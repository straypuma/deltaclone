import SwiftUI

struct NFTView: View {
    let valuation: Valuation
    @Environment(PortfolioStore.self) private var store
    @Environment(Navigator.self) private var navigator

    var body: some View {
        if valuation.nftGroups.isEmpty {
            ContentUnavailableView {
                Label("No NFTs", systemImage: AssetCategory.nfts.systemImage)
            } description: {
                Text("Add your Milady Maker and Remilio Babies by token number. They're valued at the collection floor.")
            } actions: {
                Button("Add NFT") { navigator.sheet = .nft(nil) }
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SummaryHeader(title: "NFTs", value: valuation.total(.nfts), currency: valuation.base,
                                  change: valuation.change(.nfts), changePercent: valuation.changePercent(.nfts))
                    Divider()
                    VStack(alignment: .leading, spacing: 32) {
                        ForEach(valuation.nftGroups) { group in
                            collection(group)
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    private func collection(_ group: NFTGroup) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                RemoteImage(url: group.imageURL, maxPixel: 120)
                    .frame(width: 40, height: 40)
                    .clipShape(.rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.collection.name).font(.title3.weight(.semibold))
                    Text(floorText(group)).font(.callout).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Format.money(group.value, valuation.base))
                        .font(.title3.weight(.semibold)).monospacedDigit().privacySensitive()
                    ChangeLabel(percent: group.change24h).font(.callout)
                }
                Button {
                    navigator.sheet = .nft(group.collection)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add \(group.collection.tokenName)")
                .padding(.leading, 8)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 16)],
                      alignment: .leading, spacing: 16) {
                ForEach(group.tokens) { token in
                    TokenCard(token: token, floorETH: group.floorETH)
                        .contextMenu { menu(token) }
                }
            }
        }
    }

    private func floorText(_ group: NFTGroup) -> String {
        let count = "\(group.tokens.count) owned"
        guard let eth = group.floorETH else { return count }
        return "\(count) · Floor \(Format.eth(eth)) (\(Format.money(group.floor, valuation.base)))"
    }

    @ViewBuilder
    private func menu(_ token: NFTHolding) -> some View {
        Link("View on OpenSea", destination: token.collection.marketplaceURL(token: token.tokenID))
        Button("Copy Token Number") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("\(token.tokenID)", forType: .string)
        }
        Divider()
        Button("Remove", role: .destructive) { store.deleteNFTs([token.id]) }
    }
}

struct TokenCard: View {
    let token: NFTHolding
    let floorETH: Double?
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear
                .aspectRatio(4 / 5, contentMode: .fit)
                .overlay { RemoteImage(url: token.collection.imageURL(token: token.tokenID), maxPixel: 480) }
                .clipShape(.rect(cornerRadius: 10))
            HStack {
                Text("\(token.collection.tokenName) #\(token.tokenID)")
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .accessibilityIdentifier("token-\(token.collection.rawValue)-\(token.tokenID)")
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 4)
        }
        .padding(8)
        .background(.background.secondary, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).strokeBorder(.separator.opacity(hovering ? 1 : 0.5))
        }
        .scaleEffect(hovering ? 1.015 : 1)
        .animation(.snappy(duration: 0.2), value: hovering)
        .onHover { hovering = $0 }
    }
}

// MARK: - Add

struct NFTSheet: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var collection: NFTCollection
    @State private var tokensText = ""

    init(collection: NFTCollection) {
        _collection = State(initialValue: collection)
    }

    private var tokens: [Int] {
        tokensText.split { !$0.isNumber }.compactMap { Int($0) }.filter { $0 >= 0 && $0 < 100_000 }
    }

    private var owned: Set<Int> {
        Set(store.portfolio.nfts.filter { $0.collection == collection }.map(\.tokenID))
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("Collection", selection: $collection) {
                        ForEach(NFTCollection.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("collection")
                    TextField("Token numbers", text: $tokensText, prompt: Text("e.g. 1234, 5678"))
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("tokens")
                } footer: {
                    Text("Separate multiple tokens with commas or spaces.")
                        .foregroundStyle(.secondary)
                }

                if !tokens.isEmpty {
                    Section("Preview") {
                        ScrollView(.horizontal) {
                            HStack(spacing: 10) {
                                ForEach(Array(Set(tokens)).sorted(), id: \.self) { id in
                                    VStack(spacing: 4) {
                                        RemoteImage(url: collection.imageURL(token: id), maxPixel: 480)
                                            .frame(width: 76, height: 95)
                                            .clipShape(.rect(cornerRadius: 8))
                                        Text("#\(id)").font(.caption).monospacedDigit()
                                            .foregroundStyle(owned.contains(id) ? .tertiary : .secondary)
                                    }
                                    .opacity(owned.contains(id) ? 0.45 : 1)
                                    .help(owned.contains(id) ? "Already added" : "")
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(addTitle) {
                    store.addNFTs(collection, tokens: tokens)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(Set(tokens).subtracting(owned).isEmpty)
                .accessibilityIdentifier("confirm")
            }
            .padding([.horizontal, .bottom], 20)
            .padding(.top, 4)
        }
        .frame(width: 440, height: tokens.isEmpty ? 212 : 370)
        .animation(.snappy, value: tokens.isEmpty)
    }

    private var addTitle: String {
        let count = Set(tokens).subtracting(owned).count
        return count > 1 ? "Add \(count)" : "Add"
    }
}
