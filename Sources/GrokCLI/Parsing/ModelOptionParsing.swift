import Foundation
import GrokClient

private extension String {
    func removingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else {
            return nil
        }
        return String(dropFirst(prefix.count))
    }
}

extension GrokCLI {
    static func applyModelOption(_ arg: String, nextValue: String?) -> (mode: GrokMode?, consumedNext: Bool, missingValue: Bool) {
        if arg == "--model" || arg == "--mode" {
            guard let nextValue,
                  !nextValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !nextValue.hasPrefix("--") else {
                return (nil, false, true)
            }
            return (GrokMode.resolve(nextValue), true, false)
        }

        if let value = arg.removingPrefix("--model=") ?? arg.removingPrefix("--mode=") {
            return (GrokMode.resolve(value), false, value.isEmpty)
        }

        return (nil, false, false)
    }

    static func applyOutputFormatOption(_ arg: String, nextValue: String?) -> (format: OutputFormat?, consumedNext: Bool, missingValue: Bool, invalidValue: String?) {
        if arg == "--json" {
            return (.json, false, false, nil)
        }

        if arg == "--raw" {
            return (.raw, false, false, nil)
        }

        if arg == "--markdown" || arg == "-m" {
            return (.markdown, false, false, nil)
        }

        if arg == "--format" {
            guard let nextValue, !nextValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return (nil, false, true, nil)
            }
            guard let format = OutputFormat.resolve(nextValue) else {
                return (nil, false, false, nextValue)
            }
            return (format, true, false, nil)
        }

        if let value = arg.removingPrefix("--format=") {
            guard !value.isEmpty else {
                return (nil, false, true, nil)
            }
            guard let format = OutputFormat.resolve(value) else {
                return (nil, false, false, value)
            }
            return (format, false, false, nil)
        }

        return (nil, false, false, nil)
    }

}
