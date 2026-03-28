import SwiftUI

struct DJModePicker: View {
    @Binding var selectedMode: DJMode

    var body: some View {
        Picker("DJ Mode", selection: $selectedMode) {
            Text("Solo").tag(DJMode.solo)
            Text("Hot Seat").tag(DJMode.hotSeat)
            Text("Free for All").tag(DJMode.freeForAll)
        }
        .pickerStyle(.segmented)
    }
}
