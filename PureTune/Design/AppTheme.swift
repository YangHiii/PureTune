import SwiftUI
import UIKit

enum AppTheme {
    static let background = adaptive(
        light: UIColor(red: 0.94, green: 0.95, blue: 0.99, alpha: 1),
        dark: UIColor(red: 0.035, green: 0.045, blue: 0.075, alpha: 1)
    )

    static let backgroundTop = adaptive(
        light: UIColor(red: 0.99, green: 0.99, blue: 1, alpha: 1),
        dark: UIColor(red: 0.09, green: 0.11, blue: 0.17, alpha: 1)
    )

    static let ice = Color(red: 0.64, green: 0.87, blue: 1.0)
    static let lavender = Color(red: 0.79, green: 0.66, blue: 1.0)
    static let mint = Color(red: 0.58, green: 0.95, blue: 0.82)
    static let warm = Color(red: 1.0, green: 0.76, blue: 0.62)

    static let textPrimary = adaptive(
        light: UIColor(red: 0.08, green: 0.10, blue: 0.16, alpha: 1),
        dark: UIColor.white
    )

    static let textSecondary = adaptive(
        light: UIColor(red: 0.25, green: 0.28, blue: 0.36, alpha: 1),
        dark: UIColor(white: 1, alpha: 0.72)
    )

    static let textTertiary = adaptive(
        light: UIColor(red: 0.38, green: 0.41, blue: 0.49, alpha: 1),
        dark: UIColor(white: 1, alpha: 0.44)
    )

    static let hairline = adaptive(
        light: UIColor(white: 0.1, alpha: 0.16),
        dark: UIColor(white: 1, alpha: 0.18)
    )

    static let panelHighlight = adaptive(
        light: UIColor(white: 1, alpha: 0.82),
        dark: UIColor(white: 1, alpha: 0.12)
    )

    static let panelShade = adaptive(
        light: UIColor(white: 0.28, alpha: 0.06),
        dark: UIColor(white: 0, alpha: 0.14)
    )

    static let shadow = adaptive(
        light: UIColor(white: 0.12, alpha: 0.18),
        dark: UIColor(white: 0, alpha: 0.42)
    )

    static let controlFill = adaptive(
        light: UIColor(white: 1, alpha: 0.7),
        dark: UIColor(white: 1, alpha: 0.1)
    )

    static let primaryButtonText = adaptive(
        light: UIColor(red: 0.04, green: 0.06, blue: 0.12, alpha: 1),
        dark: UIColor(red: 0.03, green: 0.04, blue: 0.08, alpha: 1)
    )

    static let accentGradient = LinearGradient(
        colors: [ice, lavender],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

struct AuroraBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isExpanded = false

    private var isDark: Bool {
        colorScheme == .dark
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: isDark
                    ? [AppTheme.backgroundTop, AppTheme.background, .black]
                    : [
                        Color(red: 0.99, green: 0.99, blue: 1),
                        Color(red: 0.91, green: 0.94, blue: 1),
                        Color(red: 0.97, green: 0.94, blue: 1)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            GeometryReader { proxy in
                Circle()
                    .fill(AppTheme.ice.opacity(isDark ? 0.24 : 0.42))
                    .frame(width: proxy.size.width * 0.95)
                    .blur(radius: isDark ? 85 : 72)
                    .offset(
                        x: isExpanded ? -proxy.size.width * 0.22 : -proxy.size.width * 0.38,
                        y: -proxy.size.height * 0.28
                    )

                Circle()
                    .fill(AppTheme.lavender.opacity(isDark ? 0.2 : 0.34))
                    .frame(width: proxy.size.width * 0.8)
                    .blur(radius: isDark ? 95 : 78)
                    .offset(
                        x: isExpanded ? proxy.size.width * 0.46 : proxy.size.width * 0.28,
                        y: proxy.size.height * 0.12
                    )

                Circle()
                    .fill(AppTheme.mint.opacity(isDark ? 0.11 : 0.25))
                    .frame(width: proxy.size.width * 0.7)
                    .blur(radius: isDark ? 100 : 82)
                    .offset(
                        x: isExpanded ? -proxy.size.width * 0.37 : -proxy.size.width * 0.2,
                        y: proxy.size.height * 0.72
                    )
            }

            LinearGradient(
                colors: isDark
                    ? [Color.white.opacity(0.045), .clear, Color.black.opacity(0.32)]
                    : [Color.white.opacity(0.5), .clear, Color.white.opacity(0.18)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .onAppear {
            updateAmbientAnimation()
        }
        .onChange(of: scenePhase) { _ in
            updateAmbientAnimation()
        }
        .onChange(of: reduceMotion) { _ in
            updateAmbientAnimation()
        }
    }

    private func updateAmbientAnimation() {
        guard scenePhase == .active, !reduceMotion else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isExpanded = false
            }
            return
        }

        withAnimation(
            .easeInOut(duration: 12)
            .repeatForever(autoreverses: true)
        ) {
            isExpanded = true
        }
    }
}

private struct GlassPanelModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat
    let tint: Color
    let strokeOpacity: Double

    private var isDark: Bool {
        colorScheme == .dark
    }

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
                        colors: isDark
                            ? [
                                tint.opacity(0.16),
                                Color.white.opacity(0.035),
                                Color.black.opacity(0.08)
                            ]
                            : [
                                Color.white.opacity(0.62),
                                tint.opacity(0.1),
                                Color.white.opacity(0.28)
                            ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: isDark
                            ? [
                                Color.white.opacity(strokeOpacity + 0.08),
                                Color.white.opacity(strokeOpacity * 0.35),
                                Color.white.opacity(strokeOpacity * 0.6)
                            ]
                            : [
                                Color.white.opacity(0.9),
                                Color.black.opacity(strokeOpacity * 0.16),
                                Color.white.opacity(0.68)
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
                    .stroke(AppTheme.hairline.opacity(0.32), lineWidth: 0.5)
            }
            .shadow(
                color: isDark ? Color.black.opacity(0.24) : Color.black.opacity(0.09),
                radius: isDark ? 24 : 18,
                x: 0,
                y: isDark ? 12 : 8
            )
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
    @Environment(\.colorScheme) private var colorScheme

    let systemName: String
    let label: String
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .frame(width: size, height: size)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [
                                        Color.white.opacity(0.36),
                                        Color.white.opacity(0.06)
                                    ]
                                    : [
                                        Color.white.opacity(0.92),
                                        Color.black.opacity(0.08)
                                    ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                }
                .shadow(
                    color: AppTheme.shadow.opacity(colorScheme == .dark ? 0.5 : 0.25),
                    radius: 12,
                    y: 6
                )
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
            .foregroundStyle(AppTheme.primaryButtonText)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background {
                Capsule(style: .continuous)
                    .fill(AppTheme.accentGradient)
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.55), lineWidth: 0.7)
            }
            .shadow(color: AppTheme.ice.opacity(0.22), radius: 18, y: 9)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(
                .spring(response: 0.28, dampingFraction: 0.72),
                value: configuration.isPressed
            )
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }

            Spacer()
        }
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
