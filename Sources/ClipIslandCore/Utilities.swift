import AppKit
import Foundation

/// System Reduce Motion setting — gates every decorative animation.
public var reduceMotion: Bool {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
}

public func log(_ message: String) {
    FileHandle.standardError.write(Data("[ClipIsland] \(message)\n".utf8))
}

public extension String {
    /// Truncated single-line preview for list rows.
    func previewLine(limit: Int = 160) -> String {
        let oneLine = replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard oneLine.count > limit else { return oneLine }
        return String(oneLine.prefix(limit)) + "…"
    }
}

public enum TimeFormat {
    /// Compact relative time like "刚刚" / "5 分钟前" / "昨天 14:03" / "10-12 09:30".
    public static func relative(_ date: Date, now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3600 {
            return "\(Int(interval / 60)) 分钟前"
        }
        if interval < 86_400, Calendar.current.isDateInToday(date) {
            return "\(Int(interval / 3600)) 小时前"
        }
        let cal = Calendar.current
        if cal.isDateInYesterday(date) {
            let hm = DateFormatter()
            hm.dateFormat = "HH:mm"
            return "昨天 " + hm.string(from: date)
        }
        let df = DateFormatter()
        if cal.isDate(date, equalTo: now, toGranularity: .year) {
            df.dateFormat = "MM-dd HH:mm"
        } else {
            df.dateFormat = "yyyy-MM-dd"
        }
        return df.string(from: date)
    }
}
