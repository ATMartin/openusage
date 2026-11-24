extension LayoutStore {
    /// Count saved pins even before usage arrives. Unified copies of one metric count once.
    var stackedMenuBarWarning: String? {
        var kinds: [ProviderKind] = []
        var pins: [ProviderKind: Set<String>] = [:]
        for group in displayGroups {
            let kind = group.provider.kind
            if !kinds.contains(kind) { kinds.append(kind) }
            for metric in group.metrics where state.priorityPinIDs.contains(metric.id) {
                pins[kind, default: []].insert(group.unifiesAccounts ? metric.kindScopedKey : metric.id)
            }
        }
        let names = kinds.filter { (pins[$0]?.count ?? 0) > 2 }.map(\.displayName)
        guard !names.isEmpty else { return nil }
        return "Stacked is unavailable for \(names.joined(separator: ", ")): more than two metrics are pinned per provider. Unpin metrics to use at most two per provider."
    }
}
