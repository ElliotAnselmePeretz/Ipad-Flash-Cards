import SwiftUI

/// The app's own chrome, replacing the parts of UIKit that made it read as a stock iOS
/// app wearing a theme: navigation bars, toggles, steppers, segmented controls, alerts.
///
/// Everything here is built to keep the behaviour Apple's controls give free — hit
/// targets, accessibility traits and labels, Dynamic Type — while looking like this app
/// rather than every other one.

// MARK: - Header

/// Replaces the system navigation bar. A soft title, a back affordance shaped like the
/// rest of the app, and trailing actions that are ours.
struct AppHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var onBack: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 40, height: 40)
                        .background(
                            Circle().fill(Theme.ink(scheme).opacity(0.06))
                        )
                        .foregroundStyle(Theme.ink(scheme))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.display(26))
                    .foregroundStyle(Theme.ink(scheme))
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.softInk(scheme))
                }
            }
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)

            HStack(spacing: 8) { trailing }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

extension AppHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, onBack: (() -> Void)? = nil) {
        self.init(title: title, subtitle: subtitle, onBack: onBack) { EmptyView() }
    }
}

/// A round action in the header, in place of a bare toolbar glyph.
struct HeaderButton: View {
    let symbol: String
    let label: String
    var tint: Color?
    var isEnabled = true
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(
                    Circle().fill((tint ?? Theme.ink(scheme)).opacity(isEnabled ? 0.08 : 0.04))
                )
                .foregroundStyle(isEnabled ? (tint ?? Theme.ink(scheme)) : Theme.softInk(scheme).opacity(0.4))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }
}

// MARK: - Toggle

/// A switch shaped like the app, not like iOS.
struct AppToggle: View {
    let title: String
    var caption: String?
    @Binding var isOn: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isOn.toggle() }
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.label(16))
                        .foregroundStyle(Theme.ink(scheme))
                    if let caption {
                        Text(caption)
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.softInk(scheme))
                    }
                }
                Spacer(minLength: 8)
                Capsule()
                    .fill(isOn ? Theme.accent(scheme) : Theme.ink(scheme).opacity(0.15))
                    .frame(width: 52, height: 31)
                    .overlay(
                        Circle()
                            .fill(.white)
                            .padding(3)
                            .offset(x: isOn ? 10.5 : -10.5)
                            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(caption ?? "")
    }
}

// MARK: - Stepper

struct AppStepper: View {
    let title: String
    var caption: String?
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step: Int = 1
    var format: (Int) -> String = { "\($0)" }

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.label(16))
                    .foregroundStyle(Theme.ink(scheme))
                if let caption {
                    Text(caption)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.softInk(scheme))
                }
            }
            Spacer(minLength: 8)

            HStack(spacing: 0) {
                stepButton("minus", enabled: value > range.lowerBound) {
                    value = max(range.lowerBound, value - step)
                }
                Text(format(value))
                    .font(.system(size: 16, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.ink(scheme))
                    .frame(minWidth: 62)
                stepButton("plus", enabled: value < range.upperBound) {
                    value = min(range.upperBound, value + step)
                }
            }
            .background(
                Capsule().fill(Theme.ink(scheme).opacity(0.06))
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(format(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 38, height: 34)
                .foregroundStyle(enabled ? Theme.accent(scheme) : Theme.softInk(scheme).opacity(0.35))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - Segmented control

struct AppSegmented<Item: Hashable>: View {
    let items: [Item]
    let label: (Item) -> String
    @Binding var selection: Item

    @Environment(\.colorScheme) private var scheme
    @Namespace private var slider

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.self) { item in
                let selected = item == selection
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { selection = item }
                } label: {
                    Text(label(item))
                        .font(Theme.label(15))
                        .foregroundStyle(selected ? Theme.ink(scheme) : Theme.softInk(scheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(Theme.surface(scheme))
                                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                                    .matchedGeometryEffect(id: "seg", in: slider)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.ink(scheme).opacity(0.06))
        )
    }
}

// MARK: - Dialog

/// Replaces the system alert for asking a short question.
struct AppDialog<Content: View>: View {
    let title: String
    var message: String?
    let confirmTitle: String
    var isConfirmEnabled = true
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @ViewBuilder var content: Content

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 16) {
                VStack(spacing: 5) {
                    Text(title)
                        .font(Theme.display(21))
                        .foregroundStyle(Theme.ink(scheme))
                    if let message {
                        Text(message)
                            .font(Theme.body(14))
                            .foregroundStyle(Theme.softInk(scheme))
                            .multilineTextAlignment(.center)
                    }
                }

                content

                HStack(spacing: 10) {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(QuietButtonStyle())
                        .frame(maxWidth: .infinity)
                    Button {
                        onConfirm()
                    } label: {
                        Text(confirmTitle)
                            .font(Theme.label(16))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                    }
                    .buttonStyle(SpringyButtonStyle(
                        tint: isConfirmEnabled ? Theme.accent(scheme) : Theme.softInk(scheme).opacity(0.3)
                    ))
                    .disabled(!isConfirmEnabled)
                }
            }
            .padding(24)
            .frame(maxWidth: 380)
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Theme.surface(scheme))
                    .shadow(color: .black.opacity(0.25), radius: 30, y: 12)
            )
            .padding(30)
            .transition(.scale(scale: 0.94).combined(with: .opacity))
        }
    }
}

/// A text field styled like the rest of the app, for use inside dialogs.
struct AppTextField: View {
    let placeholder: String
    @Binding var text: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TextField(placeholder, text: $text)
            .font(Theme.body(16))
            .textFieldStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: Theme.smallCorner, style: .continuous)
                    .fill(Theme.ink(scheme).opacity(0.06))
            )
    }
}

/// A titled group of rows, replacing `Form` sections.
struct AppSection<Content: View>: View {
    let title: String?
    var footer: String?
    @ViewBuilder var content: Content

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title.uppercased())
                    .font(Theme.label(11))
                    .tracking(1.2)
                    .foregroundStyle(Theme.softInk(scheme))
                    .padding(.leading, 4)
            }
            WarmCard(padding: 18) {
                VStack(alignment: .leading, spacing: 14) { content }
            }
            if let footer {
                Text(footer)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.softInk(scheme))
                    .padding(.horizontal, 4)
            }
        }
    }
}

/// The visual half of `HeaderButton`, for use inside a `NavigationLink` where the link
/// itself provides the tap.
struct HeaderGlyph: View {
    let symbol: String
    let label: String
    var tint: Color?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .frame(width: 40, height: 40)
            .background(Circle().fill((tint ?? Theme.ink(scheme)).opacity(0.08)))
            .foregroundStyle(tint ?? Theme.ink(scheme))
            .accessibilityLabel(label)
    }
}

/// A transparent layer that reports deliberate fingertip taps and ignores everything else.
///
/// SwiftUI's `onTapGesture` fires for any touch, including a resting palm, and gives no
/// way to inspect the contact. UIKit does: a fingertip's contact patch is small, a palm's
/// is not, so the two can be told apart before the tap is delivered.
struct PalmSafeTapArea: UIViewRepresentable {
    /// Contacts wider than this are hands, not fingers.
    ///
    /// Measured in points. A fingertip on an iPad commonly reports 20–40 depending on how
    /// flat the finger lands, while a resting palm or forearm is far larger. The first
    /// value tried here was 30, which rejected ordinary taps along with palms.
    static let maximumFingertipRadius: CGFloat = 55

    let onTap: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap))
        tap.numberOfTapsRequired = 1
        tap.numberOfTouchesRequired = 1
        // The Pencil writes; it does not navigate.
        tap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.onTap = onTap
    }

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTap: () -> Void

        init(onTap: @escaping () -> Void) { self.onTap = onTap }

        @objc func handleTap() { onTap() }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldReceive touch: UITouch) -> Bool {
            touch.type == .direct && touch.majorRadius <= PalmSafeTapArea.maximumFingertipRadius
        }
    }
}

extension View {
    /// Taps from a fingertip only. A resting palm, a knuckle or the Pencil are ignored.
    func onFingertipTap(perform action: @escaping () -> Void) -> some View {
        overlay(PalmSafeTapArea(onTap: action))
    }
}
