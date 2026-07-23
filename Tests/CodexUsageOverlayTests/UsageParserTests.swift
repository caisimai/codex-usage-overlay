import XCTest
@testable import CodexUsageOverlay

final class UsageParserTests: XCTestCase {
    func testParsesPrimaryAndWeeklyWindows() {
        let json: [String: Any] = [
            "id": 2,
            "result": [
                "rateLimits": [
                    "primary": [
                        "usedPercent": 35,
                        "windowDurationMins": 300,
                        "resetsAt": 1_800_000_000
                    ],
                    "secondary": [
                        "usedPercent": 62,
                        "windowDurationMins": 10_080,
                        "resetsAt": 1_800_100_000
                    ]
                ]
            ]
        ]

        let snapshot = UsageParser.parse(json: json)

        XCTAssertEqual(snapshot?.rows.count, 2)
        XCTAssertEqual(snapshot?.session?.remainingPercent, 65)
        XCTAssertEqual(snapshot?.weekly?.remainingPercent, 38)
        XCTAssertEqual(snapshot?.summaryRemainingPercent, 38)
    }

    func testParsesRateLimitsByLimitIDNotification() {
        let json: [String: Any] = [
            "method": "account/rateLimits/updated",
            "params": [
                "rateLimitsByLimitId": [
                    "codex": [
                        "primary": [
                            "usedPercent": 10,
                            "windowDurationMins": 300
                        ]
                    ]
                ]
            ]
        ]

        let snapshot = UsageParser.parse(json: json)

        XCTAssertEqual(snapshot?.rows.count, 1)
        XCTAssertEqual(snapshot?.summaryRemainingPercent, 90)
    }

    func testMergesSparseRateLimitNotification() {
        let initial: [String: Any] = [
            "result": [
                "rateLimits": [
                    "primary": [
                        "usedPercent": 35,
                        "windowDurationMins": 300
                    ],
                    "secondary": [
                        "usedPercent": 62,
                        "windowDurationMins": 10_080
                    ]
                ]
            ]
        ]
        let update: [String: Any] = [
            "method": "account/rateLimits/updated",
            "params": [
                "rateLimits": [
                    "secondary": [
                        "usedPercent": 70,
                        "windowDurationMins": 10_080
                    ]
                ]
            ]
        ]

        let initialSnapshot = UsageParser.parse(json: initial)
        let mergedSnapshot = UsageParser.parse(json: update, mergingWith: initialSnapshot)

        XCTAssertEqual(mergedSnapshot?.session?.remainingPercent, 65)
        XCTAssertEqual(mergedSnapshot?.weekly?.remainingPercent, 30)
    }

    func testIgnoresIncompleteWindow() {
        let json: [String: Any] = [
            "result": [
                "rateLimits": [
                    "primary": [
                        "usedPercent": 50
                    ]
                ]
            ]
        ]

        XCTAssertNil(UsageParser.parse(json: json))
    }
}
