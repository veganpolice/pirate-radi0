import Foundation

/// Abstraction over system volume control for testability.
protocol VolumeController: AnyObject {
    var currentVolume: Float { get }
    func setVolume(_ volume: Float)
}
