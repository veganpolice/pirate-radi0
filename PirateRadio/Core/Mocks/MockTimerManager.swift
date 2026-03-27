import Foundation
import SwiftUI

/// Drives fake events on timers during demo mode.
/// Fires member joins, song requests, votes, and hot-seat countdowns.
@Observable
@MainActor
final class MockTimerManager {
    private(set) var isRunning = false
    private var tasks: [Task<Void, Never>] = []

    // Events that views can observe
    var lastEvent: MockEvent?

    enum MockEvent: Equatable {
        case memberJoined(String)
        case memberLeft(String)
        case songRequested(trackName: String, by: String)
        case voteCast(trackName: String, by: String, isUpvote: Bool)
        case hotSeatRotation(newDJ: String)
        case signalLost
        case signalReconnected
        case voiceClipReceived(from: String)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        startCrewDrip()
        startMemberEvents()
        startVoteEvents()
        startRequestEvents()
    }

    func stop() {
        isRunning = false
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    func triggerSignalLost() {
        lastEvent = .signalLost
        let task = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            lastEvent = .signalReconnected
        }
        tasks.append(task)
    }

    func triggerHotSeatRotation(newDJ: String) {
        lastEvent = .hotSeatRotation(newDJ: newDJ)
    }

    func triggerVoiceClip(from name: String) {
        lastEvent = .voiceClipReceived(from: name)
    }

    // MARK: - Private Timers

    /// Slowly add late-joining members one at a time.
    private func startCrewDrip() {
        let task = Task {
            for member in MockData.lateJoiners {
                let delay = Double.random(in: 8...18)
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled && isRunning else { break }
                lastEvent = .memberJoined(member.displayName)
            }
        }
        tasks.append(task)
    }

    private func startMemberEvents() {
        let task = Task {
            while !Task.isCancelled && isRunning {
                let delay = Double.random(in: 15...30)
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled && isRunning else { break }

                let names = ["Gondola Greg", "Black Diamond", "Fresh Tracks", "Mogul Queen"]
                let name = names.randomElement()!
                let isJoin = Bool.random()
                lastEvent = isJoin ? .memberJoined(name) : .memberLeft(name)
            }
        }
        tasks.append(task)
    }

    private func startVoteEvents() {
        let task = Task {
            while !Task.isCancelled && isRunning {
                let delay = Double.random(in: 5...10)
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled && isRunning else { break }

                let trackNames = MockData.tracks.prefix(10).map(\.name)
                let voters = MockData.members.map(\.displayName)
                lastEvent = .voteCast(
                    trackName: trackNames.randomElement()!,
                    by: voters.randomElement()!,
                    isUpvote: Bool.random()
                )
            }
        }
        tasks.append(task)
    }

    private func startRequestEvents() {
        let task = Task {
            while !Task.isCancelled && isRunning {
                let delay = Double.random(in: 20...40)
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled && isRunning else { break }

                let tracks = MockData.tracks.suffix(15)
                let track = tracks.randomElement()!
                let requesters = MockData.members.dropFirst().map(\.displayName)
                lastEvent = .songRequested(trackName: track.name, by: requesters.randomElement()!)
            }
        }
        tasks.append(task)
    }
}
