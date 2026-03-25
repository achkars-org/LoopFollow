// ComplicationEntryBuilder.swift
// Philippe Achkar
// 2026-03-25

import ClockKit

// MARK: - Complication identifiers

enum ComplicationID {
    /// graphicCircular + graphicCorner with gauge arc (Complication 1).
    static let gaugeCorner = "LoopFollowGaugeCorner"
    /// graphicCorner stacked text only (Complication 2).
    static let stackCorner = "LoopFollowStackCorner"
}

// MARK: - Entry builder

enum ComplicationEntryBuilder {

    // MARK: - Live template

    static func template(
        for family: CLKComplicationFamily,
        snapshot: GlucoseSnapshot,
        identifier: String
    ) -> CLKComplicationTemplate? {
        switch family {
        case .graphicCircular:
            return graphicCircularTemplate(snapshot: snapshot)
        case .graphicCorner:
            return identifier == ComplicationID.stackCorner
                ? graphicCornerStackTemplate(snapshot: snapshot)
                : graphicCornerGaugeTemplate(snapshot: snapshot)
        default:
            return nil
        }
    }

    // MARK: - Stale template

    static func staleTemplate(for family: CLKComplicationFamily, identifier: String) -> CLKComplicationTemplate? {
        switch family {
        case .graphicCircular:
            return CLKComplicationTemplateGraphicCircularStackText(
                line1TextProvider: CLKSimpleTextProvider(text: "--"),
                line2TextProvider: CLKSimpleTextProvider(text: "")
            )
        case .graphicCorner:
            if identifier == ComplicationID.stackCorner {
                return CLKComplicationTemplateGraphicCornerStackText(
                    innerTextProvider: CLKSimpleTextProvider(text: ""),
                    outerTextProvider: CLKSimpleTextProvider(text: "--")
                )
            } else {
                return staleGaugeTemplate()
            }
        default:
            return nil
        }
    }

    // MARK: - Placeholder template

    static func placeholderTemplate(for family: CLKComplicationFamily, identifier: String) -> CLKComplicationTemplate? {
        switch family {
        case .graphicCircular:
            return CLKComplicationTemplateGraphicCircularStackText(
                line1TextProvider: CLKSimpleTextProvider(text: "---"),
                line2TextProvider: CLKSimpleTextProvider(text: "→")
            )
        case .graphicCorner:
            if identifier == ComplicationID.stackCorner {
                let outer = CLKSimpleTextProvider(text: "---")
                outer.tintColor = .systemGreen
                return CLKComplicationTemplateGraphicCornerStackText(
                    innerTextProvider: CLKSimpleTextProvider(text: "+0  0m"),
                    outerTextProvider: outer
                )
            } else {
                let outer = CLKSimpleTextProvider(text: "---")
                outer.tintColor = .systemGreen
                let gauge = CLKSimpleGaugeProvider(style: .fill, gaugeColor: .systemGreen, fillFraction: 0)
                return CLKComplicationTemplateGraphicCornerGaugeText(
                    gaugeProvider: gauge,
                    leadingTextProvider: CLKSimpleTextProvider(text: "0"),
                    trailingTextProvider: nil,
                    outerTextProvider: outer
                )
            }
        default:
            return nil
        }
    }

    // MARK: - Graphic Circular
    // BG (top, colored) + trend arrow (bottom).

    private static func graphicCircularTemplate(snapshot: GlucoseSnapshot) -> CLKComplicationTemplate {
        let bgText = CLKSimpleTextProvider(text: WatchFormat.glucose(snapshot))
        bgText.tintColor = thresholdColor(for: snapshot)

        return CLKComplicationTemplateGraphicCircularStackText(
            line1TextProvider: bgText,
            line2TextProvider: CLKSimpleTextProvider(text: WatchFormat.trendArrow(snapshot))
        )
    }

    // MARK: - Graphic Corner — Gauge Text (Complication 1)
    // Gauge arc fills from 0 (fresh) to 100% (15 min stale).
    // Outer text: BG (colored). Leading text: delta.
    // Stale / isNotLooping → "⚠" in yellow, gauge full.

    private static func graphicCornerGaugeTemplate(snapshot: GlucoseSnapshot) -> CLKComplicationTemplate {
        guard snapshot.age < 900, !snapshot.isNotLooping else {
            return staleGaugeTemplate()
        }

        let fraction = Float(min(snapshot.age / 900.0, 1.0))
        let color = thresholdColor(for: snapshot)

        let bgText = CLKSimpleTextProvider(text: WatchFormat.glucose(snapshot))
        bgText.tintColor = color

        let gauge = CLKSimpleGaugeProvider(style: .fill, gaugeColor: color, fillFraction: fraction)

        return CLKComplicationTemplateGraphicCornerGaugeText(
            gaugeProvider: gauge,
            leadingTextProvider: CLKSimpleTextProvider(text: WatchFormat.delta(snapshot)),
            trailingTextProvider: nil,
            outerTextProvider: bgText
        )
    }

    private static func staleGaugeTemplate() -> CLKComplicationTemplate {
        let warnText = CLKSimpleTextProvider(text: "⚠")
        warnText.tintColor = .systemYellow

        let gauge = CLKSimpleGaugeProvider(style: .fill, gaugeColor: .systemYellow, fillFraction: 1.0)

        return CLKComplicationTemplateGraphicCornerGaugeText(
            gaugeProvider: gauge,
            leadingTextProvider: nil,
            trailingTextProvider: nil,
            outerTextProvider: warnText
        )
    }

    // MARK: - Graphic Corner — Stacked Text (Complication 2)
    // Outer (top, large): BG value, colored.
    // Inner (bottom, small): "Δ +3  4m" — delta + minutes ago.
    // Stale / isNotLooping: outer = "--", inner = "".

    private static func graphicCornerStackTemplate(snapshot: GlucoseSnapshot) -> CLKComplicationTemplate {
        guard snapshot.age < 900, !snapshot.isNotLooping else {
            return CLKComplicationTemplateGraphicCornerStackText(
                innerTextProvider: CLKSimpleTextProvider(text: ""),
                outerTextProvider: CLKSimpleTextProvider(text: "--")
            )
        }

        let bgText = CLKSimpleTextProvider(text: WatchFormat.glucose(snapshot))
        bgText.tintColor = thresholdColor(for: snapshot)

        let bottomLabel = "\(WatchFormat.delta(snapshot))  \(WatchFormat.minAgo(snapshot))"

        return CLKComplicationTemplateGraphicCornerStackText(
            innerTextProvider: CLKSimpleTextProvider(text: bottomLabel),
            outerTextProvider: bgText
        )
    }

    // MARK: - Threshold color

    /// snapshot.glucose is always in mg/dL (builder stores canonical mg/dL).
    static func thresholdColor(for snapshot: GlucoseSnapshot) -> UIColor {
        let t = LAAppGroupSettings.thresholdsMgdl()
        if snapshot.glucose < t.low  { return .systemRed }
        if snapshot.glucose > t.high { return .systemOrange }
        return .systemGreen
    }
}
