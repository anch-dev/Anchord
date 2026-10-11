import SwiftUI

// Shared visual language for the home screen and the song workspace, so
// every screen reads as one app.

/// A pair of colors used for card tints and gradients. Each song gets a
/// stable palette derived from its UUID (not `hashValue`, which changes
/// between launches).
struct CardPalette {
    let start: Color
    let end: Color

    var gradient: LinearGradient {
        LinearGradient(colors: [start, end], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let violet = CardPalette(start: .indigo, end: .purple)
    static let sunset = CardPalette(start: .pink, end: .orange)
    static let ocean = CardPalette(start: .teal, end: .blue)
    static let forest = CardPalette(start: .mint, end: .green)
    static let ember = CardPalette(start: .orange, end: .red)
    static let bloom = CardPalette(start: .purple, end: .pink)

    static let all: [CardPalette] = [.violet, .sunset, .ocean, .forest, .ember, .bloom]

    static func forID(_ id: UUID) -> CardPalette {
        all[Int(id.uuid.0) % all.count]
    }
}

/// Grouped background with two soft color glows at the top. The home
/// screen uses the default purple/orange; a song uses its own palette.
struct AnchordBackground: View {
    var palette: CardPalette?

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemGroupedBackground)
            RadialGradient(
                colors: [(palette?.start ?? .purple).opacity(0.24), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 420
            )
            RadialGradient(
                colors: [(palette?.end ?? .orange).opacity(0.16), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 360
            )
        }
    }
}

/// Rounded card surface used across the app.
struct CardBackground: ViewModifier {
    var cornerRadius: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }
}

extension View {
    func anchordCard(cornerRadius: CGFloat = 22) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius))
    }
}

struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
