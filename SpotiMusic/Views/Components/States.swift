import SwiftUI

struct LoadingView: View {
    var body: some View {
        ProgressView()
            .controlSize(.small)
            .frame(maxWidth: .infinity, minHeight: 120)
    }
}

struct MessageView: View {
    let symbol: String
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 17, weight: .semibold))
            if let message {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .padding(.top, 4)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, minHeight: 240)
    }
}

/// Shows the error of a failed load with a retry button.
struct ErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        MessageView(symbol: "exclamationmark.triangle", title: "Couldn't Load", message: message, actionTitle: "Try Again", action: retry)
    }
}

struct SectionTitle: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 19, weight: .bold))
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Large page title used at the top of library pages (Apple Music shows 26pt bold).
struct PageTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 26, weight: .bold))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }
}

/// Accent-filled "Play" and tinted "Shuffle" buttons from Apple Music's album header.
struct PlayShuffleButtons: View {
    var onPlay: () -> Void
    var onShuffle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onPlay) {
                Label("Play", systemImage: "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 92, height: 28)
                    .foregroundStyle(.white)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            Button(action: onShuffle) {
                Label("Shuffle", systemImage: "shuffle")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 92, height: 28)
                    .foregroundStyle(Color.accentColor)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}
