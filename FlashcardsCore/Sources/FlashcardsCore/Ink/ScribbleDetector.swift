import Foundation
import CoreGraphics

/// Recognises a scratch-out: the quick back-and-forth people do to cross something out.
///
/// The hard part is not detecting scribbles, it is *not* detecting handwriting. Letters
/// like m, w and z reverse direction too, so a naive reversal count deletes your work. A
/// scribble is distinguished by being dense as well as reversing: it covers far more path
/// length than its own size, because it goes over the same ground repeatedly.
public struct ScribbleDetector: Sendable {

    /// Direction changes along the dominant axis before a stroke can be a scribble.
    public var minimumReversals: Int
    /// Path length as a multiple of the bounding box's diagonal. Handwriting is close to 1;
    /// a scratch-out is several times its own size.
    public var minimumDensity: CGFloat
    /// Ignore very short marks: a flick of the pen is not a deletion.
    public var minimumLength: CGFloat
    /// Points per second. Crossing something out is a fast, careless movement; writing is
    /// slow and deliberate even when it loops. Speed is the signal that best separates the
    /// two, and shape alone was deleting far too much.
    public var minimumSpeed: CGFloat
    /// A scratch-out is roughly a band: wide along one axis, shallow across it. Writing
    /// fills its box more evenly.
    public var minimumElongation: CGFloat

    public init(minimumReversals: Int = 5, minimumDensity: CGFloat = 2.6,
                minimumLength: CGFloat = 80, minimumSpeed: CGFloat = 420,
                minimumElongation: CGFloat = 1.3) {
        self.minimumReversals = minimumReversals
        self.minimumDensity = minimumDensity
        self.minimumLength = minimumLength
        self.minimumSpeed = minimumSpeed
        self.minimumElongation = minimumElongation
    }

    /// `duration` is how long the stroke took. Without it, speed cannot be judged and the
    /// stroke is refused: deleting someone's work on a guess is worse than doing nothing.
    /// Everything measured about a stroke, and whether it qualified. Returned so the app
    /// can record real strokes and the thresholds can be set from measurements rather
    /// than from guesses — the first three attempts at these numbers were guesses.
    public struct Measurement: Sendable, Equatable {
        public var pointCount: Int
        public var length: CGFloat
        public var diagonal: CGFloat
        public var density: CGFloat
        public var elongation: CGFloat
        public var reversals: Int
        public var duration: TimeInterval
        public var speed: CGFloat
        public var isScribble: Bool
        /// The first rule that refused it, for reading back later.
        public var rejectedBy: String?
    }

    public func measure(_ points: [CGPoint], duration: TimeInterval?) -> Measurement {
        let length = pathLength(points)
        let box = boundingBox(points)
        let diagonal = sqrt(box.width * box.width + box.height * box.height)
        let density = diagonal > 0 ? length / diagonal : 0
        let long = max(box.width, box.height)
        let short = max(min(box.width, box.height), 1)
        let elongation = long / short
        let reversalCount = reversals(points)
        let seconds = duration ?? 0
        let speed = seconds > 0 ? length / CGFloat(seconds) : 0

        var rejected: String?
        if points.count < 8 { rejected = "points" }
        else if length < minimumLength { rejected = "length" }
        else if diagonal <= 0 { rejected = "diagonal" }
        else if density < minimumDensity { rejected = "density" }
        else if elongation < minimumElongation { rejected = "elongation" }
        else if reversalCount < minimumReversals { rejected = "reversals" }
        else if seconds <= 0 { rejected = "no-timing" }
        else if speed < minimumSpeed { rejected = "speed" }

        return Measurement(
            pointCount: points.count, length: length, diagonal: diagonal, density: density,
            elongation: elongation, reversals: reversalCount, duration: seconds, speed: speed,
            isScribble: rejected == nil, rejectedBy: rejected
        )
    }

    public func isScribble(_ points: [CGPoint], duration: TimeInterval? = nil) -> Bool {
        guard points.count >= 8 else { return false }

        let length = pathLength(points)
        guard length >= minimumLength else { return false }

        let box = boundingBox(points)
        let diagonal = sqrt(box.width * box.width + box.height * box.height)
        guard diagonal > 0 else { return false }
        guard length / diagonal >= minimumDensity else { return false }

        // Long and thin, the shape of scratching something out.
        let long = max(box.width, box.height)
        let short = max(min(box.width, box.height), 1)
        guard long / short >= minimumElongation else { return false }

        guard reversals(points) >= minimumReversals else { return false }

        guard let duration, duration > 0 else { return false }
        return length / CGFloat(duration) >= minimumSpeed
    }

    /// Direction changes along whichever axis the stroke travels furthest on.
    func reversals(_ points: [CGPoint]) -> Int {
        let box = boundingBox(points)
        let horizontal = box.width >= box.height
        let values = points.map { horizontal ? $0.x : $0.y }

        var count = 0
        var lastSign = 0
        for i in 1..<values.count {
            let delta = values[i] - values[i - 1]
            // Ignore jitter: only a real move counts as a direction.
            guard abs(delta) > 1.5 else { continue }
            let sign = delta > 0 ? 1 : -1
            if lastSign != 0, sign != lastSign { count += 1 }
            lastSign = sign
        }
        return count
    }

    func pathLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count > 1 else { return 0 }
        var total: CGFloat = 0
        for i in 1..<points.count {
            total += hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)
        }
        return total
    }

    func boundingBox(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Which of `candidates` the scribble crosses, and should therefore be deleted.
    ///
    /// Whole strokes go, not the overlapping fragment: crossing out half a letter and
    /// leaving the other half is not what anyone means by scratching something out.
    public func strokesCrossed(
        by scribble: [CGPoint], candidates: [[CGPoint]], tolerance: CGFloat = 14
    ) -> [Int] {
        let scribbleBox = boundingBox(scribble).insetBy(dx: -tolerance, dy: -tolerance)

        return candidates.indices.filter { index in
            let candidate = candidates[index]
            guard !candidate.isEmpty else { return false }
            guard boundingBox(candidate).intersects(scribbleBox) else { return false }

            for point in candidate {
                for scribblePoint in scribble {
                    if hypot(point.x - scribblePoint.x, point.y - scribblePoint.y) <= tolerance {
                        return true
                    }
                }
            }
            return false
        }
    }
}
