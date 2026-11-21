import SwiftUI

/// Every piece as a large card. Adding music arrives with importing.
struct LibraryView: View {
    @Environment(ReaderSettings.self) private var settings
    @State private var open: Piece?
    @ScaledMetric(relativeTo: .title2) private var cardWidth: CGFloat = 320

    private var pieces: [Piece] { [.sample(for: settings.instrument)] }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: min(cardWidth, 600)), spacing: 24)], spacing: 24) {
                    ForEach(pieces) { piece in
                        Button { open = piece } label: { PieceCard(piece: piece) }
                            .buttonStyle(.plain)
                    }
                }
                .air(.horizontal, 48)
                .air(.vertical, 24)
            }
            .background(Palette.ground)
            .navigationTitle("Library")
        }
        .fullScreenCover(item: $open) { piece in
            ReaderView(piece: piece, backTitle: "Library")
        }
    }
}

struct PieceCard: View {
    let piece: Piece

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(piece.title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
            if let composer = piece.composer {
                Text(composer)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .air(.horizontal, 32)
        .air(.vertical, 24)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 26))
        .contentShape(RoundedRectangle(cornerRadius: 26))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// What a tab shows while it has nothing: one plain line, and what to do if anything.
struct EmptyTab: View {
    let title: LocalizedStringResource
    let heading: LocalizedStringResource
    var message: LocalizedStringResource?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text(heading)
                    .font(.title.weight(.semibold))
                if let message {
                    Text(message)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .air(.all, 48)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.ground)
            .navigationTitle(Text(title))
        }
    }
}
