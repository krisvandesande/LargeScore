import AppKit
import PDFKit

/// Where each bar sits on the PDF it was read from: the staves found on its pages,
/// and Audiveris's lines and bar widths from its MusicXML.
nonisolated enum PDFPlaces {
    struct Place: Equatable {
        /// The PDF page, from 0.
        var page: Int
        /// The bar's staff, as fractions of the page, from its top left.
        var bar: CGRect
        /// The whole line of music the bar is on.
        var line: CGRect
    }

    /// A staff found on a PDF page, as fractions of the page from its top left.
    struct Staff: Equatable {
        var page: Int
        var rect: CGRect
    }

    /// Each bar's place: Audiveris's lines of music (where it started a new system) laid
    /// on the staves found in the PDF, in reading order, and each line's bars spread
    /// over its staff by the widths Audiveris measured.
    static func bars(in xml: String, staves found: [Staff]) -> [String: Place] {
        let part = xml.range(of: "</part>").map { String(xml[..<$0.lowerBound]) } ?? xml
        let perSystem = max(part.firstMatch(#"<staves>\s*(\d+)\s*</staves>"#).flatMap(Int.init) ?? 1, 1)
        // Staves grouped into systems: a piano part has two to a line.
        var systems: [Staff] = []
        var index = 0
        while index + perSystem <= found.count {
            let group = found[index..<index + perSystem]
            if group.allSatisfy({ $0.page == group.first!.page }) {
                systems.append(Staff(page: group.first!.page, rect: group.map(\.rect).reduce(group.first!.rect) { $0.union($1) }))
                index += perSystem
            } else {
                index += 1
            }
        }

        var lines: [[(id: String?, width: CGFloat?)]] = []
        let pattern = try! NSRegularExpression(pattern: #"<measure\b([^>]*)>([\s\S]*?)</measure>"#)
        for match in pattern.matches(in: part, range: NSRange(part.startIndex..., in: part)) {
            guard let attributesRange = Range(match.range(at: 1), in: part), let bodyRange = Range(match.range(at: 2), in: part) else { continue }
            let attributes = String(part[attributesRange])
            let body = String(part[bodyRange])
            let head = body.range(of: "<note").map { String(body[..<$0.lowerBound]) } ?? body
            let breaks = head.contains(#"new-system="yes""#) || head.contains(#"new-page="yes""#)
            if lines.isEmpty || breaks { lines.append([]) }
            lines[lines.count - 1].append((attributes.firstMatch(#"\bid="([^"]+)""#),
                                           attributes.firstMatch(#"\bwidth="([\d.]+)""#).flatMap(Double.init).map { CGFloat($0) }))
        }

        // Only when every line Audiveris read has its staff: otherwise it missed or
        // joined lines, and a bar would be shown in the wrong place.
        guard lines.count == systems.count else { return [:] }
        var places: [String: Place] = [:]
        for (line, staff) in zip(lines, systems) {
            let known = line.compactMap(\.width)
            let usual = known.isEmpty ? 1 : known.reduce(0, +) / CGFloat(known.count)
            let widths = line.map { $0.width ?? usual }
            let total = widths.reduce(0, +)
            guard total > 0 else { continue }
            var x = staff.rect.minX
            for (bar, width) in zip(line, widths) {
                let share = width / total * staff.rect.width
                if let id = bar.id {
                    places[id] = Place(page: staff.page,
                                       bar: CGRect(x: x, y: staff.rect.minY, width: share, height: staff.rect.height),
                                       line: staff.rect)
                }
                x += share
            }
        }
        return places
    }

    /// The staves on every page of a PDF, top to bottom: five dark rows, evenly spaced,
    /// across the middle of the page. Only the middle is measured, so a scan that is a
    /// little crooked still shows straight lines there.
    static func staves(in document: PDFDocument) -> [Staff] {
        (0..<document.pageCount).flatMap { index -> [Staff] in
            guard let page = document.page(at: index) else { return [] }
            return staves(on: page).map { Staff(page: index, rect: $0) }
        }
    }

    static func staves(on page: PDFPage) -> [CGRect] {
        let box = page.bounds(for: .mediaBox)
        let width = 1400, height = Int((CGFloat(width) * box.height / max(box.width, 1)).rounded())
        guard height > 0, let cg = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                              space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let data = cg.data else { return [] }
        cg.setFillColor(gray: 1, alpha: 1)
        cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
        cg.scaleBy(x: CGFloat(width) / box.width, y: CGFloat(height) / box.height)
        cg.translateBy(x: -box.minX, y: -box.minY)
        page.draw(with: .mediaBox, to: cg)
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height)
        // Ink is darker than the page by a margin: a grey scan has a grey page and grey
        // lines. Row 0 of the memory is the top of the page.
        var sum = 0
        for y in stride(from: 0, to: height, by: 7) { for x in stride(from: 0, to: width, by: 7) { sum += Int(pixels[y * width + x]) } }
        let samples = ((height + 6) / 7) * ((width + 6) / 7)
        let ink = UInt8(clamping: min(200, sum / max(samples, 1) - 40))
        func dark(_ x: Int, _ y: Int) -> Bool { pixels[y * width + x] < ink }

        // A scan can lean a little: find the tilt that lines the dark pixels of the middle
        // of the page up into the sharpest rows, then count rows along it.
        let band = (width * 3 / 10)..<(width * 7 / 10)
        let centre = width / 2
        var inked: [(x: Int, y: Int)] = []
        for y in 0..<height { for x in band where dark(x, y) { inked.append((x, y)) } }
        func profile(_ slope: Double) -> [Int] {
            var rows = [Int](repeating: 0, count: height)
            for point in inked {
                let y = point.y + Int((Double(point.x - centre) * slope).rounded())
                if y >= 0 && y < height { rows[y] += 1 }
            }
            return rows
        }
        var slope = 0.0, best = -1
        for step in -15...15 {
            let candidate = tan(Double(step) / 10 * .pi / 180)
            let score = profile(candidate).reduce(0) { $0 + $1 * $1 }
            if score > best { best = score; slope = candidate }
        }
        let counts = profile(slope)
        var rows: [Int] = []
        for y in 0..<height where counts[y] * 20 >= band.count * 9 { rows.append(y) }
        // Neighbouring dark rows are one line.
        var lines: [CGFloat] = []
        var run: [Int] = []
        for y in rows {
            if let last = run.last, y > last + 1 {
                lines.append(CGFloat(run.reduce(0, +)) / CGFloat(run.count)); run = []
            }
            run.append(y)
        }
        if !run.isEmpty { lines.append(CGFloat(run.reduce(0, +)) / CGFloat(run.count)) }
        /// The row a line through `y` at the centre is on at `x`.
        func row(_ y: Int, at x: Int) -> Int { y - Int((Double(x - centre) * slope).rounded()) }

        var found: [CGRect] = []
        var i = 0
        /// Five evenly spaced lines from line `i`, and the index after the last. A scan
        /// spaces them a little unevenly; a stray dark row between them (a long beam)
        /// is stepped over.
        func staff(from i: Int) -> (five: [CGFloat], next: Int)? {
            if i + 4 < lines.count {
                let five = Array(lines[i...i + 4])
                let gaps = zip(five.dropFirst(), five).map { $0 - $1 }
                let mean = gaps.reduce(0, +) / 4
                if mean > 3, mean < CGFloat(height) / 12, gaps.allSatisfy({ abs($0 - mean) <= max(2.5, mean * 0.3) }) {
                    return (five, i + 5)
                }
            }
            for j in (i + 1)..<min(i + 4, lines.count) {
                let gap = lines[j] - lines[i]
                guard gap > 3, gap < CGFloat(height) / 12 else { continue }
                var five = [lines[i], lines[j]], last = j
                for _ in 2...4 {
                    let expected = lines[last] + gap
                    guard let hit = lines.indices.dropFirst(last + 1).prefix(3).first(where: { abs(lines[$0] - expected) <= max(2.5, gap * 0.25) }) else { break }
                    five.append(lines[hit]); last = hit
                }
                if five.count == 5 { return (five, last + 1) }
            }
            return nil
        }
        while i + 4 < lines.count {
            if let (five, next) = staff(from: i) {
                let mean = (five[4] - five[0]) / 4
                // The staff's ends: out from the centre while at least three of its five
                // lines are there (a faded scan breaks single lines), until they stop for
                // more than two staff spaces.
                let gap = Int(mean.rounded())
                let rows = five.map { Int($0.rounded()) }
                func staffAt(_ x: Int) -> Bool {
                    rows.filter { line in
                        let y = row(line, at: x)
                        return (y - 1...y + 1).contains { $0 >= 0 && $0 < height && dark(x, $0) }
                    }.count >= 3
                }
                func reach(_ step: Int) -> Int {
                    var x = width / 2, missing = 0, edge = x
                    while x > 0 && x < width - 1 {
                        x += step
                        if staffAt(x) {
                            missing = 0; edge = x
                        } else {
                            missing += 1
                            if missing > 2 * gap { break }
                        }
                    }
                    return edge
                }
                let left = reach(-1), right = reach(1)
                found.append(CGRect(x: CGFloat(left) / CGFloat(width), y: five[0] / CGFloat(height),
                                    width: CGFloat(right - left) / CGFloat(width), height: (five[4] - five[0]) / CGFloat(height)))
                i = next
            } else {
                i += 1
            }
        }
        return found
    }

    private static func number(_ element: String, in xml: String) -> CGFloat? {
        xml.firstMatch("<\(element)>\\s*([-\\d.]+)\\s*</\(element)>").flatMap(Double.init).map { CGFloat($0) }
    }

    /// The line of music a bar is on, cut from its PDF page, with the bar outlined
    /// when `mark` is true. `scale` is pixels per PDF point.
    static func picture(of place: Place, in document: PDFDocument, mark: Bool, scale: CGFloat = 2) -> NSImage? {
        guard let page = document.page(at: place.page) else { return nil }
        let box = page.bounds(for: .mediaBox)
        // A staff's height of air above and below, for stems, slurs and markings.
        let air = place.line.height * 1.1
        // Close enough to read: the bar with some of its neighbours, or the start of
        // the line (clef, key and time) when no bar is marked.
        let left = mark ? max(place.bar.minX - place.bar.width * 0.8, place.line.minX - 0.02) : place.line.minX - 0.02
        let right = mark ? min(place.bar.maxX + place.bar.width * 0.8, place.line.maxX + 0.02) : place.line.minX + place.line.width * 0.4
        let crop = CGRect(x: max(left, 0), y: max(place.line.minY - air, 0),
                          width: min(right, 1) - max(left, 0), height: place.line.height + 2 * air)
        let size = CGSize(width: crop.width * box.width * scale, height: crop.height * box.height * scale)
        guard size.width >= 1, size.height >= 1 else { return nil }
        let image = NSImage(size: CGSize(width: size.width / scale, height: size.height / scale))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        let cg = context.cgContext
        cg.setFillColor(.white)
        cg.fill(CGRect(origin: .zero, size: size))
        cg.saveGState()
        cg.scaleBy(x: scale, y: scale)
        // PDF space runs up from the page's foot; the crop is measured down from its top.
        cg.translateBy(x: -(box.minX + crop.minX * box.width), y: -(box.minY + (1 - crop.maxY) * box.height))
        page.draw(with: .mediaBox, to: cg)
        cg.restoreGState()
        if mark {
            let bar = CGRect(x: (place.bar.minX - crop.minX) * box.width * scale,
                             y: (crop.maxY - place.bar.maxY) * box.height * scale,
                             width: place.bar.width * box.width * scale, height: place.bar.height * box.height * scale)
            cg.setStrokeColor(CGColor(red: 0.88, green: 0.47, blue: 0.1, alpha: 1))
            cg.setLineWidth(3 * scale / 2)
            cg.stroke(bar.insetBy(dx: -4 * scale, dy: -air * box.height * scale * 0.6), width: 3 * scale / 2)
        }
        image.addRepresentation(rep)
        return image
    }
}
