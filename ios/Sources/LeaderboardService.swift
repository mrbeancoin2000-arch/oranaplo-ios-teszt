import Foundation
import Combine
import Security

struct PublicRanking: Identifiable, Decodable {
    let user_id:String
    let display_name:String
    let total_steps:Int64
    let longest_run_m:Double
    var id:String { user_id }
}

enum RankingMode:String,CaseIterable { case steps,run }

private struct RankingConfig:Decodable {
    let supabase_url:String
    let supabase_publishable_key:String
    var configured:Bool {
        supabase_url.hasPrefix("https://") && supabase_publishable_key.count>35 && !supabase_url.contains("YOUR_")
    }
    static var load:RankingConfig? {
        guard let url=Bundle.main.url(forResource:"leaderboard_config",withExtension:"json"),
              let data=try? Data(contentsOf:url) else { return nil }
        return try? JSONDecoder().decode(RankingConfig.self,from:data)
    }
}

private struct RankingSession:Codable {
    var token:String
    var refresh:String
    var userID:String
    var expires:Date
}
private enum RankingKeychain {
    private static let account="hu.oranaplo.rankings.session.v1"
    static func read()->RankingSession? {
        let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrAccount as String:account,kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
        var result:CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary,&result)==errSecSuccess,let data=result as? Data else { return nil }
        return try? JSONDecoder().decode(RankingSession.self,from:data)
    }
    static func save(_ session:RankingSession) {
        guard let data=try? JSONEncoder().encode(session) else { return }
        let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrAccount as String:account]
        SecItemDelete(query as CFDictionary)
        let item:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrAccount as String:account,kSecValueData as String:data,kSecAttrAccessible as String:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        SecItemAdd(item as CFDictionary,nil)
    }
}

/// Optional, separate leaderboard service. No Google OAuth tokens or raw health/GPS data are sent.
/// Public leaderboard values are user-submitted; anti-cheat verification is not claimed.
@MainActor
final class LeaderboardService:ObservableObject {
    static let shared=LeaderboardService()
    @Published private(set) var entries:[PublicRanking]=[]
    @Published private(set) var worldRank:Int?
    @Published private(set) var busy=false
    @Published private(set) var messageKey=""
    @Published private(set) var published=UserDefaults.standard.bool(forKey:"oranaplo.ranking.published")
    @Published private(set) var activeMode:RankingMode = .steps
    @Published private(set) var reportBusy = false
    @Published private(set) var reportMessageKey = ""
    var isConfigured:Bool { RankingConfig.load?.configured == true }

    private func request(_ method:String,path:String,body:Any?=nil,authenticated:Bool=true, extra:[String:String]=[:]) async throws -> (Data,HTTPURLResponse) {
        guard let config=RankingConfig.load,config.configured,
              let base=URL(string:config.supabase_url),
              let url=URL(string:path,relativeTo:base)?.absoluteURL else { throw NSError(domain:"Leaderboard",code:1) }
        var req=URLRequest(url:url)
        req.httpMethod=method
        req.timeoutInterval=25
        req.setValue(config.supabase_publishable_key,forHTTPHeaderField:"apikey")
        req.setValue("application/json",forHTTPHeaderField:"Content-Type")
        if authenticated {
            let session=try await session()
            req.setValue("Bearer \(session.token)",forHTTPHeaderField:"Authorization")
        } else { req.setValue("Bearer \(config.supabase_publishable_key)",forHTTPHeaderField:"Authorization") }
        for (key,value) in extra { req.setValue(value,forHTTPHeaderField:key) }
        if let body { req.httpBody=try JSONSerialization.data(withJSONObject:body) }
        let (data,response)=try await URLSession.shared.data(for:req)
        guard let http=response as? HTTPURLResponse,(200..<300).contains(http.statusCode) else {
            throw NSError(domain:"Leaderboard",code:(response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return (data,http)
    }
    private func session() async throws -> RankingSession {
        if let saved=RankingKeychain.read(),saved.expires>Date().addingTimeInterval(60) { return saved }
        guard let config=RankingConfig.load,config.configured,
              let base=URL(string:config.supabase_url) else { throw NSError(domain:"Leaderboard",code:2) }
        let old=RankingKeychain.read()
        let refreshing=old != nil && !(old!.refresh.isEmpty)
        let suffix=refreshing ? "/auth/v1/token?grant_type=refresh_token" : "/auth/v1/signup"
        guard let url=URL(string:suffix,relativeTo:base)?.absoluteURL else { throw NSError(domain:"Leaderboard",code:3) }
        var req=URLRequest(url:url)
        req.httpMethod="POST"
        req.setValue(config.supabase_publishable_key,forHTTPHeaderField:"apikey")
        req.setValue("application/json",forHTTPHeaderField:"Content-Type")
        // Supabase Anonymous Sign-ins must be explicitly enabled in the backend.
        let payload:[String:Any]=refreshing ? ["refresh_token":old!.refresh] : ["data":[:]]
        req.httpBody=try JSONSerialization.data(withJSONObject:payload)
        let (data,response)=try await URLSession.shared.data(for:req)
        guard let http=response as? HTTPURLResponse,(200..<300).contains(http.statusCode),
              let json=try JSONSerialization.jsonObject(with:data) as? [String:Any],
              let access=json["access_token"] as? String,
              let refresh=json["refresh_token"] as? String else { throw NSError(domain:"Leaderboard",code:4) }
        let user=json["user"] as? [String:Any]
        let identifier=(user?["id"] as? String) ?? old?.userID ?? ""
        guard !identifier.isEmpty else { throw NSError(domain:"Leaderboard",code:5) }
        let expiry=(json["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        let new=RankingSession(token:access,refresh:refresh,userID:identifier,expires:Date().addingTimeInterval(max(60,expiry)))
        RankingKeychain.save(new)
        return new
    }

    func refresh(mode:RankingMode) async {
        activeMode=mode
        guard isConfigured else { entries=[];worldRank=nil;messageKey="leader.configure";return }
        guard !busy else { return }
        busy=true;defer { busy=false }
        do {
            let column=mode == .steps ? "total_steps" : "longest_run_m"
            let (data,_)=try await request("GET",path:"/rest/v1/oranaplo_rankings?select=user_id,display_name,total_steps,longest_run_m&published=eq.true&order=\(column).desc&limit=50")
            entries=try JSONDecoder().decode([PublicRanking].self,from:data)
            let myID = try await session().userID
            let (ownData,_) = try await request("GET",path:"/rest/v1/oranaplo_rankings?select=user_id,display_name,total_steps,longest_run_m&published=eq.true&user_id=eq.\(myID)&limit=1")
            let mine = try JSONDecoder().decode([PublicRanking].self,from:ownData).first
            if let mine {
                let value = mode == .steps ? String(mine.total_steps) : String(mine.longest_run_m)
                let (_,http)=try await request("GET",path:"/rest/v1/oranaplo_rankings?select=user_id&published=eq.true&\(column)=gt.\(value)&limit=1",extra:["Prefer":"count=exact"])
                // Content-Range: "0-0/123" or "*/0"; rank is count of strictly higher scores +1.
                let range = http.value(forHTTPHeaderField:"Content-Range") ?? ""
                worldRank = Int(String(range.split(separator:"/").last ?? "")).map { $0+1 }
            } else { worldRank=nil }
            messageKey=""
        } catch {
            entries=[];worldRank=nil;messageKey="leader.error"
        }
    }

    func publish(name:String) async {
        let trimmed=name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard (3...24).contains(trimmed.count), !trimmed.contains("\n") else { messageKey="leader.nameNeeded";return }
        guard isConfigured else { messageKey="leader.configure";return }
        guard !busy else { return }
        busy=true;defer { busy=false }
        let today=Date()
        let from=Calendar.current.startOfDay(for:OraUsageClock.firstUse)
        let total=await DailyHealthDashboard.shared.sum(.stepCount,from:from,to:today,unit:.count())
        guard let total else { messageKey="leader.permissionNeeded";return }
        do {
            let user=try await session()
            let longest=RunTracker.shared.longestCompletedRunMeters
            let body:[String:Any]=["user_id":user.userID,"display_name":trimmed,
                "total_steps":Int64(max(0,total)),"longest_run_m":max(0,longest),"published":true]
            _=try await request("POST",path:"/rest/v1/oranaplo_rankings?on_conflict=user_id",body:[body],extra:["Prefer":"resolution=merge-duplicates,return=minimal"])
            published=true
            UserDefaults.standard.set(true,forKey:"oranaplo.ranking.published")
            messageKey="leader.published"
        } catch { messageKey="leader.error" }
    }

    /// Authenticated submission only. The Supabase Edge Function forwards a
    /// category-only report to the maintainer's email using a server-side mail key.
    /// No raw diagnostic log, free-text field, GPS, HealthKit value or Google ID.
    func submitBugReport(category: SafeSupportPayload.Category, reasonCode: String) async {
        guard isConfigured else { reportMessageKey = "support.notConfigured"; return }
        guard !reportBusy else { return }
        reportBusy=true
        reportMessageKey="support.sending"
        defer { reportBusy=false }
        let version=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "unknown"
        let payload=SafeSupportPayload(category:category,reasonCode:reasonCode,version:version)
        do {
            let data=try JSONEncoder().encode(payload)
            guard let body=try JSONSerialization.jsonObject(with:data) as? [String:Any] else {
                reportMessageKey="support.error";return
            }
            _ = try await request("POST",path:"/functions/v1/bug-report",body:body)
            reportMessageKey="support.sent"
        } catch let error as NSError {
            reportMessageKey=error.code==429 ? "support.rateLimited" : "support.error"
            CrashCheckpoint.mark("report.delivery.failed")
            SafeDiagnosticTrail.mark(.reportFailed)
        }
    }

    func revoke() async {
        guard !busy, isConfigured else { messageKey="leader.configure";return }
        busy=true;defer { busy=false }
        do {
            let session=try await session()
            let id=session.userID.addingPercentEncoding(withAllowedCharacters:.urlPathAllowed) ?? session.userID
            _=try await request("DELETE",path:"/rest/v1/oranaplo_rankings?user_id=eq.\(id)")
            published=false
            entries.removeAll { $0.user_id == id }
            UserDefaults.standard.set(false,forKey:"oranaplo.ranking.published")
            messageKey="leader.revoked"
            SafeDiagnosticTrail.mark(.rankDeleted)
            worldRank=nil
        } catch { messageKey="leader.error" }
    }
}
