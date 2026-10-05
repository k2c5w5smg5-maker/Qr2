import Foundation
import Combine
import StoreKit

/// Consumable in-app purchases. Each purchase adds credits; unlocking a code spends one.
/// Product IDs must match the ones configured in App Store Connect (and Products.storekit).
enum CreditPack: String, CaseIterable {
    case single = "com.example.qrmaker.credit.1"
    case ten = "com.example.qrmaker.credit.10"

    var credits: Int {
        switch self {
        case .single: return 1
        case .ten: return 10
        }
    }
}

@MainActor
final class StoreManager: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var credits: Int
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isPurchasing = false
    @Published var lastError: String?

    private let creditsKey = "qrmaker.credits"
    private var updatesTask: Task<Void, Never>?

    init() {
        credits = UserDefaults.standard.integer(forKey: creditsKey)
        updatesTask = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                _ = await self?.handle(result)
            }
        }
        Task {
            await loadProducts()
            await finishPendingTransactions()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    /// The product used by the main "Unlock" button.
    var singleProduct: Product? {
        products.first { $0.id == CreditPack.single.rawValue }
    }

    func creditCount(for product: Product) -> Int {
        CreditPack(rawValue: product.id)?.credits ?? 0
    }

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let fetched = try await Product.products(for: CreditPack.allCases.map(\.rawValue))
            products = fetched.sorted { $0.price < $1.price }
            if fetched.isEmpty {
                lastError = "Products are not available yet. Check the StoreKit configuration or App Store Connect."
            }
        } catch {
            lastError = "Could not load prices: \(error.localizedDescription)"
        }
    }

    /// Returns true when the purchase completed and credits were added.
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                return await handle(verification)
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Spends one credit. Returns false when the balance is empty.
    func useCredit() -> Bool {
        guard credits > 0 else { return false }
        setCredits(credits - 1)
        return true
    }

    @discardableResult
    private func handle(_ result: VerificationResult<StoreKit.Transaction>) async -> Bool {
        guard case .verified(let transaction) = result else {
            lastError = "This purchase could not be verified."
            return false
        }
        if transaction.revocationDate == nil, let pack = CreditPack(rawValue: transaction.productID) {
            setCredits(credits + pack.credits)
        }
        await transaction.finish()
        return true
    }

    /// Credits purchases that were interrupted (for example by a crash) before being finished.
    private func finishPendingTransactions() async {
        for await result in StoreKit.Transaction.unfinished {
            await handle(result)
        }
    }

    private func setCredits(_ value: Int) {
        credits = max(0, value)
        UserDefaults.standard.set(credits, forKey: creditsKey)
    }
}
