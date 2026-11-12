import Foundation
import Combine
import CryptoKit

struct SleepRating: Identifiable, Codable {
    var id: UUID = UUID()
    let date: Date
    let score: Int
}
struct RoomReading: Identifiable, Codable {
    var id: UUID = UUID()
    let date: Date
    let temperatureC: Double?
    let humidityPercent: Double?
    let co2PPM: Double?
    let source: String // manual reading or user's external sensor
}
struct WaterEntry: Identifiable, Codable {
    var id: UUID = UUID()
    let date: Date
    let milliliters: Int
    let source: String
}
struct MedicationEntry: Identifiable, Codable {
    var id: UUID = UUID()
    let date: Date
    let name: String
    let dose: String
    let taken: Bool
}

@MainActor
final class WellnessDiary: ObservableObject {
    static let shared = WellnessDiary()
    @Published private(set) var sleepRatings:[SleepRating] = []
    @Published private(set) var rooms:[RoomReading] = []
    @Published private(set) var medicines:[MedicationEntry] = []
    @Published private(set) var water:[WaterEntry] = []
    @Published private(set) var storageError:String?
    private var accountKey="local-device"
    private let folder:URL = {
        let directory=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("OraNaplo/Wellness",isDirectory:true)
        try? FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        return directory
    }()
    private var file:URL { folder.appendingPathComponent("journal-\(accountKey).json") }
    private struct Stored:Codable {
        var ratings:[SleepRating]
        var rooms:[RoomReading]
        var medicines:[MedicationEntry]
        var water:[WaterEntry]
        enum CodingKeys:String,CodingKey { case ratings,rooms,medicines,water }
        init(ratings:[SleepRating],rooms:[RoomReading],medicines:[MedicationEntry],water:[WaterEntry]) {
            self.ratings=ratings;self.rooms=rooms;self.medicines=medicines;self.water=water
        }
        init(from decoder:Decoder) throws {
            let c=try decoder.container(keyedBy:CodingKeys.self)
            ratings=try c.decode([SleepRating].self,forKey:.ratings)
            rooms=try c.decode([RoomReading].self,forKey:.rooms)
            medicines=try c.decode([MedicationEntry].self,forKey:.medicines)
            water=try c.decodeIfPresent([WaterEntry].self,forKey:.water) ?? []
        }
    }
    private init() { loadSelected() }
    func selectAccount(_ email:String) {
        let normalized=email.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
        let next:String
        if normalized.isEmpty { next="local-device" }
        else {
            let sha=SHA256.hash(data:Data(normalized.utf8)).map{String(format:"%02x",$0)}.joined()
            next=String(sha.prefix(24))
        }
        guard next != accountKey else { return }
        accountKey=next
        loadSelected()
    }
    private func loadSelected() {
        // Never retain another account's medical notes during a Google identity change.
        sleepRatings=[];rooms=[];medicines=[];water=[];storageError=nil
        guard FileManager.default.fileExists(atPath:file.path) else { return }
        do {
            let value=try JSONDecoder().decode(Stored.self,from:Data(contentsOf:file))
            sleepRatings=value.ratings;rooms=value.rooms;medicines=value.medicines;water=value.water
        } catch { storageError="A korábbi egészségnapló nem olvasható. Az eredeti fájl megmaradt." }
    }
    private func save(_ value:Stored) throws {
        if storageError != nil { throw DiaryError.corrupted }
        let data=try JSONEncoder().encode(value)
        try data.write(to:file,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
    }
    func rateSleep(_ score:Int,for date:Date=Date()) throws {
        guard (1...10).contains(score) else { throw DiaryError.invalidValue }
        var updated=sleepRatings
        updated.append(SleepRating(date:date,score:score))
        try save(Stored(ratings:updated,rooms:rooms,medicines:medicines,water:water))
        sleepRatings=updated
    }
    func addRoom(temperature:Double?,humidity:Double?,co2:Double?,source:String="manual") throws {
        guard temperature != nil || humidity != nil || co2 != nil else { throw DiaryError.invalidValue }
        if let t=temperature, (!t.isFinite || t < -50 || t > 80) { throw DiaryError.invalidValue }
        if let h=humidity, (!h.isFinite || h < 0 || h > 100) { throw DiaryError.invalidValue }
        if let c=co2, (!c.isFinite || c < 0 || c > 100000) { throw DiaryError.invalidValue }
        var updated=rooms
        updated.append(RoomReading(date:Date(),temperatureC:temperature,humidityPercent:humidity,co2PPM:co2,source:source))
        try save(Stored(ratings:sleepRatings,rooms:updated,medicines:medicines,water:water))
        rooms=updated
    }
    func medication(name:String,dose:String,taken:Bool) throws {
        let cleanName=name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard (1...100).contains(cleanName.count), dose.count < 60 else { throw DiaryError.invalidValue }
        var updated=medicines
        updated.append(MedicationEntry(date:Date(),name:cleanName,dose:dose,taken:taken))
        try save(Stored(ratings:sleepRatings,rooms:rooms,medicines:updated,water:water))
        medicines=updated
    }
    func addWater(_ milliliters:Int,source:String="manual",at date:Date=Date(),id:UUID=UUID()) throws {
        guard (1...5000).contains(milliliters) else { throw DiaryError.invalidValue }
        guard !water.contains(where:{$0.id == id}) else { return }
        var updated=water
        updated.append(WaterEntry(id:id,date:date,milliliters:milliliters,source:source))
        try save(Stored(ratings:sleepRatings,rooms:rooms,medicines:medicines,water:updated))
        water=updated
    }
    func erase() throws {
        try save(Stored(ratings:[],rooms:[],medicines:[],water:[]))
        sleepRatings=[];rooms=[];medicines=[];water=[]
    }
}
enum DiaryError:LocalizedError {
    case corrupted,invalidValue
    var errorDescription:String? {
        switch self {
        case .corrupted:return "A korábbi napló sérült; nem írjuk felül."
        case .invalidValue:return "Hiányzó vagy érvénytelen adat."
        }
    }
}
