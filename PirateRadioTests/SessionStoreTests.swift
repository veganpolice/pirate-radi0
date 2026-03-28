import Foundation
import Testing
@testable import PirateRadio

@Suite("SessionStore State Logic")
@MainActor
struct SessionStoreTests {

    // MARK: - Helpers

    private func makeStore() -> SessionStore {
        SessionStore.demo()
    }

    // MARK: - Member Deduplication

    @Test("handleUpdate with memberJoined deduplicates")
    func memberJoinedDeduplicates() {
        let store = makeStore()
        let initialCount = store.session?.members.count ?? 0

        // Add a new member
        store.handleUpdate(.memberJoined("user-new", "New User"))
        #expect(store.session?.members.count == initialCount + 1)

        // Add the same member again — should update, not duplicate
        store.handleUpdate(.memberJoined("user-new", "Updated Name"))
        #expect(store.session?.members.count == initialCount + 1)

        // Name should be updated
        let member = store.session?.members.first { $0.id == "user-new" }
        #expect(member?.displayName == "Updated Name")
        #expect(member?.isConnected == true)
    }

    // MARK: - State Sync Members

    @Test("handleUpdate with stateSync replaces members")
    func stateSyncReplacesMembers() {
        let store = makeStore()

        // Add some extra members
        store.handleUpdate(.memberJoined("extra-1", "Extra One"))
        store.handleUpdate(.memberJoined("extra-2", "Extra Two"))
        let countBefore = store.session?.members.count ?? 0
        #expect(countBefore >= 3) // DJ + 2 extras

        // stateSync should replace the member list
        let snapshot = SessionSnapshot(
            trackID: nil,
            positionAtAnchor: 0,
            ntpAnchor: 0,
            playbackRate: 0,
            queue: [],
            epoch: 1,
            sequenceNumber: 0,
            members: [
                SessionSnapshot.SnapshotMember(userId: "new-dj", displayName: "New DJ"),
                SessionSnapshot.SnapshotMember(userId: "listener-1", displayName: "Listener"),
            ]
        )
        store.handleUpdate(.stateSynced(snapshot))

        #expect(store.session?.members.count == 2)
        #expect(store.session?.members.contains { $0.id == "new-dj" } == true)
        #expect(store.session?.members.contains { $0.id == "listener-1" } == true)
        // Old extras should be gone
        #expect(store.session?.members.contains { $0.id == "extra-1" } == false)
    }

    // MARK: - Playback Anchor

    @Test("stateSync with active track stores playback anchor")
    func stateSyncStoresPlaybackAnchor() {
        let store = makeStore()

        // Before any stateSync, anchor should be nil
        #expect(store.playbackAnchor == nil)

        let snapshot = SessionSnapshot(
            trackID: "track-123",
            positionAtAnchor: 30.0,
            ntpAnchor: 1_000_000,
            playbackRate: 1.0,
            queue: [],
            epoch: 1,
            sequenceNumber: 0,
            members: [
                SessionSnapshot.SnapshotMember(userId: "dj-1", displayName: "DJ"),
            ]
        )
        store.handleUpdate(.stateSynced(snapshot))

        #expect(store.playbackAnchor != nil)
        #expect(store.playbackAnchor?.trackID == "track-123")
        #expect(store.playbackAnchor?.positionAtAnchor == 30.0)
        #expect(store.playbackAnchor?.ntpAnchor == 1_000_000)
        #expect(store.playbackAnchor?.playbackRate == 1.0)
    }

    @Test("stateSync without track does not set anchor")
    func stateSyncNoTrackNoAnchor() {
        let store = makeStore()

        let snapshot = SessionSnapshot(
            trackID: nil,
            positionAtAnchor: 0,
            ntpAnchor: 0,
            playbackRate: 0,
            queue: [],
            epoch: 1,
            sequenceNumber: 0,
            members: [
                SessionSnapshot.SnapshotMember(userId: "dj-1", displayName: "DJ"),
            ]
        )
        store.handleUpdate(.stateSynced(snapshot))

        #expect(store.playbackAnchor == nil)
    }

}
