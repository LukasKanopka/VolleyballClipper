import CoreGraphics
import Foundation

struct AnalyzerConfig: Sendable {
    var downsampleWidth: Int = 640
    var downsampleHeight: Int = 360

    /// Ignore players smaller than this fraction of the frame height.
    var minBoundingBoxHeight: CGFloat = 0.15

    var minJointConfidence: Float = 0.2

    /// Used to normalize joint speed (in normalized-units / second) into 0...1.
    var energyMaxJointSpeed: Float = 1.2

    /// For high-fps sources, run Vision on every Nth frame.
    var maxVisionRate: Float = 30
}
