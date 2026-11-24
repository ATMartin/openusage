import SwiftUI
import XCTest
@testable import OpenUsage

@MainActor
final class StackedMenuBarTests: XCTestCase {
    private let claude = Provider(id: "claude@1", kind: .claude)
    private let codex = Provider(id: "codex@1", kind: .codex)

    private func account(_ provider: Provider, _ keys: [String]) -> DashboardAccount {
        DashboardAccount(provider: provider, lines: keys.enumerated().map { index, key in
            let data = WidgetData(title: key, kind: .percent, used: Double(index * 10), limit: 100)
            return DashboardLine(
                descriptor: WidgetDescriptor(provider: provider, key: key, metricLabel: key, sample: data), data: data
            )
        })
    }

    private func layout(_ accounts: [DashboardAccount]) -> LayoutStore {
        LayoutStore(registry: WidgetRegistry(
            providers: accounts.map(\.provider), descriptors: accounts.flatMap { $0.lines.map(\.descriptor) }
        ), defaults: isolatedDefaults())
    }

    func testFourPinsFitInTwoStacksInSavedOrderWithoutUnpinnedLimits() {
        let accounts = [account(codex, ["Weekly", "Session", "Other"]), account(claude, ["Session", "Weekly"])]
        let pins: Set<String> = ["codex@1.Weekly", "codex@1.Session", "claude@1.Session", "claude@1.Weekly"]
        let content = MenuBarContentBuilder.buildStacked(accounts: accounts, pinned: pins, limit: .upToTwo)
        XCTAssertTrue(content.stacked)
        XCTAssertEqual(content.stacks.map(\.id), [.codex, .claude])
        XCTAssertEqual(content.stacks.map { $0.items.map(\.label) }, [["Weekly", "Session"], ["Session", "Weekly"]])
        XCTAssertEqual(content.items.count, 4)
        XCTAssertEqual(content.overflow, 0)
        XCTAssertTrue(content.accessibilityText.contains("ChatGPT Weekly 0%"))
        XCTAssertTrue(content.accessibilityText.contains("Claude Session 0%"))
    }

    func testStackLimitKeepsBothPinsAndCountsOmittedProviders() {
        let accounts = [account(claude, ["Session", "Weekly"]), account(codex, ["Session", "Weekly"])]
        let pins = Set(accounts.flatMap { $0.lines.map(\.id) })
        let one = MenuBarContentBuilder.buildStacked(accounts: accounts, pinned: pins, limit: .upToOne)
        XCTAssertEqual(one.items.map(\.id), ["claude@1.Session", "claude@1.Weekly"])
        XCTAssertEqual(one.overflow, 1)
        let icon = MenuBarContentBuilder.buildStacked(accounts: accounts, pinned: pins, limit: .iconOnly)
        XCTAssertTrue(icon.isEmpty)
        XCTAssertEqual(icon.overflow, 0)
        XCTAssertTrue(MenuBarContentBuilder.buildStacked(accounts: accounts, pinned: [], limit: .upToTwo).isEmpty)
    }

    func testSpentPinsStayInTheirPositionAndUseTheSelectedValueFormat() {
        let original = account(claude, ["Session", "Weekly"])
        let accounts = [DashboardAccount(provider: claude, lines: original.lines.map { line in
            let data = WidgetData(title: line.data.title, kind: .percent, used: 100, limit: 100, displayMode: .remaining)
            return DashboardLine(descriptor: line.descriptor, data: data)
        })]
        let content = MenuBarContentBuilder.buildStacked(
            accounts: accounts, pinned: Set(original.lines.map(\.id)), limit: .upToOne
        )
        XCTAssertEqual(content.items.map(\.label), ["Session", "Weekly"])
        XCTAssertEqual(content.items.map(\.value), ["0%", "0%"])
    }

    func testThirdPinDisablesStackingBeforeAnyUsageArrivesAndUnpinningOrHidingRestoresIt() {
        let layout = layout([account(claude, ["Session", "Weekly", "Extra"])])
        for key in ["Session", "Weekly"] { layout.setMetric("claude@1.\(key)", pinned: true) }
        XCTAssertNil(layout.stackedMenuBarWarning)
        layout.setMetric("claude@1.Extra", pinned: true)
        XCTAssertTrue(layout.stackedMenuBarWarning?.contains("Claude") == true)
        layout.setMetric("claude@1.Extra", pinned: false)
        XCTAssertNil(layout.stackedMenuBarWarning)
        layout.setMetric("claude@1.Extra", pinned: true)
        layout.setMetric("claude@1.Extra", shown: false)
        XCTAssertNil(layout.stackedMenuBarWarning)
    }

    func testPinsAcrossAccountsCountPerProviderAndUnifiedCopiesCountOnce() {
        let work = Provider(id: "claude@2", kind: .claude)
        let accounts = [account(claude, ["Session", "Weekly"]), account(work, ["Session", "Weekly"])]
        let layout = layout(accounts)
        for line in accounts.flatMap(\.lines) { layout.setMetric(line.id, pinned: true) }
        XCTAssertNotNil(layout.stackedMenuBarWarning)
        layout.setUnifiesAccounts(true, of: .claude)
        XCTAssertNil(layout.stackedMenuBarWarning)
        let content = MenuBarContentBuilder.buildStacked(
            accounts: [.unifying(accounts)], pinned: layout.state.priorityPinIDs, limit: .upToOne
        )
        XCTAssertEqual(content.items.count, 2)
        XCTAssertEqual(content.stacks.count, 1)
        layout.setUnifiesAccounts(false, of: .claude)
        XCTAssertNotNil(layout.stackedMenuBarWarning)
    }

    func testTwoAccountsShareOneProviderMarkWithoutMisleadingAccountBadge() {
        var personal = claude
        personal.badge = "P"
        let work = Provider(id: "claude@2", kind: .claude, badge: "W")
        let accounts = [account(personal, ["Session"]), account(work, ["Weekly"])]
        let content = MenuBarContentBuilder.buildStacked(
            accounts: accounts, pinned: Set(accounts.flatMap { $0.lines.map(\.id) }), limit: .upToOne
        )
        XCTAssertEqual(content.stacks.count, 1)
        XCTAssertEqual(content.items.count, 2)
        XCTAssertNil(content.stacks.first?.provider.badge)
    }

    func testStackedPreferenceDefaultsOffAndSurvivesRelaunch() {
        let defaults = isolatedDefaults()
        let store = WidgetDataStore.forTesting([], defaults: defaults)
        XCTAssertFalse(store.menuBarStacked)
        store.menuBarStacked = true
        XCTAssertTrue(WidgetDataStore.forTesting([], defaults: defaults).menuBarStacked)
    }

    func testStackedRenderingIsCompactAndRetainsUpdateIndicatorAndAccessibility() throws {
        let sample = PriorityIconsPreview.sample(limit: .upToTwo, stacked: true)
        let stacked = try XCTUnwrap(MenuBarStripRenderer.image(for: sample))
        var individual = sample
        individual.stacked = false
        let wide = try XCTUnwrap(MenuBarStripRenderer.image(for: individual))
        XCTAssertLessThan(stacked.size.width, wide.size.width * 0.65)
        XCTAssertLessThanOrEqual(stacked.size.height, 22)
        XCTAssertTrue(stacked.isTemplate)
        XCTAssertEqual(stacked.accessibilityDescription, sample.accessibilityText)
        var update = sample
        update.updateAvailable = true
        XCTAssertGreaterThan(try XCTUnwrap(MenuBarStripRenderer.image(for: update)).size.width, stacked.size.width)
        XCTAssertTrue(update.accessibilityText.contains("Update available"))
    }

    func testChangingOnlyTheLayoutInvalidatesTheStripGate() {
        let content = PriorityIconsPreview.sample(limit: .upToOne)
        var stacked = content
        stacked.stacked = true
        var shown: [MenuBarContent] = []
        var gate = StatusItemController.StripGate()
        gate.show(content) { shown.append($0) }
        gate.show(stacked) { shown.append($0) }
        gate.show(stacked) { shown.append($0) }
        XCTAssertEqual(shown, [content, stacked])
    }
}
