import SwiftUI

@main
struct FolioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = PortfolioStore()
    @State private var navigator = Navigator()
    @AppStorage(Pref.showMenuBarExtra, store: Pref.defaults) private var showMenuBarExtra = false

    var body: some Scene {
        Window("Folio", id: "main") {
            ContentView()
                .environment(store)
                .environment(navigator)
                .frame(minWidth: 760, minHeight: 500)
        }
        .defaultSize(width: 1080, height: 720)
        .commands { FolioCommands(store: store, navigator: navigator) }

        Settings {
            SettingsView()
                .environment(store)
        }

        MenuBarExtra(isInserted: $showMenuBarExtra) {
            MenuBarView()
                .environment(store)
                .environment(navigator)
        } label: {
            MenuBarLabel()
                .environment(store)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running for the menu bar item if it's enabled.
        !Pref.defaults.bool(forKey: Pref.showMenuBarExtra)
    }
}

// MARK: - Navigation state

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case overview, crypto, cash, nfts
    var id: String { rawValue }

    var category: AssetCategory? {
        switch self {
        case .overview: nil
        case .crypto: .crypto
        case .cash: .cash
        case .nfts: .nfts
        }
    }

    var title: String { category?.title ?? "Overview" }
    var systemImage: String { category?.systemImage ?? "chart.pie" }
}

enum ActiveSheet: Identifiable {
    case crypto(CryptoHolding?)
    case cash(CashHolding?)
    case nft(NFTCollection?)
    case transaction(HoldingRef, AssetTransaction?)

    var id: String {
        switch self {
        case .crypto(let h): "crypto-\(h?.id.uuidString ?? "new")"
        case .cash(let h): "cash-\(h?.id.uuidString ?? "new")"
        case .nft: "nft"
        case .transaction(_, let t): "transaction-\(t?.id.uuidString ?? "new")"
        }
    }
}

@MainActor @Observable
final class Navigator {
    var selection: SidebarItem? = SidebarItem(rawValue: Pref.defaults.string(forKey: Pref.lastSection) ?? "") ?? .overview {
        didSet {
            Pref.defaults.set(selection?.rawValue, forKey: Pref.lastSection)
            path = []
        }
    }
    /// Holding detail pages pushed on top of the selected section.
    var path: [HoldingRef] = []
    var sheet: ActiveSheet?
}

/// The selected table rows, published so Edit ▸ Delete (⌘⌫) can act on them.
struct DeleteSelection {
    let count: Int
    var noun = "Holding"
    let perform: () -> Void

    var title: String { count > 1 ? "Delete \(count) \(noun)s" : "Delete \(noun)" }
}

extension FocusedValues {
    @Entry var deleteSelection: DeleteSelection?
    /// The holding a new transaction would go to: the open detail page or a single selected row.
    @Entry var transactionTarget: HoldingRef?
}

// MARK: - Menu bar commands

struct FolioCommands: Commands {
    let store: PortfolioStore
    let navigator: Navigator
    @AppStorage(Pref.hideBalances, store: Pref.defaults) private var hideBalances = false
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.deleteSelection) private var deleteSelection
    @FocusedValue(\.transactionTarget) private var transactionTarget

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Crypto…") { present(.crypto(nil)) }
                .keyboardShortcut("n")
            Button("Add Cash…") { present(.cash(nil)) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Add NFT…") { present(.nft(nil)) }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Button("Add Transaction…") {
                if let transactionTarget { present(.transaction(transactionTarget, nil)) }
            }
            .keyboardShortcut("t")
            .disabled(transactionTarget == nil)
            Divider()
            Button("Show Data File in Finder") { store.revealDataFile() }
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button(deleteSelection?.title ?? "Delete Holding") {
                deleteSelection?.perform()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(deleteSelection == nil)
        }

        CommandGroup(before: .sidebar) {
            ForEach(Array(SidebarItem.allCases.enumerated()), id: \.element) { index, item in
                Button(item.title) {
                    openWindow(id: "main")
                    navigator.selection = item
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
            }
            Divider()
            Button("Refresh Prices") { Task { await store.refresh() } }
                .keyboardShortcut("r")
            Toggle("Hide Balances", isOn: $hideBalances)
                .keyboardShortcut("h", modifiers: [.command, .shift])
            Divider()
        }
    }

    private func present(_ sheet: ActiveSheet) {
        openWindow(id: "main")
        navigator.sheet = sheet
    }
}
