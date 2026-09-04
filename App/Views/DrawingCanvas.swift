import SwiftUI
import PencilKit

/// Wraps `PKCanvasView`. This one type is the whole Apple Pencil story: pressure, tilt,
/// palm rejection, the low-latency ink pipeline, the double-tap-to-erase gesture and
/// undo all come from PencilKit for free.
struct DrawingCanvas: UIViewRepresentable {
    @Binding var data: Data?
    /// Show the system tool palette (pens, eraser, colours, ruler).
    var showsToolPicker: Bool = true
    var isReadOnly: Bool = false
    /// Set false to let a finger draw too; true means Pencil-only, finger scrolls.
    var pencilOnly: Bool = true

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawingPolicy = pencilOnly ? .pencilOnly : .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.alwaysBounceVertical = false
        canvas.isUserInteractionEnabled = !isReadOnly

        if let data, let drawing = try? PKDrawing(data: data) {
            canvas.drawing = drawing
        }
        context.coordinator.canvas = canvas
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        canvas.isUserInteractionEnabled = !isReadOnly
        canvas.drawingPolicy = pencilOnly ? .pencilOnly : .anyInput

        // Only push external changes in; never stomp on ink the user is mid-stroke on.
        let incoming = data.flatMap { try? PKDrawing(data: $0) } ?? PKDrawing()
        if !context.coordinator.isEditing, canvas.drawing.dataRepresentation() != incoming.dataRepresentation() {
            canvas.drawing = incoming
        }

        context.coordinator.setToolPickerVisible(showsToolPicker && !isReadOnly, for: canvas)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: DrawingCanvas
        weak var canvas: PKCanvasView?
        private var toolPicker: PKToolPicker?
        var isEditing = false

        init(_ parent: DrawingCanvas) { self.parent = parent }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) { isEditing = true }
        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) { isEditing = false }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let encoded = canvasView.drawing.dataRepresentation()
            if parent.data != encoded { parent.data = encoded }
        }

        func setToolPickerVisible(_ visible: Bool, for canvas: PKCanvasView) {
            guard let window = canvas.window else { return }
            let picker = toolPicker ?? PKToolPicker.shared(for: window) ?? PKToolPicker()
            toolPicker = picker
            picker.setVisible(visible, forFirstResponder: canvas)
            picker.addObserver(canvas)
            if visible { canvas.becomeFirstResponder() }
        }
    }
}

/// Renders saved ink without accepting input — used for the answer side and history.
struct DrawingThumbnail: View {
    let data: Data?
    var height: CGFloat = 120

    var body: some View {
        GeometryReader { geo in
            if let data, let drawing = try? PKDrawing(data: data), !drawing.bounds.isEmpty {
                let bounds = drawing.bounds
                let scale = min(geo.size.width / bounds.width, geo.size.height / bounds.height, 1)
                Image(uiImage: drawing.image(from: bounds, scale: UIScreen.main.scale))
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
}
