import SwiftUI
import os

/// Phase 2 spike: one bundled piece, one part, engraved for the screen at five sizes,
/// turned by tap, swipe or a pedal's keys. Replaced by the real reader in phase 3.
struct SpikeReaderView: View {
    static let staffHeights: [CGFloat] = [40, 48, 56, 64, 72]
    private static let log = Logger(subsystem: "be.kvds.largescore", category: "engraving")

    @State private var engraver = VerovioEngraver()
    @State private var pages: [SVGScene] = []
    @State private var page = 0
    @State private var sizeIndex = 4
    @State private var failed = false
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focused: Bool

    private let margins = EdgeInsets(top: 56, leading: 64, bottom: 88, trailing: 64)

    var body: some View {
        GeometryReader { proxy in
            let area = CGSize(width: proxy.size.width - margins.leading - margins.trailing,
                              height: proxy.size.height - margins.top - margins.bottom)
            ZStack(alignment: .bottomTrailing) {
                (colorScheme == .dark ? Color.black : Color.white).ignoresSafeArea()
                if pages.indices.contains(page) {
                    ScoreCanvas(scene: pages[page], ink: colorScheme == .dark ? .white : .black)
                        .frame(width: area.width, height: area.height)
                        .padding(margins)
                } else if failed {
                    Text("This music could not be read.")
                        .font(.title)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if !pages.isEmpty {
                    Text("Page \(page + 1) of \(pages.count)")
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 40)
                        .padding(.bottom, 28)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                if location.x > proxy.size.width * 2 / 3 { turn(1) }
                else if location.x < proxy.size.width / 3 { turn(-1) }
                else { sizeIndex = (sizeIndex + 1) % Self.staffHeights.count }
            }
            .gesture(DragGesture(minimumDistance: 40).onEnded { value in
                if value.translation.width < -40 { turn(1) } else if value.translation.width > 40 { turn(-1) }
            })
            .task(id: LayoutRequest(pageSize: area, staffHeight: Self.staffHeights[sizeIndex])) {
                await engrave(for: area)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(keys: [.rightArrow, .downArrow, .pageDown, .space]) { _ in turn(1); return .handled }
        .onKeyPress(keys: [.leftArrow, .upArrow, .pageUp]) { _ in turn(-1); return .handled }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Evening Air")
        .accessibilityValue(pages.isEmpty ? "" : "Page \(page + 1) of \(pages.count)")
        .accessibilityAdjustableAction { direction in
            turn(direction == .increment ? 1 : -1)
        }
    }

    private func turn(_ step: Int) {
        let target = page + step
        guard pages.indices.contains(target) else { return }
        page = target
    }

    private func engrave(for area: CGSize) async {
        guard area.width > 100, area.height > 100,
              let url = Bundle.main.url(forResource: "evening-air", withExtension: "musicxml"),
              let xml = try? String(contentsOf: url, encoding: .utf8) else { return }
        let request = LayoutRequest(pageSize: area, staffHeight: Self.staffHeights[sizeIndex])
        do {
            let score = try await engraver.engrave(musicXML: xml, request: request)
            let clock = ContinuousClock()
            let start = clock.now
            let scenes = score.pages.compactMap { SVGScene(svg: $0.svg) }
            Self.log.info("engraved \(score.pages.count) pages in \(score.duration), read in \(clock.now - start)")
            pages = scenes
            page = min(page, max(scenes.count - 1, 0))
        } catch {
            failed = true
        }
    }
}
