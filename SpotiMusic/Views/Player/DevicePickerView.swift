import SwiftUI

/// AirPlay-style output picker listing Spotify Connect devices, including this Mac.
struct DeviceButton: View {
    var tint: Color
    @State private var showing = false

    var body: some View {
        Button { showing.toggle() } label: {
            Image(systemName: "airplayaudio")
                .font(.system(size: 15))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .help("Choose where to play")
        .popover(isPresented: $showing, arrowEdge: .top) {
            DevicePickerView()
        }
    }
}

struct DevicePickerView: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var web: WebPlaybackHost
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Play On")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)

            if case .failed(let message) = web.status {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Built-in player unavailable", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Retry") { web.restart() }
                        .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            } else if web.status == .connecting {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Starting built-in player…").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }

            Divider()

            if loading && player.devices.isEmpty {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(16)
            } else if player.devices.isEmpty {
                Text("No devices found. Open Spotify on a phone, speaker or computer.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(14)
            } else {
                VStack(spacing: 2) {
                    ForEach(player.devices) { device in
                        DeviceRow(device: device, isThisMac: device.deviceID == player.localDeviceID)
                    }
                }
                .padding(6)
            }
        }
        .frame(width: 280)
        .task {
            await player.loadDevices()
            loading = false
        }
    }
}

private struct DeviceRow: View {
    let device: Device
    let isThisMac: Bool
    @EnvironmentObject private var player: PlayerController
    @State private var hovering = false

    var body: some View {
        Button {
            guard let id = device.deviceID, !device.isActive else { return }
            Task { await player.transfer(to: id) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isThisMac ? "laptopcomputer" : device.symbolName)
                    .font(.system(size: 15))
                    .frame(width: 22)
                    .foregroundStyle(device.isActive ? Color.accentColor : .primary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(isThisMac ? "This Mac" : device.name)
                        .font(.system(size: 13))
                    if isThisMac || device.isActive {
                        Text(device.isActive ? "Playing" : "SpotiMusic")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if device.isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(hovering ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(device.isRestricted == true || device.deviceID == nil)
        .onHover { hovering = $0 }
    }
}
