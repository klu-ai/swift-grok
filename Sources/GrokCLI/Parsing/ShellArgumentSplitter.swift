import Foundation
import GrokClient

extension GrokCLI {
    static func splitCommandArguments(_ input: String) throws -> [String] {
        var args: [String] = []
        var current = ""
        var currentStarted = false
        var quote: Character?
        var escaping = false

        for character in input {
            if escaping {
                current.append(character)
                currentStarted = true
                escaping = false
                continue
            }

            if character == "\\" {
                escaping = true
                currentStarted = true
                continue
            }

            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                    currentStarted = true
                }
                continue
            }

            if character == "\"" || character == "'" {
                quote = character
                currentStarted = true
                continue
            }

            if character.isWhitespace {
                if currentStarted {
                    args.append(current)
                    current = ""
                    currentStarted = false
                }
                continue
            }

            current.append(character)
            currentStarted = true
        }

        if escaping {
            current.append("\\")
        }

        if let quote {
            throw GrokError.apiError("Unclosed \(quote) quote in command")
        }

        if currentStarted {
            args.append(current)
        }

        return args
    }

}
