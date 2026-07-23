import Foundation

struct UsageRow {
    let title: String
    let remainingPercent: Int
    let windowDurationMinutes: Int
    let resetsAt: Date?

    var isWeekly: Bool { windowDurationMinutes >= 6 * 24 * 60 }

    var resetText: String {
        guard let resetsAt else { return "重置时间未知" }
        let remaining = max(0, Int(resetsAt.timeIntervalSinceNow))
        let days = remaining / 86_400
        let hours = (remaining % 86_400) / 3_600
        let minutes = (remaining % 3_600) / 60
        if days > 0 { return "约 \(days)天后重置" }
        if hours > 0 { return "约 \(hours)小时后重置" }
        return "约 \(max(1, minutes))分钟后重置"
    }
}

struct UsageSnapshot {
    let rows: [UsageRow]
    let updatedAt: Date

    var weekly: UsageRow? { rows.first(where: { $0.isWeekly }) }
    var session: UsageRow? { rows.first(where: { !$0.isWeekly }) }
    var summaryRemainingPercent: Int? { weekly?.remainingPercent ?? rows.first?.remainingPercent }
}

enum UsageParser {
    static func parse(json: [String: Any]) -> UsageSnapshot? {
        let payload: [String: Any]
        if let result = json["result"] as? [String: Any] {
            payload = result
        } else if let params = json["params"] as? [String: Any] {
            payload = params
        } else {
            payload = json
        }

        var snapshots: [[String: Any]] = []
        if let byLimitID = payload["rateLimitsByLimitId"] as? [String: Any] {
            snapshots = byLimitID.compactMap { key, value in
                guard var snapshot = value as? [String: Any] else { return nil }
                if snapshot["limitId"] == nil { snapshot["limitId"] = key }
                return snapshot
            }
        }
        if snapshots.isEmpty, let rateLimits = payload["rateLimits"] as? [String: Any] {
            snapshots = [rateLimits]
        }

        let rows = snapshots
            .flatMap(makeRows)
            .sorted {
                if $0.isWeekly != $1.isWeekly { return !$0.isWeekly }
                return $0.windowDurationMinutes < $1.windowDurationMinutes
            }
        guard !rows.isEmpty else { return nil }
        return UsageSnapshot(rows: rows, updatedAt: Date())
    }

    private static func makeRows(from snapshot: [String: Any]) -> [UsageRow] {
        ["primary", "secondary"].compactMap { key in
            guard let window = snapshot[key] as? [String: Any],
                  let usedPercent = integer(window["usedPercent"]),
                  let duration = integer(window["windowDurationMins"])
            else { return nil }

            let remaining = min(100, max(0, 100 - usedPercent))
            let resetDate = integer(window["resetsAt"]).map {
                Date(timeIntervalSince1970: TimeInterval($0))
            }
            let title = duration >= 6 * 24 * 60
                ? "周额度"
                : (duration % 60 == 0 ? "(duration / 60)小时额度" : "(duration)分钟额度")
            return UsageRow(
                title: title,
                remainingPercent: remaining,
                windowDurationMinutes: duration,
                resetsAt: resetDate
            )
        }
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }
}
