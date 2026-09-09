import SwiftUI

enum GEDTheme {
    static let ink = Color(red: 0.10, green: 0.13, blue: 0.20)
    static let accent = Color(red: 0.31, green: 0.28, blue: 0.90)
    static let mint = Color(red: 0.18, green: 0.68, blue: 0.52)
    static let warm = Color(red: 0.98, green: 0.62, blue: 0.24)
    static let canvas = Color(red: 0.96, green: 0.96, blue: 0.98)
}

struct StatusPill: View {
    let text: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(.white)
            .background(GEDTheme.accent.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 16))
    }
}

