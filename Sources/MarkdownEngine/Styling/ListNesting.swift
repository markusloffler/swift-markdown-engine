//
//  ListNesting.swift
//  MarkdownEngine
//
//  Source-level list nesting. The block pass groups list-item LINES only, so
//  an item's continuation paragraphs (indented text after a blank line) and
//  lazy continuation lines (text right below an item) arrive as top-level
//  paragraphs, and a nested list resumed after such a paragraph arrives as a
//  new top-level list. This recovers which item a line belongs to by scanning
//  the source upward, CommonMark-style: a line nests under the nearest earlier
//  item whose content column it reaches. Leniently, an item that merely sits
//  further left (`1. a` then `  - b`) still counts when no stricter match
//  exists, which matches what the old `spaces / 2` depth produced.
//

import Foundation

enum ListNesting {

    /// A list-item line: where its marker starts and where its content starts.
    struct ItemLine: Equatable {
        let range: NSRange
        let markerIndent: Int
        let contentColumn: Int
    }

    /// Upward scan budget per lookup.
    static let scanLimit = 400

    private enum LineKind {
        case blank
        case text(indent: Int)
        case item(ItemLine)
    }

    /// Item-line view of a parsed `ListItem`.
    static func itemLine(_ item: ListItem) -> ItemLine {
        let afterMarker = NSMaxRange(item.marker)
        let gap = item.contentRange.location > afterMarker ? 1 : 0
        return ItemLine(range: item.range, markerIndent: item.indent,
                        contentColumn: afterMarker - item.range.location + gap)
    }

    /// The item an item nests under; nil at top level or when the scan
    /// budget runs out.
    static func parent(of item: ItemLine, in ns: NSString) -> ItemLine? {
        guard item.markerIndent > 0 else { return nil }
        return parent(above: item.range.location, column: item.markerIndent, in: ns)
    }

    /// The item a non-item line continues: the item right above it (a lazy
    /// continuation), or the item whose content its indentation reaches.
    static func owner(ofLineAt lineRange: NSRange, in ns: NSString) -> ItemLine? {
        guard lineRange.location > 0 else { return nil }
        let previous = ns.lineRange(for: NSRange(location: lineRange.location - 1, length: 0))
        if case .item(let item) = classify(previous, ns) { return item }
        guard case .text(let indent) = classify(lineRange, ns), indent > 0 else { return nil }
        return parent(above: lineRange.location, column: indent, in: ns)
    }

    /// Nearest item above `location` that a line indented `column` nests under.
    private static func parent(above location: Int, column: Int, in ns: NSString) -> ItemLine? {
        var fallback: ItemLine?
        var cursor = location
        var scanned = 0
        while cursor > 0 {
            guard scanned < scanLimit else { return fallback }
            let line = ns.lineRange(for: NSRange(location: cursor - 1, length: 0))
            cursor = line.location
            scanned += 1
            switch classify(line, ns) {
            case .blank:
                continue
            case .text(let indent):
                // Unindented prose ends every list above it.
                if indent == 0 { return fallback }
            case .item(let item):
                if item.markerIndent < column {
                    if item.contentColumn <= column { return item }
                    if fallback == nil { fallback = item }
                }
                // Nothing above a top-level item can still be open.
                if item.markerIndent == 0 { return fallback }
            }
        }
        return fallback
    }

    private static func classify(_ line: NSRange, _ ns: NSString) -> LineKind {
        let end = NSMaxRange(line)
        var i = line.location
        while i < end, isIndent(ns.character(at: i)) { i += 1 }
        let indent = i - line.location
        guard i < end, !isLineBreak(ns.character(at: i)) else { return .blank }
        let markerStart = i
        let c = ns.character(at: i)
        if c == 0x2D || c == 0x2A || c == 0x2B {                // - * +
            i += 1
        } else {                                                // N. / N)
            var digits = 0
            while i < end, digits < 9, (0x30...0x39).contains(ns.character(at: i)) { i += 1; digits += 1 }
            guard digits > 0, i < end, ns.character(at: i) == 0x2E || ns.character(at: i) == 0x29 else {
                return .text(indent: indent)
            }
            i += 1
        }
        guard i > markerStart, i < end, isIndent(ns.character(at: i)) else { return .text(indent: indent) }
        return .item(ItemLine(range: line, markerIndent: indent, contentColumn: i + 1 - line.location))
    }

    private static func isIndent(_ c: unichar) -> Bool { c == 0x20 || c == 0x09 }
    private static func isLineBreak(_ c: unichar) -> Bool { c == 0x0A || c == 0x0D }
}
