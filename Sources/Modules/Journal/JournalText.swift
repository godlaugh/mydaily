import Foundation
import XLang

/// Uses the same in-app language bundle as the rest of ALog.
enum JournalText {
    static func string(_ key: String) -> String {
        NSLocalizedString(key, tableName: "Journal", bundle: Bundle.current, comment: "")
    }
}

extension MemoEntity {
    var journalTitle: String {
        if isHidden { return JournalText.string("hidden") }
        let text = viewContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return JournalText.string(file == nil ? "untitled" : "audio_note") }
        return JournalContentText(text).title
    }

    var journalPreview: String {
        if isHidden { return JournalText.string("hidden") }
        return viewContent.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var journalExcerpt: String {
        guard !isHidden else { return "" }
        return JournalContentText(journalPreview).remainder
    }

    var journalDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        if let timezone { formatter.timeZone = TimeZone(identifier: timezone) }
        return formatter.string(from: createdAt ?? .distantPast)
    }

    var journalDuration: String { Self.durationLabel(duration) }

    static func durationLabel(_ duration: Double) -> String {
        let seconds = duration.isFinite ? max(0, Int(duration)) : 0
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
