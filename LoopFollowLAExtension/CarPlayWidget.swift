// LoopFollow
// CarPlayWidget.swift

import AppIntents
import Charts
import SwiftUI
import WidgetKit

/// A small widget for the CarPlay Widgets screen, also usable on the Home
/// Screen. One page at a time; the button in the corner steps through them.
struct CarPlayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: CarPlayWidgetStore.kind, provider: CarPlayWidgetProvider()) { entry in
            CarPlayWidgetView(entry: entry)
        }
        .configurationDisplayName("LoopFollow")
        .description("Glucose, trend, override and alerts, one page at a time.")
        .supportedFamilies([.systemSmall])
    }
}

/// Moves the widget to its next page. Runs in the widget extension; WidgetKit
/// redraws the widget as soon as it returns.
struct NextCarPlayWidgetPageIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Widget Page"
    static var description = IntentDescription("Shows the next page of the LoopFollow widget.")
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        CarPlayWidgetStore.page = CarPlayWidgetStore.page.next
        return .result()
    }
}

// MARK: - Timeline

struct CarPlayWidgetEntry: TimelineEntry {
    let date: Date
    let state: CarPlayWidgetState?
    let page: CarPlayWidgetPage
}

struct CarPlayWidgetProvider: TimelineProvider {
    func placeholder(in _: Context) -> CarPlayWidgetEntry {
        CarPlayWidgetEntry(date: Date(), state: nil, page: .now)
    }

    func getSnapshot(in _: Context, completion: @escaping (CarPlayWidgetEntry) -> Void) {
        completion(CarPlayWidgetEntry(date: Date(), state: CarPlayWidgetStore.load(), page: CarPlayWidgetStore.page))
    }

    /// The app asks for a reload whenever the data changes. In between, one
    /// entry a minute for half an hour, then every five minutes to the hour,
    /// keeps the reading's age, the stale cue and the alerts current, including
    /// when the app has stopped updating.
    func getTimeline(in _: Context, completion: @escaping (Timeline<CarPlayWidgetEntry>) -> Void) {
        let now = Date()
        let state = CarPlayWidgetStore.load()
        let page = CarPlayWidgetStore.page
        let minutes = Array(0 ..< 30) + Array(stride(from: 30, through: 60, by: 5))
        let entries = minutes.map {
            CarPlayWidgetEntry(date: now.addingTimeInterval(Double($0) * 60), state: state, page: page)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Views

struct CarPlayWidgetView: View {
    let entry: CarPlayWidgetEntry

    private var alerts: [WidgetAlert] {
        entry.state?.alertInputs.alerts(at: entry.date) ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if let state = entry.state, let snapshot = state.snapshot {
                    switch entry.page {
                    case .now:
                        CarPlayNowPage(snapshot: snapshot, date: entry.date)
                    case .trend:
                        CarPlayTrendPage(snapshot: snapshot, history: state.history, date: entry.date)
                    case .override:
                        CarPlayOverridePage(snapshot: snapshot, date: entry.date)
                    case .alerts:
                        CarPlayAlertsPage(alerts: alerts)
                    }
                } else {
                    CarPlayNoDataPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .invalidatableContent()

            CarPlayWidgetFooter(page: entry.page, alerts: alerts)
        }
        .foregroundStyle(.white)
        .containerBackground(Color(white: 0.17), for: .widget)
    }
}

/// The reading, trend and age, then projected BG, IOB, COB and basal with the
/// same icons as the tight CarPlay layout.
private struct CarPlayNowPage: View {
    let snapshot: GlucoseSnapshot
    let date: Date

    var body: some View {
        let isStale = snapshot.isStale(at: date)
        let color = isStale ? Color.white.opacity(0.55) : LAColors.keyline(for: snapshot)

        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(LAFormat.glucose(snapshot))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .strikethrough(isStale, pattern: .solid, color: .red)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(LAFormat.trendArrow(snapshot))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(color)

            Text("\(LAFormat.delta(snapshot)) \(snapshot.unit.displayName) · \(WidgetAlertInputs.ago(date.timeIntervalSince(snapshot.updatedAt)))")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isStale ? Color.red : Color.white.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 6)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    metric(LAFormat.projected(snapshot), label: "Projected glucose") { Image(systemName: "target") }
                    metric(LAFormat.cob(snapshot), label: "Carbs on board") { Image(systemName: "fork.knife") }
                }
                Spacer(minLength: 4)
                VStack(alignment: .leading, spacing: 5) {
                    metric(LAFormat.iob(snapshot), label: "Insulin on board") { Image(systemName: "syringe") }
                    metric(LAFormat.activeBasal(snapshot), label: "Basal rate") {
                        BasalStepIcon()
                            .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                            .frame(width: 13, height: 9)
                    }
                }
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
        }
    }

    private func metric(_ value: String, label: String, @ViewBuilder icon: () -> some View) -> some View {
        HStack(spacing: 4) {
            icon()
                .foregroundStyle(.white.opacity(0.65))
                .frame(width: 15)
                .accessibilityHidden(true)
            Text(value)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityLabel("\(label) \(value)")
        }
    }
}

/// The last three hours against the target range, with the reading in the corner.
private struct CarPlayTrendPage: View {
    let snapshot: GlucoseSnapshot
    let history: [GlucosePoint]
    let date: Date

    var body: some View {
        let thresholds = LAAppGroupSettings.thresholdsMgdl()
        let low = display(thresholds.low)
        let high = display(thresholds.high)
        let values = history.map { display($0.mgdl) }
        let yMin = min(values.min() ?? low, low) * 0.9
        let yMax = max(values.max() ?? high, high) * 1.05
        let start = date.addingTimeInterval(-CarPlayWidgetState.historyWindow)
        let isStale = snapshot.isStale(at: date)

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Last 3 h")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text("\(LAFormat.glucose(snapshot)) \(LAFormat.trendArrow(snapshot))")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .strikethrough(isStale, pattern: .solid, color: .red)
                    .foregroundStyle(isStale ? Color.white.opacity(0.55) : LAColors.keyline(for: snapshot))
            }

            Chart {
                RectangleMark(
                    xStart: .value("Start", start),
                    xEnd: .value("End", date),
                    yStart: .value("Low", low),
                    yEnd: .value("High", high)
                )
                .foregroundStyle(Color.green.opacity(0.18))

                ForEach(history, id: \.date) { point in
                    PointMark(
                        x: .value("Time", point.date),
                        y: .value("Glucose", display(point.mgdl))
                    )
                    .symbolSize(10)
                    .foregroundStyle(color(for: point.mgdl, low: thresholds.low, high: thresholds.high))
                }
            }
            .chartXScale(domain: start ... date)
            .chartYScale(domain: yMin ... yMax)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .accessibilityLabel("Glucose over the last 3 hours")

            Text("Range \(format(low))–\(format(high))")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private func display(_ mgdl: Double) -> Double {
        snapshot.unit == .mmol ? GlucoseConversion.toMmol(mgdl) : mgdl
    }

    private func format(_ value: Double) -> String {
        snapshot.unit == .mmol
            ? value.formatted(.number.precision(.fractionLength(1)))
            : "\(Int(value.rounded()))"
    }

    private func color(for mgdl: Double, low: Double, high: Double) -> Color {
        if mgdl <= low { return .red }
        if mgdl >= high { return .orange }
        return .green
    }
}

/// The running override with its insulin needs, range and time left, then
/// the basal rate. Without an override, the temp target if any.
private struct CarPlayOverridePage: View {
    let snapshot: GlucoseSnapshot
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let name = LAFormat.activeOverrideName(snapshot) {
                Text("\(Image(systemName: "slider.horizontal.3")) \(name)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.green)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                let details = snapshot.overrideDetails(now: date)
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
            } else {
                Text("No override")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
            }

            if let target = LAFormat.tempTargetValue(snapshot) {
                Text("Temp target \(target)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }

            Spacer(minLength: 4)

            HStack(spacing: 5) {
                BasalStepIcon()
                    .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .frame(width: 13, height: 9)
                    .foregroundStyle(.white.opacity(0.65))
                    .accessibilityHidden(true)
                Text("\(LAFormat.basal(snapshot)) U/h")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityLabel("Basal rate \(LAFormat.basal(snapshot)) units per hour")
            }
        }
    }
}

/// A large thumbs-up when nothing needs attention, otherwise the alerts,
/// urgent first.
private struct CarPlayAlertsPage: View {
    let alerts: [WidgetAlert]

    var body: some View {
        if alerts.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "hand.thumbsup.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(.green)
                Text("All good")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        } else {
            // Three rows fit; with more, two and a count of the rest.
            let shown = alerts.count > 3 ? Array(alerts.prefix(2)) : alerts
            VStack(alignment: .leading, spacing: 6) {
                ForEach(shown) { alert in
                    CarPlayAlertRow(alert: alert)
                }
                if alerts.count > shown.count {
                    Text("+\(alerts.count - shown.count) more")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }
}

private struct CarPlayAlertRow: View {
    let alert: WidgetAlert

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: Self.symbol(for: alert.kind))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(alert.severity == .urgent ? Color.red : Color.orange)
                .frame(width: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(alert.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let detail = alert.detail {
                    Text(detail)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    static func symbol(for kind: WidgetAlert.Kind) -> String {
        switch kind {
        case .noReadings: "wifi.slash"
        case .notLooping: "arrow.triangle.2.circlepath"
        case .low: "arrow.down.circle.fill"
        case .lowSoon: "arrow.down.right.circle.fill"
        case .droppingFast: "arrow.down.circle"
        case .high: "arrow.up.circle.fill"
        case .sensorExpiry: "dot.radiowaves.left.and.right"
        case .siteExpiry: "bandage.fill"
        case .lowInsulin: "syringe.fill"
        case .pumpBattery: "battery.25"
        case .phoneBattery: "iphone"
        case .appExpiry: "app.badge"
        }
    }
}

private struct CarPlayNoDataPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No data yet")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            Text("Open LoopFollow on your iPhone.")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

/// The page name and dots, a count of alerts when on another page, and the
/// button to the next page.
private struct CarPlayWidgetFooter: View {
    let page: CarPlayWidgetPage
    let alerts: [WidgetAlert]

    var body: some View {
        HStack(spacing: 5) {
            Text(page.title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))

            HStack(spacing: 3) {
                ForEach(CarPlayWidgetPage.allCases, id: \.self) { item in
                    Circle()
                        .fill(item == page ? Color.white : Color.white.opacity(0.35))
                        .frame(width: 5, height: 5)
                }
            }
            .accessibilityHidden(true)

            if page != .alerts, !alerts.isEmpty {
                let urgent = alerts.contains { $0.severity == .urgent }
                Text("\(Image(systemName: "exclamationmark.triangle.fill")) \(alerts.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(urgent ? Color.red : Color.orange)
                    .accessibilityLabel("\(alerts.count) alerts")
            }

            Spacer(minLength: 0)

            Button(intent: NextCarPlayWidgetPageIntent()) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.2)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next page")
        }
    }
}
