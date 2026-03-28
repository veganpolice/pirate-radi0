import Foundation

/// Abstraction over a speed data source (GPS, mock, etc.) for testability.
protocol SpeedProvider: AnyObject, Sendable {
    /// Continuous stream of speed values in miles per hour.
    var speedStream: AsyncStream<Double> { get }
    func startUpdating() async
    func stopUpdating() async
}
