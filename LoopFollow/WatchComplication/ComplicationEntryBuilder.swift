// ComplicationEntryBuilder.swift
// Philippe Achkar
// 2026-03-10

import ClockKit
import SwiftUI

enum ComplicationEntryBuilder {

    // MARK: - Live Template

    static func template(
        for family: CLKComplicationFamily,
        snapshot: GlucoseSnapshot
    ) -> CLKComplicationTemplate? {
        switch family {
        case .graphicCircular:
            return graphicCircularTemplate(snapshot: snapshot)
        case .graphicCorner:
            return graphicCornerTemplate(snapshot: snapshot)
        default:
            return nil
        }
    }

    // MARK: - Stale Template

    static func staleTemplate(for family: CLKComplicationFamily) -> CLKComplicationTemplate? {
        switch family {
        case .graphicCircular:
            return CLKComplicationTemplateGraphicCircularStackText(
                line1TextProvider: CLKSimpleTextProvider(text: "--"),
                line2TextProvider: CLKSimpleTextProvider(text: "")
            )
        case .graphicCorner:
            return CLKComplicationTemplateGraphicCornerStackText(
                innerTextProvider: CLKSimpleTextProvider(text: "--"),
                outerTextProvider: CLKSimpleTextProvider(text: "")
            )
        default:
            return nil
        }
    }

    // MARK: - Placeholder Template

    static func placeholderTemplate(for family: CLKComplicationFamily) -> CLKComplicationTemplate? {
        switch family {
        case .graphicCircular:
            return CLKComplicationTemplateGraphicCircularStackText(
                line1TextProvider: CLKSimpleTextProvider(text: "---"),
                line2TextProvider: CLKSimpleTextProvider(text: "→")
            )
        case .graphicCorner:
            return CLKComplicationTemplateGraphicCornerStackText(
                innerTextProvider: CLKSimpleTextProvider(text: "---"),
                outerTextProvider: CLKSimpleTextProvider(text: "→")
            )
        default:
            return nil
        }
    }

    // MARK: - Graphic Circular
    // Layout: large glucose value on top, trend arrow below
    // Colour: derived from threshold classification

    private static func graphicCircularTemplate(
        snapshot: GlucoseSnapshot
    ) -> CLKComplicationTemplateGraphicCircularStackText {
        let glucoseText = CLKSimpleTextProvider(text: formattedGlucose(snapshot))
        glucoseText.tintColor = thresholdColour(for: snapshot)

        let template = CLKComplicationTemplateGraphicCircularStackText(
            line1TextProvider: glucoseText,
            line2TextProvider: CLKSimpleTextProvider(text: "")
        )
        return template
    }

    // MARK: - Graphic Corner
    // Layout: glucose value inner, trend arrow outer
    // Colour: derived from threshold classification

    private static func graphicCornerTemplate(
        snapshot: GlucoseSnapshot
    ) -> CLKComplicationTemplateGraphicCornerStackText {
        let glucoseText = CLKSimpleTextProvider(text: formattedGlucose(snapshot))
        glucoseText.tintColor = thresholdColour(for: snapshot)

        let arrowText = CLKSimpleTextProvider(text: trendArrow(for: snapshot.trend))

        let template = CLKComplicationTemplateGraphicCornerStackText(
            innerTextProvider: glucoseText,
            outerTextProvider: arrowText
        )
        return template
    }

    // MARK: - Helpers

    private static func formattedGlucose(_ snapshot: GlucoseSnapshot) -> String {
        switch snapshot.unit {
        case .mgdl:
            return String(Int(snapshot.glucose.rounded()))
        case .mmol:
            return String(format: "%.1f", snapshot.glucose)
        }
    }

    private static func trendArrow(for trend: GlucoseSnapshot.Trend) -> String {
        switch trend {
        case .upFast:   return "↑↑"
        case .up:       return "↑"
        case .flat:     return "→"
        case .down:     return "↓"
        case .downFast: return "↓↓"
        case .unknown:  return "?"
        }
    }

    private static func thresholdColour(for snapshot: GlucoseSnapshot) -> UIColor {
        let thresholds = LAAppGroupSettings.thresholdsMgdl()

        // Always classify against mg/dL regardless of display unit
        let mgdl: Double
        switch snapshot.unit {
        case .mgdl:
            mgdl = snapshot.glucose
        case .mmol:
            mgdl = snapshot.glucose * 18.0182
        }

        if mgdl < thresholds.low {
            return UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0)   // red
        } else if mgdl > thresholds.high {
            return UIColor(red: 1.0, green: 0.58, blue: 0.0, alpha: 1.0)    // orange
        } else {
            return UIColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1.0)  // green
        }
    }
}
