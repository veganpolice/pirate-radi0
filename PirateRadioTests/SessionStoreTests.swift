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
            djUserID: "new-dj",
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

    // MARK: - DJ Promotion

    @Test("handleUpdate with stateSync promotes new DJ")
    func stateSyncPromotesNewDJ() {
        let store = makeStore()
        let originalDJ = store.session?.djUserID

        // stateSync with a different DJ
        let snapshot = SessionSnapshot(
            trackID: nil,
            positionAtAnchor: 0,
            ntpAnchor: 0,
            playbackRate: 0,
            queue: [],
            djUserID: "promoted-user",
            epoch: 2,
            sequenceNumber: 0,
            members: [
                SessionSnapshot.SnapshotMember(userId: "promoted-user", displayName: "Promoted"),
            ]
        )
        store.handleUpdate(.stateSynced(snapshot))

        #expect(store.session?.djUserID == "promoted-user")
        #expect(store.session?.djUserID != originalDJ)
        #expect(store.session?.epoch == 2)
    }
}
