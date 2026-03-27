import SwiftUI

/// Small badge showing connection state.
struct ConnectionStatusBadge: View {
    let state: ConnectionState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(PirateTheme.body(11))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var color: Color {
        switch state {
        case .connected: PirateTheme.signal
        case .connecting, .reconnecting, .resyncing: PirateTheme.flare
        case .disconnected, .failed: .red.opacity(0.8)
        }
    }

    private var label: String {
        switch state {
        case .connected: "connected"
        case .connecting: "connecting..."
        case .reconnecting(let attempt): "reconnecting (\(attempt))..."
        case .resyncing: "resyncing..."
        case .disconnected: "disconnected"
        case .failed(let reason): "failed: \(reason)"
        }
    }
}
