import SwiftUI
import UIKit

enum Palette {
    /// 9.5:1 on white; the dark variant 10:1 on black.
    static let accent = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x8C / 255, green: 0xB8 / 255, blue: 0xFF / 255, alpha: 1)
            : UIColor(red: 0x00 / 255, green: 0x40 / 255, blue: 0xA0 / 255, alpha: 1)
    })
    /// White on the light accent, black on the dark one.
    static let onAccent = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? .black : .white
    })
    static let buttonFill = Color(.tertiarySystemFill)
    static let card = Color(.secondarySystemGroupedBackground)
    static let ground = Color(.systemGroupedBackground)
    /// Quieter text that still reads at any size: 6.6:1 on the grouped background in
    /// light, 10:1 on a dark card. The system's secondary grey is 3.3:1 in light,
    /// enough only for large text.
    static let quiet = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0xC7 / 255, green: 0xC7 / 255, blue: 0xCC / 255, alpha: 1)
            : UIColor(red: 0x55 / 255, green: 0x55 / 255, blue: 0x5A / 255, alpha: 1)
    })
}

extension View {
    /// A form section's footer: body size, in the quiet colour.
    func formNote() -> some View {
        font(.body).foregroundStyle(Palette.quiet)
    }

    /// A form section's header: headline size, in the quiet colour, as written.
    func formHeading() -> some View {
        font(.headline).foregroundStyle(Palette.quiet).textCase(nil)
    }
}

/// A large capsule button with words: at least 64 pt tall, growing with the text.
struct LargeButtonStyle: ButtonStyle {
    var prominent = false
    /// An icon alone: a circle as tall as the words' buttons.
    var round = false
    @ScaledMetric(relativeTo: .title3) private var height: CGFloat = 64
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(prominent ? Palette.onAccent : Palette.accent)
            .padding(.horizontal, round ? 0 : 28)
            .air(.vertical, round ? 0 : 8)
            .frame(minWidth: round ? height : nil, minHeight: height)
            .background(prominent ? Palette.accent : Palette.buttonFill, in: PillShape(radius: 32))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .contentShape(PillShape(radius: 32))
    }
}

extension ButtonStyle where Self == LargeButtonStyle {
    static var large: LargeButtonStyle { LargeButtonStyle() }
    static var largeProminent: LargeButtonStyle { LargeButtonStyle(prominent: true) }
    static var largeRound: LargeButtonStyle { LargeButtonStyle(round: true) }
}

/// A large title as the screens use it, wrapping rather than cutting.
struct ScreenTitle: View {
    let text: LocalizedStringResource

    var body: some View {
        Text(text)
            .font(.largeTitle.weight(.bold))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// A solid band in `colour` behind the status bar, so scrolled content never shows
    /// through it.
    func solidStatusBar(_ colour: Color) -> some View {
        overlay(alignment: .top) {
            colour
                .frame(height: 0)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
