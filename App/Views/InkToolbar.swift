import SwiftUI
import PencilKit

/// The writing tools, built from scratch rather than using Apple's `PKToolPicker`.
///
/// The system picker is instantly recognisable as the one from Notes and Freeform: a
/// floating tray of skeuomorphic pencils. This is a flat, compact bar that sits in the
/// app's own layout, so the app reads as its own thing.
struct InkToolbar: View {
    @Binding var tool: InkTool
    @Binding var color: InkColor
    @Binding var width: InkWidth

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("scribbleToErase") private var scribbleToErase = true

    var body: some View {
        HStack(spacing: 18) {
            toolGroup
            Divider().frame(height: 22)
            widthGroup
            Divider().frame(height: 22)
            colorGroup
            Divider().frame(height: 22)
            scribbleToggle
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    /// Scratch a stroke out to delete it. Off is a legitimate choice: some handwriting
    /// looks enough like a scratch-out to trip it.
    private var scribbleToggle: some View {
        Button {
            scribbleToErase.toggle()
        } label: {
            Image(systemName: "scribble.variable")
                .font(.system(size: 17, weight: .medium))
                .frame(width: 36, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(scribbleToErase ? Color.accentColor.opacity(0.18) : .clear)
                )
                .foregroundStyle(scribbleToErase ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Scribble to erase")
        .accessibilityValue(scribbleToErase ? "On" : "Off")
        .accessibilityIdentifier("ink.scribbleErase")
    }

    private var toolGroup: some View {
        HStack(spacing: 6) {
            ForEach(InkTool.allCases) { candidate in
                Button {
                    tool = candidate
                } label: {
                    Image(systemName: candidate.symbol)
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 36, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(tool == candidate ? Color.accentColor.opacity(0.18) : .clear)
                        )
                        .foregroundStyle(tool == candidate ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(candidate.label)
                .accessibilityIdentifier("ink.tool.\(candidate.rawValue)")
                .accessibilityAddTraits(tool == candidate ? [.isSelected] : [])
            }
        }
    }

    private var widthGroup: some View {
        HStack(spacing: 6) {
            ForEach(InkWidth.allCases) { candidate in
                Button {
                    width = candidate
                } label: {
                    Circle()
                        .fill(width == candidate ? Color.accentColor : Color.secondary)
                        .frame(width: candidate.dotSize, height: candidate.dotSize)
                        .frame(width: 28, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(candidate.label)
                .accessibilityIdentifier("ink.width.\(candidate.rawValue)")
            }
        }
    }

    private var colorGroup: some View {
        HStack(spacing: 8) {
            ForEach(InkColor.allCases) { candidate in
                Button {
                    color = candidate
                } label: {
                    Circle()
                        .fill(candidate.swatch(for: colorScheme))
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle().strokeBorder(
                                color == candidate ? Color.accentColor : Color.primary.opacity(0.15),
                                lineWidth: color == candidate ? 2.5 : 1
                            )
                        )
                        .frame(width: 28, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(candidate.label)
                .accessibilityIdentifier("ink.color.\(candidate.rawValue)")
            }
        }
    }
}

// MARK: - Tool model

enum InkTool: String, CaseIterable, Identifiable {
    case pen, pencil, highlighter, eraser

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pen: "Pen"
        case .pencil: "Pencil"
        case .highlighter: "Highlighter"
        case .eraser: "Eraser"
        }
    }

    /// Deliberately plain SF Symbols rather than Apple's illustrated pencil tray.
    var symbol: String {
        switch self {
        case .pen: "pencil.tip"
        case .pencil: "scribble"
        case .highlighter: "highlighter"
        case .eraser: "eraser"
        }
    }

    var inkType: PKInk.InkType? {
        switch self {
        case .pen: .pen
        case .pencil: .pencil
        case .highlighter: .marker
        case .eraser: nil
        }
    }
}

enum InkWidth: String, CaseIterable, Identifiable {
    case fine, medium, broad

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fine: "Fine"
        case .medium: "Medium"
        case .broad: "Broad"
        }
    }

    var dotSize: CGFloat {
        switch self {
        case .fine: 7
        case .medium: 11
        case .broad: 15
        }
    }

    func points(for tool: InkTool) -> CGFloat {
        let base: CGFloat = switch self {
        case .fine: 2
        case .medium: 5
        case .broad: 9
        }
        // A highlighter has to be much fatter than a pen to read as one.
        return tool == .highlighter ? base * 4 : base
    }
}

enum InkColor: String, CaseIterable, Identifiable {
    case ink, blue, red, green, amber

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ink: "Ink"
        case .blue: "Blue"
        case .red: "Red"
        case .green: "Green"
        case .amber: "Amber"
        }
    }

    /// The default "ink" follows the theme — near-black on light, near-white on dark —
    /// so handwriting stays legible either way. The rest are tuned to sit on both grounds.
    func uiColor(for style: UIUserInterfaceStyle) -> UIColor {
        let dark = style == .dark
        switch self {
        case .ink:   return dark ? UIColor(white: 0.94, alpha: 1) : UIColor(white: 0.08, alpha: 1)
        case .blue:  return dark ? UIColor(red: 0.48, green: 0.62, blue: 1.00, alpha: 1)
                                 : UIColor(red: 0.13, green: 0.28, blue: 0.72, alpha: 1)
        case .red:   return dark ? UIColor(red: 1.00, green: 0.48, blue: 0.44, alpha: 1)
                                 : UIColor(red: 0.72, green: 0.18, blue: 0.14, alpha: 1)
        case .green: return dark ? UIColor(red: 0.44, green: 0.82, blue: 0.56, alpha: 1)
                                 : UIColor(red: 0.11, green: 0.48, blue: 0.26, alpha: 1)
        case .amber: return dark ? UIColor(red: 0.98, green: 0.76, blue: 0.36, alpha: 1)
                                 : UIColor(red: 0.68, green: 0.46, blue: 0.06, alpha: 1)
        }
    }

    func swatch(for scheme: ColorScheme) -> Color {
        Color(uiColor(for: scheme == .dark ? .dark : .light))
    }
}
