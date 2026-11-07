import SwiftUI

enum JournalTheme {
    static let paper = adaptive(0xF9F8F4, 0x141414)
    static let surface = adaptive(0xFFFFFF, 0x202020)
    static let ink = adaptive(0x21221F, 0xF2F0EB)
    static let secondary = adaptive(0x73756E, 0xAAA9A2)
    static let line = adaptive(0xE6E6DE, 0x343530)
    static let soft = adaptive(0xEDECE5, 0x252622)
    static let accent = adaptive(0xB14735, 0xF59680)
    static let record = Color(red: 0.68, green: 0.28, blue: 0.21)
    static let headline = Font.custom("Songti SC", size: 29, relativeTo: .title)

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
}
