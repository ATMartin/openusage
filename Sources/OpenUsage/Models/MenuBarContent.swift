import Foundation

struct MenuBarContent: Equatable {
    struct Item: Equatable, Identifiable {
        let id: String
        let provider: Provider
        let label: String
        let shortLabel: String
        let value: String
    }

    let items: [Item]
    var stacked = false
    var overflow = 0
    var updateAvailable = false

    var isEmpty: Bool { items.isEmpty }

    struct Stack: Identifiable {
        let id: ProviderKind
        var items: [Item]

        var provider: Provider {
            var provider = items[0].provider
            if items.contains(where: { $0.provider.id != provider.id }) { provider.badge = nil }
            return provider
        }
    }

    /// First occurrence wins, preserving the user's provider, account, and metric order.
    var stacks: [Stack] {
        items.reduce(into: []) { stacks, item in
            if let index = stacks.firstIndex(where: { $0.id == item.provider.kind }) {
                stacks[index].items.append(item)
            } else {
                stacks.append(Stack(id: item.provider.kind, items: [item]))
            }
        }
    }

    var accessibilityText: String {
        let shown = items.map { "\($0.provider.fullName) \($0.label) \($0.value)" }
        let more = overflow > 0 ? ["\(overflow) more"] : []
        let update = updateAvailable ? ["Update available"] : []
        return (shown + more + update).joined(separator: "; ")
    }
}

@MainActor
enum MenuBarContentBuilder {
    private static let genericWords: Set<String> = ["models", "bot", "usage"]

    /// Pins only, including spent pins, in saved order. The limit counts provider stacks.
    /// LayoutStore validates all pins (including metrics without readings) before this is used.
    static func buildStacked(accounts: [DashboardAccount], pinned: Set<String>, limit: MenuBarLimit) -> MenuBarContent {
        guard limit != .iconOnly else { return MenuBarContent(items: []) }
        let items = accounts.flatMap { account in
            account.lines.filter { $0.metricIDs.contains(where: pinned.contains) }.map { line in
                MenuBarContent.Item(
                    id: line.id, provider: account.provider, label: line.data.title,
                    shortLabel: shortLabel(line.data.title), value: line.data.menuBarValue
                )
            }
        }
        let stacks = MenuBarContent(items: items).stacks
        return MenuBarContent(
            items: stacks.prefix(limit.count).flatMap(\.items), stacked: true,
            overflow: max(0, stacks.count - limit.count)
        )
    }

    /// Only what's running out, or with `alwaysShows` every section of the Priority tab in its order, top to bottom.
    static func build(board: PriorityBoard, limit: MenuBarLimit, alwaysShows: Bool = false) -> MenuBarContent {
        guard limit != .iconOnly else { return MenuBarContent(items: []) }
        let counted = alwaysShows
            ? board.pinned.map { ($0.provider, $0.line) } + (board.attention + board.useItOrLoseIt).map { ($0.provider, $0.line) }
            : board.runningOut.map { ($0.provider, $0.line) }
        let usedUp = alwaysShows ? board.usedUp.map { ($0.provider, $0.line) } : []
        let shown = (counted + usedUp).prefix(limit.count).map { provider, line in
            let label = line.data.title
            return MenuBarContent.Item(
                id: line.id,
                provider: provider,
                label: label,
                shortLabel: shortLabel(label),
                value: line.data.menuBarValue
            )
        }
        return MenuBarContent(items: shown, overflow: max(0, counted.count - shown.count))
    }

    static func shortLabel(_ label: String) -> String {
        var words = label.split(separator: " ")
        guard words.count > 1, let last = words.last, genericWords.contains(last.lowercased()) else { return label }
        words.removeLast()
        return words.joined(separator: " ")
    }
}
