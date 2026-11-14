import Foundation
import StoreKit
import Combine

/// No server, password or manually settable Pro flag. Purchase state comes only
/// from verified StoreKit 2 transactions (including restored purchases).
@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()
    static let productID = "hu.oranaplo.pro.yearly"

    @Published private(set) var proActive = false
    @Published private(set) var product: Product?
    @Published private(set) var expiration: Date?
    @Published private(set) var busy = false
    @Published private(set) var messageKey = "tier.expired"
    @Published private(set) var technicalError = ""
    private var updatesTask: Task<Void, Never>?

    private init() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refreshEntitlement()
            }
        }
    }
    deinit { updatesTask?.cancel() }

    func load() async {
        DiagnosticCenter.record(.storeProductsBegin, area: .storekit)
        await refreshEntitlement()
        do {
            product = try await Product.products(for: [Self.productID]).first(where: { $0.id == Self.productID })
            if product == nil { messageKey = proActive ? "tier.active" : "tier.unavailable" }
            DiagnosticCenter.record(product == nil ? .storeProductsFailed : .storeProductsReady, area: .storekit,
                                    severity: product == nil ? .warning : .info)
        } catch {
            technicalError = error.localizedDescription
            DiagnosticCenter.record(.storeProductsFailed, area: .storekit, severity: .failure)
            messageKey = proActive ? "tier.active" : "tier.unavailable"
        }
    }

    func refreshEntitlement() async {
        var verified = false
        var expires: Date?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.productID,
                  transaction.revocationDate == nil,
                  !transaction.isUpgraded else { continue }
            if let end = transaction.expirationDate, end > Date() {
                verified = true
                if expires == nil || end > expires! { expires = end }
            }
        }
        proActive = verified
        expiration = expires
        messageKey = verified ? "tier.active" : "tier.expired"
        DiagnosticCenter.record(.entitlementRefresh, area: .storekit)
    }

    func purchase() async {
        guard let product, !busy else { messageKey = "tier.unavailable"; return }
        busy = true
        DiagnosticCenter.record(.purchaseBegin, area: .storekit)
        defer { busy = false }
        do {
            let options: Set<Product.PurchaseOption> = ReferralService.shared.appAccountToken.map { [.appAccountToken($0)] } ?? []
            let outcome = try await product.purchase(options: options)
            switch outcome {
            case .success(let result):
                switch result {
                case .verified(let transaction):
                    await transaction.finish()
                    await refreshEntitlement()
                    DiagnosticCenter.record(.purchaseVerified, area: .storekit)
                    messageKey = proActive ? "tier.thanks" : "tier.problem"
                case .unverified:
                    DiagnosticCenter.record(.purchaseUnverified, area: .storekit, severity: .failure)
                    messageKey = "tier.problem"
                }
            case .pending:
                DiagnosticCenter.record(.purchasePending, area: .storekit)
                messageKey = "tier.pending"
            case .userCancelled:
                DiagnosticCenter.record(.purchaseCancelled, area: .storekit)
                messageKey = "tier.cancelled"
            @unknown default: messageKey = "tier.problem"
            }
        } catch {
            technicalError = error.localizedDescription
            DiagnosticCenter.record(.purchaseFailed, area: .storekit, severity: .failure)
            messageKey = "tier.problem"
        }
    }

    func restore() async {
        busy = true
        defer { busy = false }
        do {
            try await AppStore.sync()
            await refreshEntitlement()
        } catch {
            technicalError = error.localizedDescription
            DiagnosticCenter.record(.restoreFailed, area: .storekit, severity: .failure)
            messageKey = "tier.problem"
        }
    }
}
