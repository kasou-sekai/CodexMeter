import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var service: CodexUsageService
    @ObservedObject var settings: AppSettings
    @ObservedObject var history: UsageHistoryModel
    @ObservedObject var updateChecker: UpdateChecker
    @Environment(\.openWindow) private var openWindow
    @State private var maximumPopoverHeight = PopoverLayoutMetrics.initialMaximumHeight

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
                .layoutPriority(1)

            ScrollView {
                scrollableContent
            }
            .clipped()

            bottomControls
                .layoutPriority(1)
        }
        .padding(14)
        .frame(width: 360)
        .frame(maxHeight: maximumPopoverHeight)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            PopoverScreenHeightReader { visibleHeight in
                let updatedHeight = PopoverLayoutMetrics.maximumHeight(
                    forScreenVisibleHeight: visibleHeight
                )
                guard abs(maximumPopoverHeight - updatedHeight) > 0.5 else { return }
                maximumPopoverHeight = updatedHeight
            }
        }
        .onAppear {
            settings.refreshLaunchAtLoginStatus()
            service.refreshIfNeeded()
        }
        .task(id: history.dataRevision) {
            // Load the preferred weekly cycle whenever the popover appears or
            // a successful refresh records a new local history sample.
            await history.load()
        }
        .alert(
            L10n.string("settings.error_title"),
            isPresented: Binding(
                get: { settings.settingsError != nil },
                set: { if !$0 { settings.clearSettingsError() } }
            )
        ) {
            Button(L10n.string("action.ok")) {
                settings.clearSettingsError()
            }

            if settings.settingsDestination != nil {
                Button(L10n.string("action.open_system_settings")) {
                    settings.openRelevantSystemSettings()
                    settings.clearSettingsError()
                }
            }
        } message: {
            Text(settings.settingsError ?? "")
        }
    }

    private var scrollableContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if settings.developerPreviewEnabled {
                previewModeBanner
            }

            if service.isStale {
                staleBanner
            }

            if case .updateAvailable(let release) = updateChecker.state {
                updateBanner(release)
            }

            Divider()

            if service.isLoading && service.windows.isEmpty {
                loadingView
            } else if let errorMessage = service.errorMessage,
                      service.windows.isEmpty {
                errorView(errorMessage)
            } else {
                if let errorMessage = service.errorMessage {
                    inlineErrorView(errorMessage)
                }

                configurableContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bottomControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
            SettingsSection(service: service, settings: settings)
            Divider()
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func updateBanner(_ release: AvailableUpdate) -> some View {
        Button {
            openWindow(id: CodexMeterWindowID.about)
            NSApplication.shared.activate(ignoringOtherApps: true)
        } label: {
            HStack {
                Label(
                    L10n.format("updates.available_format", release.version),
                    systemImage: "arrow.down.circle.fill"
                )
                Spacer()
                Image(systemName: "chevron.right")
            }
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(.blue)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string("app.title"))
                    .font(.headline)

                Text(service.accountDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if service.isRefreshInFlight {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                service.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help(L10n.string("action.refresh"))
            .disabled(service.isRefreshInFlight)
        }
    }

    private var staleBanner: some View {
        Label(L10n.string("data.stale"), systemImage: "clock.badge.exclamationmark")
            .font(.caption)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private var previewModeBanner: some View {
        HStack(spacing: 8) {
            Label(
                L10n.string("developer.preview_mode_active"),
                systemImage: "eye.trianglebadge.exclamationmark"
            )
            .font(.caption)
            .foregroundStyle(.orange)

            Spacer()

            Button(L10n.string("developer.return_to_live")) {
                settings.developerPreviewEnabled = false
            }
            .buttonStyle(.plain)
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private var loadingView: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(L10n.string("loading.usage"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 90)
    }

    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L10n.string("error.cannot_read"), systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(L10n.string("action.retry")) {
                service.refresh()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
    }

    private func inlineErrorView(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var visibleQuotaWindows: [CodexUsageWindow] {
        settings.popoverContent.visibleQuotaWindows(from: service.windows)
    }

    private var resetCreditsSummary: CodexRateLimitResetCreditsSummary? {
        guard let summary = service.rateLimitResetCredits,
              summary.hasAvailableCredits else {
            return nil
        }
        return summary
    }

    private var displayedSections: [PopoverContentSection] {
        settings.popoverContent.sectionOrder.filter { section in
            guard settings.popoverContent.isSectionVisible(section) else { return false }

            switch section {
            case .quotaWindows:
                return !visibleQuotaWindows.isEmpty
            case .resetCredits:
                return resetCreditsSummary != nil
            case .quotaHistory, .tokenActivity:
                return true
            }
        }
    }

    private var configurableContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(displayedSections) { section in
                if section != displayedSections.first {
                    Divider()
                }

                popoverSection(section)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func popoverSection(_ section: PopoverContentSection) -> some View {
        switch section {
        case .quotaWindows:
            usageView
        case .resetCredits:
            if let summary = resetCreditsSummary {
                ResetCreditsSection(
                    summary: summary,
                    appearance: settings.developerAppearance
                )
                .id(settings.language.rawValue)
            }
        case .quotaHistory:
            Button(action: openHistoryWindow) {
                menuQuotaSection
            }
            .buttonStyle(.plain)
        case .tokenActivity:
            Button(action: openHistoryWindow) {
                menuTokenSection
            }
            .buttonStyle(.plain)
        }
    }

    private var usageView: some View {
        // Update countdowns and pace locally every minute without another API call.
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            HStack(alignment: .top, spacing: 6) {
                ForEach(visibleQuotaWindows) { window in
                    UsageWindowRow(
                        window: window,
                        now: context.date,
                        appearance: settings.developerAppearance
                    )
                }

                if let credits = service.purchasedCredits {
                    PurchasedCreditsView(snapshot: credits)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .id(settings.language.rawValue)
    }

    private var menuQuotaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string("history.quota.title"))
                        .font(.subheadline.weight(.semibold))
                    Text(L10n.string("history.quota.fixed_cycle"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let remaining = menuQuotaRemaining {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(remaining)%")
                            .font(.headline.monospacedDigit())
                        Text(L10n.string("quota.remaining"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let cycle = menuQuotaCycle {
                QuotaHistoryChart(series: cycle, showsAxes: false)
                    .frame(height: 92)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line")
                        .foregroundStyle(HistoryPalette.accent)
                    Text(L10n.string("history.empty.message"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var menuTokenSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string("history.tokens.title"))
                        .font(.subheadline.weight(.semibold))
                    Text(TokenActivityRange.month.localizedName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !menuTokenPoints.isEmpty {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(compactToken(menuTokenTotal))
                            .font(.headline.monospacedDigit())
                        Text(L10n.string("history.tokens.total"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if menuTokenPoints.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.fill")
                        .foregroundStyle(HistoryPalette.accent)
                    Text(historySummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            } else {
                CompactTokenActivityChart(points: menuTokenPoints)
                    .frame(height: 92)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var menuQuotaCycle: QuotaHistorySeries? {
        let window = QuotaWindowSelection.preferredDefault(from: history.quotaWindows)
        guard let window else { return nil }

        let samples = history.quotaSamples.filter { $0.windowID == window.id }
        guard let cycle = QuotaHistorySeries.makeCurrentCycle(
            samples: samples,
            window: window,
            now: Date()
        ), !cycle.samples.isEmpty else {
            return nil
        }
        return cycle
    }

    private var menuQuotaRemaining: Int? {
        menuQuotaCycle?.samples.last?.remainingPercent
    }

    private func openHistoryWindow() {
        openWindow(id: CodexMeterWindowID.history)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private var menuTokenPoints: [TokenChartPoint] {
        TokenChartData.filtered(
            TokenChartData.points(from: history.tokenUsage ?? service.tokenUsage),
            range: .month,
            now: Date()
        )
    }

    private var menuTokenTotal: Int64 {
        menuTokenPoints.reduce(0) { partial, point in
            let (sum, overflow) = partial.addingReportingOverflow(point.tokens)
            return overflow ? Int64.max : sum
        }
    }

    private func compactToken(_ value: Int64) -> String {
        CompactTokenFormatter.string(value, locale: L10n.locale)
    }

    private var historySummary: String {
        if let lifetime = service.tokenUsage?.summary.lifetimeTokens {
            return L10n.format(
                "history.summary.tokens_format",
                CompactTokenFormatter.string(lifetime, locale: L10n.locale)
            )
        }
        return L10n.string("history.summary.local")
    }

    private var footer: some View {
        HStack {
            if let lastUpdated = service.lastUpdated {
                Text(L10n.format(
                    "status.updated_at_format",
                    L10n.formattedTime(lastUpdated)
                ))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            } else {
                Text(L10n.string("status.local_server"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button(L10n.string("action.quit")) {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }
}

private enum PopoverLayoutMetrics {
    private static let fallbackScreenHeight: CGFloat = 720
    private static let screenEdgeClearance: CGFloat = 16

    static var initialMaximumHeight: CGFloat {
        maximumHeight(forScreenVisibleHeight: NSScreen.main?.visibleFrame.height)
    }

    static func maximumHeight(forScreenVisibleHeight visibleHeight: CGFloat?) -> CGFloat {
        max(1, (visibleHeight ?? fallbackScreenHeight) - screenEdgeClearance)
    }
}

/// Reports the visible height of the display that actually contains the menu
/// bar popover, including updates after display or scaling changes.
private struct PopoverScreenHeightReader: NSViewRepresentable {
    let onVisibleHeightChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScreenTrackingView {
        ScreenTrackingView(onVisibleHeightChange: onVisibleHeightChange)
    }

    func updateNSView(_ nsView: ScreenTrackingView, context: Context) {
        nsView.onVisibleHeightChange = onVisibleHeightChange
        nsView.publishVisibleHeight()
    }

    final class ScreenTrackingView: NSView {
        var onVisibleHeightChange: (CGFloat) -> Void
        private var observers: [NSObjectProtocol] = []

        init(onVisibleHeightChange: @escaping (CGFloat) -> Void) {
            self.onVisibleHeightChange = onVisibleHeightChange
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            removeObservers()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            installObservers()
            publishVisibleHeight()
        }

        func publishVisibleHeight() {
            guard let visibleHeight = window?.screen?.visibleFrame.height else { return }
            let callback = onVisibleHeightChange
            DispatchQueue.main.async {
                callback(visibleHeight)
            }
        }

        private func installObservers() {
            removeObservers()

            if let window {
                observers.append(NotificationCenter.default.addObserver(
                    forName: NSWindow.didChangeScreenNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    self?.publishVisibleHeight()
                })
            }

            observers.append(NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.publishVisibleHeight()
            })
        }

        private func removeObservers() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
        }
    }
}

/// Presents banked reset availability without exposing a redemption action.
private struct ResetCreditsSection: View {
    let summary: CodexRateLimitResetCreditsSummary
    let appearance: MenuBarAppearance
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            content(at: context.date)
        }
    }

    private func content(at date: Date) -> some View {
        let usableCredits = summary.usableCredits(at: date)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.string("reset_credits.title"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(countText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ResetCreditsTimeline(
                credits: usableCredits,
                now: date,
                appearance: appearance,
                colorScheme: colorScheme
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var countText: String {
        guard summary.hasAvailableCredits else {
            return L10n.string("reset_credits.none")
        }
        return L10n.format("reset_credits.available_format", summary.availableCount)
    }

}

/// Places reset-card expirations on one fixed axis covering the next 30 days.
private struct ResetCreditsTimeline: View {
    let credits: [CodexRateLimitResetCredit]
    let now: Date
    let appearance: MenuBarAppearance
    let colorScheme: ColorScheme

    private let duration: TimeInterval = 30 * 24 * 60 * 60

    private var endDate: Date {
        now.addingTimeInterval(duration)
    }

    private var plottedCredits: [CodexRateLimitResetCredit] {
        credits.filter { credit in
            guard let expiresAt = credit.expiresAt else { return false }
            return expiresAt >= now && expiresAt <= endDate
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.tertiary)
                        .frame(height: 2)
                        .position(x: proxy.size.width / 2, y: 14)

                    ForEach(plottedCredits) { credit in
                        if let expiresAt = credit.expiresAt {
                            Circle()
                                .fill(tint(for: credit))
                                .overlay(Circle().stroke(.background, lineWidth: 2))
                                .frame(width: 10, height: 10)
                                .position(
                                    x: xPosition(for: expiresAt, width: proxy.size.width),
                                    y: 14
                                )
                                .help(L10n.format(
                                    "reset_credits.expires_format",
                                    L10n.formattedDateTime(expiresAt)
                                ))
                                .accessibilityLabel(
                                    credit.title ?? L10n.string("reset_credits.title")
                                )
                                .accessibilityValue(L10n.format(
                                    "reset_credits.expires_format",
                                    L10n.formattedDateTime(expiresAt)
                                ))
                        }
                    }
                }
            }
            .frame(height: 28)

            HStack {
                Text(L10n.formattedShortDate(now))
                Spacer()
                Text(L10n.formattedShortDate(endDate))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func xPosition(for date: Date, width: CGFloat) -> CGFloat {
        let fraction = date.timeIntervalSince(now) / duration
        return min(width - 5, max(5, width * fraction))
    }

    private func tint(for credit: CodexRateLimitResetCredit) -> Color {
        switch credit.expirationAttentionLevel(at: now) {
        case .normal:
            appearance.normalColor.swiftUIColor(for: colorScheme)
        case .warning:
            appearance.warningColor.swiftUIColor(for: colorScheme)
        case .critical, .none:
            appearance.criticalColor.swiftUIColor(for: colorScheme)
        }
    }
}

/// Opens the shared settings window without expanding the menu bar popover.
private struct SettingsSection: View {
    @ObservedObject var service: CodexUsageService
    @ObservedObject var settings: AppSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            openWindow(id: CodexMeterWindowID.settings)
            NSApplication.shared.activate(ignoringOtherApps: true)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "gearshape")
                Text(L10n.string("settings.title"))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("settings.title"))
    }
}

private enum CompactMetricLayout {
    static let height: CGFloat = 101
}

/// Displays quota and reset time as a compact pair of concentric rings.
private struct UsageWindowRow: View {
    let window: CodexUsageWindow
    let now: Date
    let appearance: MenuBarAppearance
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                ring(value: Double(window.remainingPercent), lineWidth: 6, tint: quotaTint)
                    .frame(width: 62, height: 62)

                if let remainingTime = window.remainingTimePercent(at: now) {
                    ring(
                        value: remainingTime,
                        lineWidth: 6,
                        tint: appearance.timeColor(
                            forDurationMins: window.windowDurationMins
                        ).swiftUIColor(for: colorScheme)
                    )
                    .frame(width: 47, height: 47)
                }

                Text("\(window.remainingPercent)%")
                    .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
            }

            Text(windowLabel)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.top, 4)

            if let resetsAt = window.resetsAt {
                Text(L10n.remainingDuration(until: resetsAt, from: now))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 104, height: CompactMetricLayout.height, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(windowLabel)
        .accessibilityValue(accessibilityValue)
    }

    private func ring(value: Double, lineWidth: CGFloat, tint: Color) -> some View {
        ZStack {
            Circle().stroke(tint.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, value / 100)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }

    private var accessibilityValue: String {
        var value = "\(window.remainingPercent)% \(L10n.string("quota.remaining"))"
        if let resetsAt = window.resetsAt {
            value += ", " + L10n.format(
                "quota.reset_remaining_format",
                L10n.remainingDuration(until: resetsAt, from: now)
            )
        }
        return value
    }

    private var windowLabel: String {
        switch window.windowDurationMins {
        case 5 * 60:
            L10n.string("quota.window.five_hour_limit")
        case 7 * 24 * 60:
            L10n.string("quota.window.weekly_limit")
        default:
            window.name
        }
    }

    private var quotaTint: Color {
        switch window.attentionLevel(at: now) {
        case .normal: appearance.normalColor.swiftUIColor(for: colorScheme)
        case .warning: appearance.warningColor.swiftUIColor(for: colorScheme)
        case .critical: appearance.criticalColor.swiftUIColor(for: colorScheme)
        }
    }
}

/// Shows the two equally important forms of a purchased credit balance.
private struct PurchasedCreditsView: View {
    let snapshot: CodexPurchasedCreditsSnapshot

    var body: some View {
        VStack(spacing: 2) {
            Spacer(minLength: 0)

            Text(dollarText)
                .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.65)
                .lineLimit(1)

            Text(creditText)
                .font(.system(size: 16, weight: .medium, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.65)
                .lineLimit(1)

            Spacer(minLength: 0)

            Text(L10n.string("credits.balance_label"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 104, height: CompactMetricLayout.height, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.string("credits.title"))
        .accessibilityValue("\(dollarText), \(creditText), \(L10n.string("credits.balance_label"))")
    }

    private var creditText: String {
        if snapshot.unlimited {
            return "∞"
        }
        let amount = snapshot.balance.map { decimalString($0) } ?? "0"
        return amount
    }

    private var dollarText: String {
        if snapshot.unlimited {
            return L10n.string("credits.unlimited")
        }
        let amount = snapshot.dollarBalance.map {
            "$" + decimalString($0, maximumFractionDigits: 2)
        } ?? "$0"
        return amount
    }

    private func decimalString(
        _ value: Decimal,
        maximumFractionDigits: Int = 0
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = L10n.locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits
        return formatter.string(from: value as NSDecimalNumber) ?? "0"
    }
}
