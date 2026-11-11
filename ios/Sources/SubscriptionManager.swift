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
        await refreshEntitlement()
        do {
            product = try await Product.products(for: [Self.productID]).first(where: { $0.id == Self.productID })
            if product == nil { messageKey = proActive ? "tier.active" : "tier.unavailable" }
        } catch {
            technicalError = error.localizedDescription
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
    }

    func purchase() async {
        guard let product, !busy else { messageKey = "tier.unavailable"; return }
        busy = true
        defer { busy = false }
        do {
            let outcome = try await product.purchase()
            switch outcome {
            case .success(let result):
                switch result {
                case .verified(let transaction):
                    await transaction.finish()
                    await refreshEntitlement()
                    messageKey = proActive ? "tier.thanks" : "tier.problem"
                case .unverified:
                    messageKey = "tier.problem"
                }
            case .pending: messageKey = "tier.pending"
            case .userCancelled: messageKey = "tier.cancelled"
            @unknown default: messageKey = "tier.problem"
            }
        } catch {
            technicalError = error.localizedDescription
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
            messageKey = "tier.problem"
        }
    }
}
