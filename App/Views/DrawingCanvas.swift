import SwiftUI
import PencilKit

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

    /// Called when a finger taps, or swipes left/right, on the canvas.
    var onFlip: (() -> Void)?

    /// UI tests cannot synthesise Apple Pencil input, so they opt into finger drawing
    /// through a launch argument. Nothing ships with this enabled.
    private var effectivePencilOnly: Bool {
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-allow-finger") { return false }
        return pencilOnly
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawingPolicy = effectivePencilOnly ? .pencilOnly : .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.alwaysBounceVertical = false
        canvas.isUserInteractionEnabled = !isReadOnly

        if let data, let drawing = try? PKDrawing(data: data) {
            canvas.drawing = drawing
        }

        if onFlip != nil {
            // A single deliberate fingertip tap, and nothing else.
            //
            // The first version also accepted swipes, and accepted any direct touch. A
            // resting palm is a direct touch, and dragging a hand across the page looks
            // like a swipe, so the card flipped constantly while writing. Swipes are gone,
            // and the delegate now rejects anything that is not a small fingertip.
            let tap = UITapGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handleFlip))
            tap.numberOfTapsRequired = 1
            tap.numberOfTouchesRequired = 1
            tap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            tap.delegate = context.coordinator
            canvas.addGestureRecognizer(tap)
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

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
        var parent: DrawingCanvas
        var isEditing = false

        init(_ parent: DrawingCanvas) { self.parent = parent }

        func apply(tool: InkTool, color: InkColor, width: InkWidth, to canvas: PKCanvasView) {
            guard let inkType = tool.inkType else {
                canvas.tool = PKEraserTool(.bitmap)
                return
            }
            let style = canvas.traitCollection.userInterfaceStyle
            canvas.tool = PKInkingTool(inkType,
                                       color: color.uiColor(for: style),
                                       width: width.points(for: tool))
        }

        @objc func handleFlip() {
            parent.onFlip?()
        }

        /// A fingertip contact patch is small; a palm or forearm is not. iPadOS reports
        /// the contact radius, so the two can be told apart before the tap ever fires.
        private static let maximumFingertipRadius: CGFloat = 30

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldReceive touch: UITouch) -> Bool {
            // The Pencil draws; it never navigates.
            guard touch.type == .direct else { return false }

            // Reject broad contacts: resting palms, knuckles, a forearm on the page.
            if touch.majorRadius > Self.maximumFingertipRadius { return false }

            // While ink is being laid down, a stray hand touch is not a deliberate tap.
            if isEditing { return false }

            return true
        }

        /// Never let the flip tap pre-empt PencilKit's own gestures.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            false
        }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) { isEditing = true }
        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) { isEditing = false }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let encoded = canvasView.drawing.dataRepresentation()
            if parent.data != encoded { parent.data = encoded }
        }
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

    /// PencilKit renders ink for a trait environment, so a drawing made in light mode has
    /// to be rasterised with the current style or dark-mode handwriting comes out invisible.
    private func render(_ drawing: PKDrawing, in bounds: CGRect) -> UIImage {
        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        var image = UIImage()
        traits.performAsCurrent {
            image = drawing.image(from: bounds, scale: UIScreen.main.scale)
        }
        return image
    }
}
