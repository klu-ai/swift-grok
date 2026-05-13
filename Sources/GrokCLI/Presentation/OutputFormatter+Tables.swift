import Foundation

extension OutputFormatter {
    enum TableAlignment {
        case left
        case right
        case center
    }

    func parseTableRow(_ line: String) -> [String]? {
        var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("|") else {
            return nil
        }
        if trimmed.first == "|" {
            trimmed.removeFirst()
        }
        if trimmed.last == "|" {
            trimmed.removeLast()
        }
        return trimmed
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    func parseTableSeparator(_ line: String) -> [TableAlignment]? {
        guard let cells = parseTableRow(line), !cells.isEmpty else {
            return nil
        }
        var alignments: [TableAlignment] = []
        for cell in cells {
            let normalized = cell.replacingOccurrences(of: " ", with: "")
            let dashCount = normalized.filter { $0 == "-" }.count
            guard dashCount >= 1,
                  normalized.allSatisfy({ $0 == "-" || $0 == ":" }) else {
                return nil
            }
            if normalized.hasPrefix(":"), normalized.hasSuffix(":") {
                alignments.append(.center)
            } else if normalized.hasSuffix(":") {
                alignments.append(.right)
            } else {
                alignments.append(.left)
            }
        }
        return alignments
    }

    func normalizedTableRow<T>(_ row: [T], count: Int, defaultValue: T) -> [T] {
        guard row.count < count else {
            return Array(row.prefix(count))
        }
        return row + Array(repeating: defaultValue, count: count - row.count)
    }

    func normalizedTableRow(_ row: [String], count: Int) -> [String] {
        normalizedTableRow(row, count: count, defaultValue: "")
    }

    func tableColumnWidths(rows: [[String]], columnCount: Int) -> [Int] {
        (0..<columnCount).map { column in
            rows.map { row in
                visibleLength(row[column])
            }.max() ?? 0
        }
    }

    func renderTableRow(_ row: [String], widths: [Int], alignments: [TableAlignment]) -> String {
        let cells = row.enumerated().map { index, cell in
            " " + padded(cell, width: widths[index], alignment: alignments[index]) + " "
        }
        return "|" + cells.joined(separator: "|") + "|"
    }

    func renderTableSeparator(widths: [Int], alignments: [TableAlignment]) -> String {
        let cells = widths.enumerated().map { index, width in
            let dashes = String(repeating: "-", count: max(width, 3) + 2)
            switch alignments[index] {
            case .left:
                return dashes
            case .right:
                return String(dashes.dropLast()) + ":"
            case .center:
                return ":" + String(dashes.dropFirst().dropLast()) + ":"
            }
        }
        return "|" + cells.joined(separator: "|") + "|"
    }

    func padded(_ value: String, width: Int, alignment: TableAlignment) -> String {
        let missing = max(0, width - visibleLength(value))
        switch alignment {
        case .left:
            return value + String(repeating: " ", count: missing)
        case .right:
            return String(repeating: " ", count: missing) + value
        case .center:
            let left = missing / 2
            let right = missing - left
            return String(repeating: " ", count: left) + value + String(repeating: " ", count: right)
        }
    }

    func visibleLength(_ value: String) -> Int {
        stripANSI(value).count
    }

    func stripANSI(_ value: String) -> String {
        let escape = "\u{001B}"
        return value.replacingOccurrences(
            of: "\(escape)\\[[0-9;]*m",
            with: "",
            options: .regularExpression
        )
    }
}
