import SwiftUI
import PencilKit
import FlashcardsCore

/// Wraps `PKCanvasView`.
///
/// PencilKit supplies the ink pipeline — pressure, tilt, low latency and, crucially,
/// palm rejection. The tool *interface* is ours: Apple's `PKToolPicker` is never shown,
/// so the app doesn't look like Notes.
/// Lets a parent view drive the canvas: undo, redo, erase everything. PencilKit keeps its
/// own undo stack per canvas, so this just exposes what is already there.
@Observable
final class InkCanvasController {
    weak var canvas: PKCanvasView?

    var canUndo: Bool { canvas?.undoManager?.canUndo ?? false }
    var canRedo: Bool { canvas?.undoManager?.canRedo ?? false }

    func undo() { canvas?.undoManager?.undo() }
    func redo() { canvas?.undoManager?.redo() }
    func clear() { canvas?.drawing = PKDrawing() }
}

struct DrawingCanvas: UIViewRepresentable {
    @Binding var data: Data?

    var controller: InkCanvasController?

    var tool: InkTool = .pen
    var color: InkColor = .ink
    var width: InkWidth = .medium
    var isReadOnly: Bool = false

    /// Pencil-only is the whole palm-rejection story: with `.pencilOnly`, iPadOS routes
    /// every non-Pencil touch — finger, knuckle, resting palm, forearm — away from the ink
    /// pipeline, so a hand on the glass can never leave a mark. It also frees finger
    /// gestures for navigation, which is what lets a tap flip the card.
    var pencilOnly: Bool = true

    /// Deliberately absent: there is no tap-to-flip while writing.
    ///
    /// The card editor and rapid capture are used with a hand resting on the page, and a
    /// resting palm produces a direct touch that looks like a tap. Filtering by contact
    /// size failed in both directions — tight enough to reject a palm also rejected real
    /// fingertips. Those screens use explicit controls instead, and tapping to flip lives
    /// on the study screen, where nothing is resting on the glass.

    /// Scratch a stroke out to delete it, the way you would on paper. Detection can
    /// misfire on unusual handwriting, so it is switchable from the tool bar.
    @AppStorage("scribbleToErase") private var scribbleToErase = true

    /// UI tests cannot synthesise Apple Pencil input, so they opt into finger drawing
    /// through a launch argument. Nothing ships with this enabled.
    private var effectivePencilOnly: Bool {
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-allow-finger") { return false }
        return pencilOnly
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = MenulessCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawingPolicy = effectivePencilOnly ? .pencilOnly : .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.alwaysBounceVertical = false
        canvas.isUserInteractionEnabled = !isReadOnly

        if let data, let drawing = try? PKDrawing(data: data) {
            canvas.drawing = drawing
        }

        context.coordinator.apply(tool: tool, color: color, width: width, to: canvas)
        controller?.canvas = canvas
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        canvas.isUserInteractionEnabled = !isReadOnly
        canvas.drawingPolicy = effectivePencilOnly ? .pencilOnly : .anyInput

        // Only push external changes in; never stomp on ink the user is mid-stroke on.
        let incoming = data.flatMap { try? PKDrawing(data: $0) } ?? PKDrawing()
        if !context.coordinator.isEditing,
           canvas.drawing.dataRepresentation() != incoming.dataRepresentation() {
            canvas.drawing = incoming
        }

        context.coordinator.apply(tool: tool, color: color, width: width, to: canvas)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: DrawingCanvas
        var isEditing = false

        init(_ parent: DrawingCanvas) { self.parent = parent }

        func apply(tool: InkTool, color: InkColor, width: InkWidth, to canvas: PKCanvasView) {
            guard let inkType = tool.inkType else {
                canvas.tool = PKEraserTool(.bitmap)
                return
            }
            // Always hand PencilKit the light-mode colour.
            //
            // PencilKit adapts ink for dark mode itself: it treats the colour it is given
            // as the one for light backgrounds and inverts it on dark. Passing the dark
            // variant meant the near-white ink was inverted a second time and came out
            // black — invisible on a dark page. One inversion, not two.
            canvas.tool = PKInkingTool(inkType,
                                       color: color.uiColor(for: .light),
                                       width: width.points(for: tool))
        }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) { isEditing = true }
        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) { isEditing = false }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            if parent.scribbleToErase, applyScribbleErase(on: canvasView) { return }
            let encoded = canvasView.drawing.dataRepresentation()
            if parent.data != encoded { parent.data = encoded }
        }

        // MARK: - Scribble to erase

        private let detector = ScribbleDetector()

        /// If the stroke just drawn was a scratch-out, delete it and whatever it crossed.
        /// Returns true when it acted, so the caller does not also save the scribble.
        private func applyScribbleErase(on canvasView: PKCanvasView) -> Bool {
            let strokes = canvasView.drawing.strokes
            guard strokes.count >= 2, let last = strokes.last else { return false }

            let scribblePoints = points(of: last)
            guard detector.isScribble(scribblePoints) else { return false }

            let others = strokes.dropLast().map(points(of:))
            let crossed = Set(detector.strokesCrossed(by: scribblePoints, candidates: Array(others)))
            guard !crossed.isEmpty else { return false }

            // Drop the crossed strokes and the scratch-out itself.
            var remaining: [PKStroke] = []
            for (index, stroke) in strokes.enumerated() {
                if index == strokes.count - 1 { continue }
                if crossed.contains(index) { continue }
                remaining.append(stroke)
            }

            let updated = PKDrawing(strokes: remaining)
            canvasView.drawing = updated
            parent.data = updated.dataRepresentation()

            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return true
        }

        /// A stroke's path in canvas coordinates, sampled evenly.
        private func points(of stroke: PKStroke) -> [CGPoint] {
            stroke.path
                .interpolatedPoints(by: .distance(6))
                .map { $0.location.applying(stroke.transform) }
        }
    }
}

/// A canvas that never offers the system edit menu.
///
/// Resting the Pencil or a finger for a moment brings up iPadOS's Copy / Paste bubble over
/// the drawing. It is never useful here — there is nothing to paste a drawing into — and it
/// interrupts writing, which is the one thing this view exists for.
private final class MenulessCanvasView: PKCanvasView {
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        false
    }

    override func buildMenu(with builder: any UIMenuBuilder) {
        // Leave the menu empty rather than calling super, so nothing is offered at all.
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        stripEditMenu()
    }

    /// PencilKit installs its edit-menu interaction lazily, and reinstalls it after some
    /// tool changes, so removing it once on `didMoveToWindow` was not enough — the
    /// Select All / Insert Space bubble came back. Strip it on every layout pass, and
    /// from the subviews PencilKit adds as well.
    override func layoutSubviews() {
        super.layoutSubviews()
        stripEditMenu()
    }

    private func stripEditMenu() {
        func strip(_ view: UIView) {
            for interaction in view.interactions where interaction is UIEditMenuInteraction {
                view.removeInteraction(interaction)
            }
            for sub in view.subviews { strip(sub) }
        }
        strip(self)
    }

    /// Long-press is what raises the menu. Swallowing it with a recognizer that does
    /// nothing means the system gesture never wins.
    override func addGestureRecognizer(_ recognizer: UIGestureRecognizer) {
        super.addGestureRecognizer(recognizer)
    }
}

extension PKDrawing {
    /// Serialised ink is never zero bytes, so "did they actually write something?" has to
    /// ask about strokes rather than about the size of the Data.
    static func hasStrokes(_ data: Data?) -> Bool {
        guard let data, let drawing = try? PKDrawing(data: data) else { return false }
        return !drawing.strokes.isEmpty
    }
}

/// Renders saved ink without accepting input — used for the answer side and history.
struct DrawingThumbnail: View {
    let data: Data?
    var height: CGFloat = 120

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            if let data, let drawing = try? PKDrawing(data: data), !drawing.bounds.isEmpty {
                let bounds = drawing.bounds
                let scale = min(geo.size.width / bounds.width, geo.size.height / bounds.height, 1)
                Image(uiImage: render(drawing, in: bounds))
                    .resizable()
                    .scaledToFit()
                    .frame(width: bounds.width * scale, height: bounds.height * scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear
            }
        }
        .frame(height: height)
    }

    /// Rasterised with the current style, so PencilKit performs the same single dark-mode
    /// adaptation here that the live canvas does. Ink stored as black therefore shows white
    /// on a dark page, and the thumbnail matches what was written.
    private func render(_ drawing: PKDrawing, in bounds: CGRect) -> UIImage {
        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        var image = UIImage()
        traits.performAsCurrent {
            image = drawing.image(from: bounds, scale: UIScreen.main.scale)
        }
        return image
    }
}
