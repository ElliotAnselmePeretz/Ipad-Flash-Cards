import SwiftUI

/// The app's warmth lives here.
///
/// The previous look was system-default: cool greys, sharp corners, the standard SF text
/// face. That reads as a utility. These are paper colours — warm, slightly peachy — with
/// a rounded typeface and generous corner radii, so studying feels closer to a notebook
/// than to a form.
enum Theme {

    // MARK: - Colour

    /// Page. Warm off-white by day, a soft dark brown at night rather than pure black,
    /// which keeps the "paper" feeling instead of switching to a terminal.
    static func page(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.11, green: 0.10, blue: 0.09)
                        : Color(red: 0.985, green: 0.965, blue: 0.935)
    }

    /// Raised surfaces: cards, bars, rows.
    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.16, green: 0.145, blue: 0.13)
                        : Color(red: 1.0, green: 0.993, blue: 0.976)
    }

    /// Text and ink.
    static func ink(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.95, green: 0.93, blue: 0.90)
                        : Color(red: 0.18, green: 0.15, blue: 0.12)
    }

    static func softInk(_ scheme: ColorScheme) -> Color {
        ink(scheme).opacity(0.55)
    }

    /// A warm apricot, used sparingly — it is the only saturated colour in the chrome.
    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.95, green: 0.68, blue: 0.42)
                        : Color(red: 0.86, green: 0.51, blue: 0.24)
    }

    /// The ambient glow. Light mode gets a soft sky blue — cool light falling on warm
    /// paper. Dark mode keeps the warm accent instead: a blue halo on a dark brown ground
    /// reads as a screen glitch rather than light.
    static func glow(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.95, green: 0.68, blue: 0.42)
                        : Color(red: 0.53, green: 0.76, blue: 0.94)
    }

    /// The three answers. Warm and distinguishable without being traffic lights.
    static func hard(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.94, green: 0.55, blue: 0.50)
                        : Color(red: 0.78, green: 0.32, blue: 0.27)
    }

    static func medium(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.95, green: 0.76, blue: 0.44)
                        : Color(red: 0.80, green: 0.55, blue: 0.18)
    }

    static func easy(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.62, green: 0.82, blue: 0.58)
                        : Color(red: 0.33, green: 0.56, blue: 0.32)
    }

    // MARK: - Shape and type

    static let corner: CGFloat = 22
    static let smallCorner: CGFloat = 14

    /// Rounded throughout. It is the single biggest reason the app reads as friendly.
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .rounded) }
    static func body(_ size: CGFloat = 17) -> Font { .system(size: size, weight: .regular, design: .rounded) }
    static func label(_ size: CGFloat = 15) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
}

/// A soft raised panel — the app's one repeated shape.
struct WarmCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Theme.surface(scheme))
                    .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.06),
                            radius: 14, x: 0, y: 6)
            )
    }
}

/// Buttons that give a little under the finger. Small, but it is most of what makes an
/// interface feel alive rather than inert.
struct SpringyButtonStyle: ButtonStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: Theme.smallCorner, style: .continuous)
                    .fill(tint)
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct QuietButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.ink(scheme))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: Theme.smallCorner, style: .continuous)
                    .fill(Theme.ink(scheme).opacity(configuration.isPressed ? 0.14 : 0.07))
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// A slow, soft halo. Deliberately restrained: it breathes over three seconds and never
/// exceeds a faint bloom, so it reads as warmth rather than a notification.
struct SoftGlow: ViewModifier {
    var color: Color
    var active: Bool = true
    var maxOpacity: Double = 0.55

    @State private var pulse = false

    func body(content: Content) -> some View {
        content
            .background(
                // Inset negatively and blurred hard, so the halo actually escapes from
                // behind an opaque card instead of being hidden by it.
                RoundedRectangle(cornerRadius: Theme.corner + 10, style: .continuous)
                    .fill(color)
                    .padding(-14)
                    .blur(radius: 30)
                    .opacity(active ? (pulse ? maxOpacity : maxOpacity * 0.45) : 0)
                    .scaleEffect(pulse ? 1.03 : 1.0)
                    .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: pulse)
                    .allowsHitTesting(false)
            )
            .onAppear { pulse = true }
    }
}

extension View {
    /// Adds the app's ambient glow behind a surface.
    func softGlow(_ color: Color, active: Bool = true, maxOpacity: Double = 0.28) -> some View {
        modifier(SoftGlow(color: color, active: active, maxOpacity: maxOpacity))
    }
}

/// A small warm statistic, used to stop screens feeling bare.
struct StatChip: View {
    @Environment(\.colorScheme) private var scheme
    let value: String
    let label: String
    var tint: Color?

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(tint ?? Theme.ink(scheme))
            Text(label)
                .font(Theme.body(12))
                .foregroundStyle(Theme.softInk(scheme))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Theme.smallCorner, style: .continuous)
                .fill((tint ?? Theme.ink(scheme)).opacity(0.07))
        )
    }
}
