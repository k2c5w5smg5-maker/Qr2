import SwiftUI
import StoreKit

/// Lists the consumable credit packs.
struct PurchaseSheet: View {
    @EnvironmentObject private var store: StoreManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(store.credits == 1 ? "You have 1 credit." : "You have \(store.credits) credits.")
                        .font(.headline)
                    Text("One credit unlocks one QR code. Unlocked codes stay in My Codes and can be saved or shared as often as you like.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Credit packs") {
                    if store.products.isEmpty {
                        if store.isLoadingProducts {
                            HStack {
                                ProgressView()
                                Text("Loading prices…")
                            }
                        } else {
                            Text("Prices are unavailable right now.")
                                .foregroundStyle(.secondary)
                            Button("Try again") {
                                Task { await store.loadProducts() }
                            }
                        }
                    }
                    ForEach(store.products) { product in
                        Button {
                            Task {
                                if await store.purchase(product) { dismiss() }
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(product.displayName)
                                        .foregroundStyle(.primary)
                                    Text(product.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(product.displayPrice)
                                    .fontWeight(.semibold)
                            }
                        }
                        .disabled(store.isPurchasing)
                    }
                }

                Section {
                    Text("Credits are consumable purchases and are kept on this device. Prices are set by the App Store in your local currency.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Buy credits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
