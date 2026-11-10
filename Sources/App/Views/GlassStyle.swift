import SwiftUI

/// Liquid Glass 风格的轻量实现。
///
/// iOS 26 的系统 `.glassEffect` 只在最新 SDK 上可用，而这个 App 要兼容 iOS 15，
/// 所以这里用「超薄材质 + 高光描边 + 柔和投影」复刻那种悬浮玻璃的观感：
/// 不同系统版本上表现一致，也不会因为 SDK 版本差异编译失败。
struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = 22
    var tint: Color = .clear
    var strokeOpacity: Double = 0.55

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    if tint != .clear {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint.opacity(colorScheme == .dark ? 0.22 : 0.14))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? strokeOpacity * 0.4 : strokeOpacity),
                                Color.white.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.10), radius: 16, x: 0, y: 6)
    }
}

extension View {
    /// 半透明玻璃底板。
    func glassSurface(cornerRadius: CGFloat = 22, tint: Color = .clear, strokeOpacity: Double = 0.55) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, tint: tint, strokeOpacity: strokeOpacity))
    }

    /// 胶囊形玻璃底板。
    func glassCapsule(tint: Color = .clear) -> some View {
        background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
        )
    }
}

/// 列表顶部的小胶囊统计条，用在「已嗅探」「下载」页。
struct GlassStatPill: View {
    let systemImage: String
    let text: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
        }
        .foregroundColor(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .glassCapsule()
    }
}
