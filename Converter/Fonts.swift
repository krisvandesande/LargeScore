import SwiftUI

/// The Converter's text sizes. The Mac's own text styles are small for someone with
/// low vision (body is 13 pt, title3 15 pt): everything people read here is at least 20 pt.
extension Font {
    static let reading = Font.system(size: 20)
    static let readingBold = Font.system(size: 20, weight: .semibold)
    static let readingHeading = Font.system(size: 24, weight: .semibold)
    static let readingTitle = Font.system(size: 34, weight: .semibold)
}
