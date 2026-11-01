import SwiftUI

struct ArtworkView: View {
    @Environment(\.colorScheme) private var colorScheme

    let song: Song
    let url: URL
    var cornerRadius: CGFloat = 14
    var isCurrent = false
    var isPlaying = false
    var showsPlaybackBadge = false

    @State private var image: UIImage?

    private var palette: [Color] {
        ArtworkPalette.colors(for: song)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: palette.map { $0.opacity(isCurrent ? 0.9 : 0.68) },
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                Image(systemName: isCurrent && isPlaying ? "waveform" : "music.note")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white.opacity(0.94))
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            }

            if showsPlaybackBadge, isCurrent {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 24, height: 24)
                    .overlay {
                        Image(systemName: isPlaying ? "waveform" : "pause.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                    .padding(7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color.white.opacity(0.24), Color.white.opacity(0.05)]
                            : [Color.white.opacity(0.82), Color.black.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.7
                )
        }
        .task(id: song.fileName) {
            image = await ArtworkStore.shared.artwork(for: song, url: url)
        }
    }
}
