import Foundation
import GrokClient

enum CLIOptionParsing {
    static func removeFlag(_ flag: String, from args: inout [String]) -> Bool {
        let originalCount = args.count
        args.removeAll { $0 == flag }
        return args.count != originalCount
    }

    static func removeJSONOutputOptions(from args: inout [String]) throws -> Bool {
        var json = false
        var result: [String] = []
        var index = 0

        while index < args.count {
            let arg = args[index]

            if arg == "--json" {
                json = true
                index += 1
                continue
            }

            if arg == "--format" {
                let valueIndex = index + 1
                guard valueIndex < args.count, !args[valueIndex].hasPrefix("--") else {
                    throw GrokError.apiError("--format requires a value")
                }
                let value = args[valueIndex]
                guard value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "json" else {
                    throw GrokError.apiError("Invalid --format value: \(value). Use json.")
                }
                json = true
                index += 2
                continue
            }

            if arg.hasPrefix("--format=") {
                let value = String(arg.dropFirst("--format=".count))
                guard !value.isEmpty else {
                    throw GrokError.apiError("--format requires a value")
                }
                guard value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "json" else {
                    throw GrokError.apiError("Invalid --format value: \(value). Use json.")
                }
                json = true
                index += 1
                continue
            }

            result.append(arg)
            index += 1
        }

        args = result
        return json
    }

    static func nameAndValue(_ arg: String) -> (name: String, inlineValue: String?) {
        guard let separator = arg.firstIndex(of: "=") else {
            return (arg, nil)
        }
        return (String(arg[..<separator]), String(arg[arg.index(after: separator)...]))
    }

    static func readValue(
        _ inlineValue: String?,
        args: [String],
        index: Int,
        option: String
    ) throws -> (String, Int) {
        if let inlineValue {
            guard !inlineValue.isEmpty else {
                throw GrokError.apiError("\(option) requires a value")
            }
            return (inlineValue, index)
        }

        let nextIndex = index + 1
        guard nextIndex < args.count, !args[nextIndex].hasPrefix("--") else {
            throw GrokError.apiError("\(option) requires a value")
        }
        return (args[nextIndex], nextIndex)
    }
}
