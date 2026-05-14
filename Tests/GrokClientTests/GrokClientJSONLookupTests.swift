import XCTest
@testable import GrokClient

final class GrokClientJSONLookupTests: XCTestCase {
    func testDirectScalarLookupDoesNotRecurse() {
        let lookup = JSONLookup([
            "wrapper": [
                "target": "nested",
                "count": "7",
                "enabled": "true"
            ]
        ])

        XCTAssertNil(lookup.string("target"))
        XCTAssertNil(lookup.int("count"))
        XCTAssertNil(lookup.bool("enabled"))
    }

    func testRecursiveScalarLookupFindsNestedValues() {
        let lookup = JSONLookup([
            "wrapper": [
                "items": [
                    [
                        "target": "nested",
                        "count": "7",
                        "enabled": "true"
                    ]
                ]
            ]
        ])

        XCTAssertEqual(lookup.firstString("target"), "nested")
        XCTAssertEqual(lookup.firstInt("count"), 7)
        XCTAssertEqual(lookup.firstBool("enabled"), true)
    }

    func testAnyCodableNormalizesNestedAnyContainers() throws {
        let lookup = JSONLookup([
            "outer": [
                "array": [
                    ["name": "first"],
                    AnyCodable(["name": "second", "flags": [true, false]])
                ],
                "null": NSNull()
            ] as [String: Any]
        ])

        let raw = try XCTUnwrap(lookup.rawAnyCodable.value as? [String: AnyCodable])
        let outer = try XCTUnwrap(raw["outer"]?.value as? [String: AnyCodable])
        let array = try XCTUnwrap(outer["array"]?.value as? [AnyCodable])
        let first = try XCTUnwrap(array[0].value as? [String: AnyCodable])
        let second = try XCTUnwrap(array[1].value as? [String: AnyCodable])
        let flags = try XCTUnwrap(second["flags"]?.value as? [AnyCodable])

        XCTAssertEqual(first["name"]?.value as? String, "first")
        XCTAssertEqual(second["name"]?.value as? String, "second")
        XCTAssertEqual(flags.map { $0.value as? Bool }, [true, false])
        XCTAssertTrue(outer["null"]?.value is NSNull)
    }

    func testAllDictionariesTraversesWrappersAndArrays() {
        let lookup = JSONLookup([
            "envelope": [
                "result": [
                    "items": [
                        ["id": "one"],
                        ["id": "two"]
                    ]
                ]
            ]
        ])

        XCTAssertTrue(lookup.dictionaries("items").isEmpty)

        let recursive = lookup.allDictionaries("items")
        XCTAssertEqual(recursive.count, 2)
        XCTAssertEqual(recursive[0]["id"]?.value as? String, "one")
        XCTAssertEqual(recursive[1]["id"]?.value as? String, "two")
    }
}
