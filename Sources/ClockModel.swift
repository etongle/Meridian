import Foundation

struct ClockRegion: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var customName: String?

    static let local = ClockRegion(id: "system")
    var followsSystem: Bool { id == "system" }

    func timeZone(local: TimeZone) -> TimeZone {
        followsSystem ? local : (TimeZone(identifier: id) ?? local)
    }

    func name(local: TimeZone, language: AppLanguage = .english) -> String {
        if let customName, !customName.trimmingCharacters(in: .whitespaces).isEmpty {
            return customName
        }
        return CityCatalog.name(for: timeZone(local: local).identifier, language: language)
    }
}

enum CityCatalog {
    static let names: [String: String] = [
        "America/New_York": "纽约", "America/Detroit": "底特律",
        "America/Chicago": "芝加哥", "America/Denver": "丹佛",
        "America/Los_Angeles": "洛杉矶", "America/Phoenix": "凤凰城",
        "America/Anchorage": "安克雷奇", "Pacific/Honolulu": "檀香山",
        "America/Toronto": "多伦多", "America/Vancouver": "温哥华",
        "America/Mexico_City": "墨西哥城", "America/Sao_Paulo": "圣保罗",
        "America/Argentina/Buenos_Aires": "布宜诺斯艾利斯",
        "America/Bogota": "波哥大", "America/Lima": "利马",
        "Europe/London": "伦敦", "Europe/Paris": "巴黎",
        "Europe/Berlin": "柏林", "Europe/Amsterdam": "阿姆斯特丹",
        "Europe/Zurich": "苏黎世", "Europe/Rome": "罗马",
        "Europe/Madrid": "马德里", "Europe/Stockholm": "斯德哥尔摩",
        "Europe/Helsinki": "赫尔辛基", "Europe/Moscow": "莫斯科",
        "Europe/Istanbul": "伊斯坦布尔", "Asia/Shanghai": "上海",
        "Asia/Hong_Kong": "香港", "Asia/Taipei": "台北",
        "Asia/Macau": "澳门", "Asia/Tokyo": "东京", "Asia/Seoul": "首尔",
        "Asia/Singapore": "新加坡", "Asia/Kuala_Lumpur": "吉隆坡",
        "Asia/Bangkok": "曼谷", "Asia/Ho_Chi_Minh": "胡志明市",
        "Asia/Jakarta": "雅加达", "Asia/Manila": "马尼拉",
        "Asia/Kolkata": "新德里", "Asia/Calcutta": "新德里",
        "Asia/Kathmandu": "加德满都", "Asia/Katmandu": "加德满都",
        "Asia/Dubai": "迪拜", "Asia/Riyadh": "利雅得",
        "Asia/Jerusalem": "耶路撒冷", "Asia/Tehran": "德黑兰",
        "Asia/Dhaka": "达卡", "Asia/Karachi": "卡拉奇",
        "Australia/Sydney": "悉尼", "Australia/Melbourne": "墨尔本",
        "Australia/Brisbane": "布里斯班", "Australia/Perth": "珀斯",
        "Australia/Adelaide": "阿德莱德", "Australia/Darwin": "达尔文",
        "Australia/Eucla": "尤克拉", "Pacific/Auckland": "奥克兰",
        "Pacific/Fiji": "斐济", "Pacific/Kiritimati": "基里蒂马蒂",
        "Pacific/Pago_Pago": "帕果帕果", "Africa/Cairo": "开罗",
        "Africa/Johannesburg": "约翰内斯堡", "Africa/Nairobi": "内罗毕",
        "Africa/Lagos": "拉各斯", "Africa/Casablanca": "卡萨布兰卡",
        "Etc/UTC": "协调世界时", "GMT": "格林尼治", "UTC": "协调世界时"
    ]
    static let popular = ["America/New_York", "Europe/London", "Asia/Shanghai",
        "Asia/Tokyo", "America/Los_Angeles", "Asia/Singapore", "Europe/Paris",
        "Australia/Sydney", "Asia/Hong_Kong", "Asia/Dubai", "Asia/Kolkata",
        "Pacific/Auckland", "America/Sao_Paulo", "America/Mexico_City",
        "Europe/Berlin", "Africa/Cairo", "Africa/Johannesburg", "Africa/Lagos",
        "Africa/Nairobi", "Asia/Seoul", "Asia/Bangkok", "Pacific/Honolulu",
        "Europe/Moscow", "America/Toronto"]

    static func name(for identifier: String, language: AppLanguage = .english) -> String {
        let canonical = canonicalIdentifier(identifier)
        if language == .simplifiedChinese, let name = names[identifier] { return name }
        if language == .simplifiedChinese {
            if let name = names[canonical] ?? WorldRegionData.zhNames[canonical] { return name }
        }
        if ["Asia/Kolkata", "Asia/Calcutta"].contains(identifier) { return "New Delhi" }
        if ["UTC", "Etc/UTC", "GMT"].contains(identifier) { return "UTC" }
        if let name = WorldRegionData.enNames[canonical] { return name }
        return canonical.split(separator: "/").last.map {
            String($0).replacingOccurrences(of: "_", with: " ")
        } ?? identifier
    }

    static func defaults(local: TimeZone) -> [ClockRegion] {
        var result: [ClockRegion] = [.local]
        for identifier in ["Europe/London", "Asia/Shanghai", "Asia/Tokyo", "America/New_York", "Europe/Paris"] {
            guard result.count < 4, canonicalIdentifier(identifier) != canonicalIdentifier(local.identifier) else { continue }
            result.append(ClockRegion(id: identifier))
        }
        return result
    }

}

struct ClockSnapshot: Equatable, Sendable {
    let city: String
    let language: AppLanguage
    let time: String
    let second: Int
    let date: String
    let weekday: String
    let dayDifference: Int
    let isDaytime: Bool
    let offsetSeconds: Int
    let differenceSeconds: Int
    let isLocal: Bool

    init(region: ClockRegion, instant: Date, local: TimeZone, language: AppLanguage = .english) {
        self.language = language
        let zone = region.timeZone(local: local)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: instant)
        city = region.name(local: local, language: language)
        time = String(format: "%02d:%02d", components.hour!, components.minute!)
        second = components.second!
        date = String(format: "%04d/%02d/%02d", components.year!, components.month!, components.day!)
        weekday = (language == .english ? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"] : ["周日", "周一", "周二", "周三", "周四", "周五", "周六"])[components.weekday! - 1]
        isDaytime = (6..<18).contains(components.hour!)
        offsetSeconds = zone.secondsFromGMT(for: instant)
        differenceSeconds = offsetSeconds - local.secondsFromGMT(for: instant)
        isLocal = region.followsSystem

        // Compare calendar dates, not elapsed hours: DST days can have 23 or 25 hours.
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = local
        let localDate = localCalendar.dateComponents([.year, .month, .day], from: instant)
        var civilCalendar = Calendar(identifier: .gregorian)
        civilCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let targetDay = civilCalendar.date(from: DateComponents(year: components.year, month: components.month, day: components.day))!
        let originDay = civilCalendar.date(from: localDate)!
        dayDifference = civilCalendar.dateComponents([.day], from: originDay, to: targetDay).day!
    }

    var secondLabel: String { String(format: "%02d", second) }
    var timeWithSeconds: String { "\(time):\(secondLabel)" }

    var dayLabel: String? {
        switch dayDifference {
        case 0: return nil
        case 1: return language == .english ? "Next day" : "次日"
        case -1: return language == .english ? "Prev day" : "前日"
        default: return language == .english ? String(format: "%+d days", dayDifference) : (dayDifference > 0 ? "+\(dayDifference) 天" : "\(dayDifference) 天")
        }
    }

    var offsetLabel: String {
        if offsetSeconds == 0 { return "UTC" }
        let minutes = abs(offsetSeconds) / 60
        let suffix = minutes % 60 == 0 ? "\(minutes / 60)" : String(format: "%d:%02d", minutes / 60, minutes % 60)
        return "UTC\(offsetSeconds >= 0 ? "+" : "−")\(suffix)"
    }

    var differenceLabel: String {
        guard !isLocal else { return offsetLabel }
        if differenceSeconds == 0 { return language == .english ? "Same as local" : "与本地同一时间" }
        let minutes = abs(differenceSeconds) / 60
        let hours = minutes / 60
        let remainder = minutes % 60
        if language == .english {
            let amount = hours == 0 ? "\(remainder)m" : remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
            return "\(differenceSeconds > 0 ? "+" : "−")\(amount)"
        }
        let amount = hours == 0 ? "\(remainder) 分钟" : remainder == 0 ? "\(hours) 小时" : "\(hours) 小时 \(remainder) 分钟"
        return "\(differenceSeconds > 0 ? "快" : "慢") \(amount)"
    }
}
