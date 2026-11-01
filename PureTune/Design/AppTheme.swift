import SwiftUI

enum AppTheme {
    static let background = Color(red: 0.035, green: 0.045, blue: 0.075)
    static let backgroundTop = Color(red: 0.09, green: 0.11, blue: 0.17)
    static let ice = Color(red: 0.64, green: 0.87, blue: 1.0)
    static let lavender = Color(red: 0.79, green: 0.66, blue: 1.0)
    static let mint = Color(red: 0.58, green: 0.95, blue: 0.82)
    static let warm = Color(red: 1.0, green: 0.76, blue: 0.62)
}

struct AuroraBackground: View {
    @State private var isExpanded = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.backgroundTop, AppTheme.background, .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            GeometryReader { proxy in
                Circle()
                    .fill(AppTheme.ice.opacity(0.24))
                    .frame(width: proxy.size.width * 0.95)
                    .blur(radius: 85)
                    .offset(
                        x: isExpanded ? -proxy.size.width * 0.22 : -proxy.size.width * 0.38,
                        y: -proxy.size.height * 0.28
                    )

                Circle()
                    .fill(AppTheme.lavender.opacity(0.2))
                    .frame(width: proxy.size.width * 0.8)
                    .blur(radius: 95)
                    .offset(
                        x: isExpanded ? proxy.size.width * 0.46 : proxy.size.width * 0.28,
                        y: proxy.size.height * 0.12
                    )

                Circle()
                    .fill(AppTheme.mint.opacity(0.11))
                    .frame(width: proxy.size.width * 0.7)
                    .blur(radius: 100)
                    .offset(
                        x: isExpanded ? -proxy.size.width * 0.37 : -proxy.size.width * 0.2,
                        y: proxy.size.height * 0.72
                    )
            }

            LinearGradient(
                colors: [
                    Color.white.opacity(0.045),
                    .clear,
                    Color.black.opacity(0.32)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(
                .easeInOut(duration: 12)
                .repeatForever(autoreverses: true)
            ) {
                isExpanded = true
            }
        }
    }
}

private struct GlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color
    let strokeOpacity: Double

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .background {
                shape.fill(.ultraThinMaterial)
            }
            .background {
                shape.fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(0.16),
                            Color.white.opacity(0.035),
                            Color.black.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            .overlay {
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(strokeOpacity + 0.08),
                                Color.white.opacity(strokeOpacity * 0.35),
                                Color.white.opacity(strokeOpacity * 0.6)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            }
            .overlay {
                shape
                    .inset(by: 1)
                    .stroke(Color.white.opacity(0.035), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.24), radius: 24, x: 0, y: 12)
    }
}

extension View {
    func glassPanel(
        cornerRadius: CGFloat = 24,
        tint: Color = .clear,
        strokeOpacity: Double = 0.14
    ) -> some View {
        modifier(
            GlassPanelModifier(
                cornerRadius: cornerRadius,
                tint: tint,
                strokeOpacity: strokeOpacity
            )
        )
    }
}

struct GlassIconButton: View {
    let systemName: String
    let label: String
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
                .frame(width: size, height: size)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.36),
                                    Color.white.opacity(0.06)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                }
                .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel(label)
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(
                .spring(response: 0.28, dampingFraction: 0.72),
                value: configuration.isPressed
            )
    }
}

struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(Color.black.opacity(0.8))
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white,
                                AppTheme.ice.opacity(0.9)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.7), lineWidth: 0.7)
            }
            .shadow(color: AppTheme.ice.opacity(0.24), radius: 18, y: 9)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(
                .spring(response: 0.28, dampingFraction: 0.72),
                value: configuration.isPressed
            )
    }
}

enum ArtworkPalette {
    private static let palettes: [[Color]] = [
        [AppTheme.ice, Color(red: 0.3, green: 0.46, blue: 0.88)],
        [AppTheme.lavender, Color(red: 0.56, green: 0.34, blue: 0.84)],
        [AppTheme.mint, Color(red: 0.26, green: 0.66, blue: 0.6)],
        [AppTheme.warm, Color(red: 0.92, green: 0.43, blue: 0.48)]
    ]

    static func colors(for song: Song) -> [Color] {
        let seed = song.title.unicodeScalars.reduce(0) { partial, scalar in
            (partial &* 31 &+ Int(scalar.value)) & 0x7fff_ffff
        }
        return palettes[seed % palettes.count]
    }
}
