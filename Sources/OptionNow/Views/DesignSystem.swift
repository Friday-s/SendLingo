import SwiftUI
import AppKit

/// Shared design language for the OptionNow tool family
/// (OptionNow · SendLingo · Orbit · ClipMate).
///
/// The token names in this file are the family contract: every app in the family
/// declares the same semantic names so a change of language is a change in one
/// place per stack, not a re-design per screen. The look is native macOS glass
/// with a purple accent — soft hairline strokes, diffuse shadows, 8pt spacing and
/// 14/18pt continuous corners. Deliberately absent: heavy black borders, hard
/// offset shadows, neon fills, large high-saturation areas, decorative gradients.
///
/// Every color resolves for light, dark and the two accessibility
/// high-contrast appearances, so structure and hierarchy survive all three.
enum DS {}

// MARK: - Appearance-aware color resolution

extension DS {
    /// Resolves one semantic color across light / dark / high-contrast appearances.
    ///
    /// High-contrast variants default to their plain counterparts, so a token only
    /// needs to spell out the cases where it actually diverges (usually strokes,
    /// which have to firm up when the user asks for more contrast).
    /// Returns `SwiftUI.Color` spelled out in full: `DS.Color` below would otherwise
    /// shadow it for every unqualified mention inside this namespace.
    static func dynamicColor(
        light: NSColor,
        dark: NSColor,
        lightHighContrast: NSColor? = nil,
        darkHighContrast: NSColor? = nil
    ) -> SwiftUI.Color {
        SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [
                .aqua,
                .darkAqua,
                .accessibilityHighContrastAqua,
                .accessibilityHighContrastDarkAqua
            ])
            if match == .darkAqua { return dark }
            if match == .accessibilityHighContrastAqua { return lightHighContrast ?? light }
            if match == .accessibilityHighContrastDarkAqua { return darkHighContrast ?? dark }
            return light
        })
    }

    private static func srgb(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) -> NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

// MARK: - Color tokens

extension DS {
    enum Color {
        /// Window / root background.
        static let bg = DS.dynamicColor(
            light: DS.srgb(0.957, 0.957, 0.969),
            dark: DS.srgb(0.106, 0.106, 0.125)
        )

        /// Tint painted behind a translucent floating panel.
        static let surface = DS.dynamicColor(
            light: DS.srgb(1, 1, 1, 0.66),
            dark: DS.srgb(0.145, 0.145, 0.169, 0.72),
            lightHighContrast: DS.srgb(1, 1, 1, 0.94),
            darkHighContrast: DS.srgb(0.114, 0.114, 0.133, 0.96)
        )

        /// Resting card fill.
        static let card = DS.dynamicColor(
            light: DS.srgb(1, 1, 1, 0.78),
            dark: DS.srgb(1, 1, 1, 0.067),
            lightHighContrast: DS.srgb(1, 1, 1, 1),
            darkHighContrast: DS.srgb(1, 1, 1, 0.11)
        )

        /// Card raised above another card (nested content, hovered rows).
        static let cardElevated = DS.dynamicColor(
            light: DS.srgb(1, 1, 1, 0.94),
            dark: DS.srgb(1, 1, 1, 0.11),
            lightHighContrast: DS.srgb(1, 1, 1, 1),
            darkHighContrast: DS.srgb(1, 1, 1, 0.16)
        )

        /// Hairline separator / card outline.
        static let stroke = DS.dynamicColor(
            light: DS.srgb(0, 0, 0, 0.10),
            dark: DS.srgb(1, 1, 1, 0.12),
            lightHighContrast: DS.srgb(0, 0, 0, 0.32),
            darkHighContrast: DS.srgb(1, 1, 1, 0.38)
        )

        /// Outline for a control that needs to read as interactive.
        static let strokeStrong = DS.dynamicColor(
            light: DS.srgb(0, 0, 0, 0.18),
            dark: DS.srgb(1, 1, 1, 0.22),
            lightHighContrast: DS.srgb(0, 0, 0, 0.46),
            darkHighContrast: DS.srgb(1, 1, 1, 0.52)
        )

        static let textPrimary = SwiftUI.Color(nsColor: .labelColor)
        static let textSecondary = SwiftUI.Color(nsColor: .secondaryLabelColor)
        static let textTertiary = SwiftUI.Color(nsColor: .tertiaryLabelColor)

        /// Family accent. Purple is the family signature.
        static let accent = DS.dynamicColor(
            light: DS.srgb(0.420, 0.310, 0.831),
            dark: DS.srgb(0.659, 0.549, 0.980),
            lightHighContrast: DS.srgb(0.290, 0.184, 0.722),
            darkHighContrast: DS.srgb(0.769, 0.690, 1.0)
        )

        /// Accent wash for selected rows and tinted chips — low saturation on purpose.
        static let accentSoft = DS.dynamicColor(
            light: DS.srgb(0.420, 0.310, 0.831, 0.12),
            dark: DS.srgb(0.659, 0.549, 0.980, 0.18),
            lightHighContrast: DS.srgb(0.420, 0.310, 0.831, 0.22),
            darkHighContrast: DS.srgb(0.659, 0.549, 0.980, 0.28)
        )

        /// Foreground on top of a filled accent surface.
        static let onAccent = DS.dynamicColor(
            light: DS.srgb(1, 1, 1),
            dark: DS.srgb(0.075, 0.063, 0.129),
            darkHighContrast: DS.srgb(0.043, 0.035, 0.086)
        )

        /// Alternate accents offered by OptionNow's accent picker. They are tuned to
        /// the same lightness band as `accent` so swapping one in does not change how
        /// loud the app feels.
        static let accentBlue = DS.dynamicColor(
            light: DS.srgb(0.157, 0.376, 0.788),
            dark: DS.srgb(0.478, 0.647, 0.980),
            lightHighContrast: DS.srgb(0.078, 0.267, 0.678),
            darkHighContrast: DS.srgb(0.616, 0.757, 1.0)
        )

        static let accentPink = DS.dynamicColor(
            light: DS.srgb(0.729, 0.212, 0.478),
            dark: DS.srgb(0.949, 0.510, 0.706),
            lightHighContrast: DS.srgb(0.616, 0.125, 0.376),
            darkHighContrast: DS.srgb(0.980, 0.643, 0.796)
        )

        static let accentOrange = DS.dynamicColor(
            light: DS.srgb(0.729, 0.404, 0.086),
            dark: DS.srgb(0.933, 0.639, 0.310),
            lightHighContrast: DS.srgb(0.612, 0.322, 0.039),
            darkHighContrast: DS.srgb(0.965, 0.741, 0.475)
        )

        static let success = DS.dynamicColor(
            light: DS.srgb(0.129, 0.596, 0.361),
            dark: DS.srgb(0.263, 0.788, 0.494)
        )

        static let warning = DS.dynamicColor(
            light: DS.srgb(0.729, 0.443, 0.086),
            dark: DS.srgb(0.914, 0.651, 0.294)
        )

        static let danger = DS.dynamicColor(
            light: DS.srgb(0.788, 0.231, 0.212),
            dark: DS.srgb(0.941, 0.408, 0.373)
        )
    }
}

// MARK: - Spacing, radius, stroke width

extension DS {
    /// 8pt rhythm. `xs`/`md` are the half-steps that keep dense controls on grid.
    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    /// Two continuous radii carry the family: 14 for cards and controls,
    /// 18 for windows and floating panels. `chip` is for capsule-adjacent inline tags.
    enum Radius {
        static let chip: CGFloat = 8
        static let card: CGFloat = 14
        static let panel: CGFloat = 18
    }

    enum Stroke {
        static let hairline: CGFloat = 0.5
        static let border: CGFloat = 1
    }
}

// MARK: - Typography

extension DS {
    /// SF Pro for Latin, PingFang for Chinese — both come from `.system`, which
    /// already resolves per-script on macOS. No rounded design: the family reads
    /// as a native utility, not a toy.
    enum Font {
        static func h1() -> SwiftUI.Font { .system(size: 24, weight: .semibold) }
        static func h2() -> SwiftUI.Font { .system(size: 19, weight: .semibold) }
        static func h3() -> SwiftUI.Font { .system(size: 15, weight: .semibold) }
        static func h4() -> SwiftUI.Font { .system(size: 13, weight: .semibold) }
        static func body(_ weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .system(size: 13, weight: weight)
        }
        static func caption(_ weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .system(size: 11, weight: weight)
        }
        static func mono(_ size: CGFloat = 12) -> SwiftUI.Font {
            .system(size: size, weight: .regular, design: .monospaced)
        }
    }
}

// MARK: - Shapes

extension DS {
    static var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
    }

    static var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
    }

    static func shape(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    /// True when the user asked for less transparency; glass then falls back to
    /// an opaque fill so text keeps its contrast.
    static var reduceTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }
}

// MARK: - Surface modifiers

private struct DSCardBackground: ViewModifier {
    let fill: Color
    let radius: CGFloat
    let strokeColor: Color
    let lineWidth: CGFloat
    let shadow: Bool

    func body(content: Content) -> some View {
        let shape = DS.shape(radius)
        return content
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(strokeColor, lineWidth: lineWidth))
            .clipShape(shape)
            .modifier(DSSoftShadow(enabled: shadow, radius: radius))
    }
}

private struct DSSoftShadow: ViewModifier {
    let enabled: Bool
    let radius: CGFloat

    func body(content: Content) -> some View {
        if enabled {
            content.shadow(color: .black.opacity(0.10), radius: 10, y: 4)
        } else {
            content
        }
    }
}

private struct DSPanelBackground: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        let shape = DS.shape(radius)
        return content
            .background {
                if DS.reduceTransparency {
                    shape.fill(DS.Color.bg)
                } else {
                    shape.fill(.regularMaterial)
                }
            }
            .background(shape.fill(DS.Color.surface))
            .overlay(shape.strokeBorder(DS.Color.stroke, lineWidth: DS.Stroke.hairline))
            .clipShape(shape)
            .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
    }
}

extension View {
    /// Standard family card: soft fill, hairline outline, 14pt continuous corners.
    func dsCard(
        _ fill: Color = DS.Color.card,
        radius: CGFloat = DS.Radius.card,
        stroke: Color = DS.Color.stroke,
        lineWidth: CGFloat = DS.Stroke.hairline,
        shadow: Bool = false
    ) -> some View {
        modifier(DSCardBackground(
            fill: fill,
            radius: radius,
            strokeColor: stroke,
            lineWidth: lineWidth,
            shadow: shadow
        ))
    }

    /// Floating window / overlay panel: native glass, hairline edge, diffuse shadow.
    func dsPanel(radius: CGFloat = DS.Radius.panel) -> some View {
        modifier(DSPanelBackground(radius: radius))
    }

    /// Keyboard-focus ring. Accent-tinted and soft — never a neon outline.
    func dsFocusRing(_ visible: Bool, radius: CGFloat = DS.Radius.card) -> some View {
        overlay {
            DS.shape(radius)
                .strokeBorder(DS.Color.accent.opacity(visible ? 0.9 : 0), lineWidth: 2)
        }
    }
}

// MARK: - Controls

/// Filled accent button — one per view at most, for the primary action.
struct DSPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && isEnabled
        return configuration.label
            .font(DS.Font.body(.semibold))
            .foregroundStyle(isEnabled ? DS.Color.onAccent : DS.Color.textTertiary)
            .padding(.horizontal, DS.Space.md)
            .frame(minHeight: 30)
            .background {
                DS.cardShape.fill(
                    isEnabled
                        ? DS.Color.accent.opacity(pressed ? 0.82 : 1)
                        : DS.Color.accentSoft
                )
            }
            .overlay(DS.cardShape.strokeBorder(DS.Color.accent.opacity(isEnabled ? 0.28 : 0), lineWidth: DS.Stroke.hairline))
            .contentShape(DS.cardShape)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Outlined button for secondary actions.
///
/// `tint` turns the button into a stateful variant (e.g. success after a copy)
/// without introducing a second style: the wash and label follow the tint while
/// the geometry stays identical, so a state change never shifts layout.
struct DSSecondaryButtonStyle: ButtonStyle {
    var tint: Color?
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && isEnabled
        let label: Color = {
            guard isEnabled else { return DS.Color.textTertiary }
            return tint ?? DS.Color.textPrimary
        }()
        return configuration.label
            .font(DS.Font.body(.medium))
            .foregroundStyle(label)
            .padding(.horizontal, DS.Space.md)
            .frame(minHeight: 30)
            .background {
                DS.cardShape.fill(
                    tint.map { $0.opacity(pressed ? 0.20 : 0.13) }
                        ?? (pressed ? DS.Color.cardElevated : DS.Color.card)
                )
            }
            .overlay {
                DS.cardShape.strokeBorder(
                    tint?.opacity(0.30) ?? (isEnabled ? DS.Color.strokeStrong : DS.Color.stroke),
                    lineWidth: DS.Stroke.hairline
                )
            }
            .contentShape(DS.cardShape)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Compact symbol-only button for title bars and row affordances.
struct DSIconButtonStyle: ButtonStyle {
    var size: CGFloat = 26
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isEnabled ? DS.Color.textSecondary : DS.Color.textTertiary)
            .frame(width: size, height: size)
            .background {
                DS.shape(DS.Radius.chip).fill(
                    configuration.isPressed && isEnabled ? DS.Color.cardElevated : Color.clear
                )
            }
            .contentShape(DS.shape(DS.Radius.chip))
    }
}

// MARK: - Small components

/// Tinted status pill. Uses a soft wash plus colored text, never a saturated slab.
struct DSBadge: View {
    let text: String
    var tint: Color = DS.Color.accent

    var body: some View {
        Text(text)
            .font(DS.Font.caption(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, DS.Space.sm)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.14)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.24), lineWidth: DS.Stroke.hairline))
    }
}

struct DSSectionHeader: View {
    let eyebrow: String
    let title: String
    var subtitle: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            if !eyebrow.isEmpty {
                Text(eyebrow.uppercased())
                    .font(DS.Font.caption(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(DS.Color.accent)
            }
            Text(title)
                .font(DS.Font.h2())
                .foregroundStyle(DS.Color.textPrimary)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(DS.Font.body())
                    .foregroundStyle(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct DSProgressBar: View {
    let value: Double
    var tint: Color = DS.Color.accent

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(DS.Color.accentSoft)
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 6)
        .accessibilityValue(Text("\(Int(min(max(value, 0), 1) * 100))%"))
    }
}
