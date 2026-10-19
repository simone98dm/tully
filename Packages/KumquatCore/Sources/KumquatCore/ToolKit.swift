import Foundation

public struct ToolParameter: Sendable, Identifiable {
    public enum Kind: Sendable {
        case slider(min: Double, max: Double, step: Double, unit: String)
        case number(unit: String)
        case text(placeholder: String)
        case choice([String])
    }
    public let id: String
    public let label: String
    public let kind: Kind
    public let defaultValue: String

    public init(_ id: String, _ label: String, _ kind: Kind, default value: String) {
        self.id = id; self.label = label; self.kind = kind; self.defaultValue = value
    }
}

public enum ToolResult: Sendable {
    case files([URL])
    case message(String)
}

/// Editors the app shows instead of the generic parameter form.
public enum ToolEditor: Sendable { case photo(PhotoEditor.Mode), pdfPages }

public typealias ToolParams = [String: String]

public struct Tool: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let symbol: String
    public let categories: Set<FileCategory>
    /// Minimum number of files (2 for join/merge/collage).
    public let minFiles: Int
    public let editor: ToolEditor?
    let parametersFor: @Sendable ([URL]) -> [ToolParameter]
    let action: @Sendable ([URL], ToolParams) throws -> ToolResult

    public func parameters(for urls: [URL]) -> [ToolParameter] { parametersFor(urls) }

    /// Runs with defaults filled in for any missing parameter.
    public func run(_ urls: [URL], params: ToolParams = [:]) throws -> ToolResult {
        var merged = Dictionary(uniqueKeysWithValues: parameters(for: urls).map { ($0.id, $0.defaultValue) })
        merged.merge(params) { _, new in new }
        return try action(urls, merged)
    }

    public func applies(to urls: [URL]) -> Bool {
        guard urls.count >= minFiles else { return false }
        // Empty categories = any file (e.g. Zip).
        return categories.isEmpty || urls.allSatisfy { url in Formats.category(of: url).map(categories.contains) ?? false }
    }

    init(_ id: String, _ name: String, symbol: String, _ categories: Set<FileCategory>, minFiles: Int = 1,
         editor: ToolEditor? = nil, parameters: @escaping @Sendable ([URL]) -> [ToolParameter] = { _ in [] },
         action: @escaping @Sendable ([URL], ToolParams) throws -> ToolResult) {
        self.id = id; self.name = name; self.symbol = symbol; self.categories = categories; self.minFiles = minFiles
        self.editor = editor; self.parametersFor = parameters; self.action = action
    }
}

extension ToolParams {
    func double(_ key: String) throws -> Double {
        guard let raw = self[key], let value = Double(raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) else {
            throw ConversionError("\(key.capitalized) must be a number")
        }
        return value
    }
    func string(_ key: String) -> String { self[key] ?? "" }
}

/// Applies `body` to each file, collecting outputs (batch semantics for single-file tools).
func eachFile(_ urls: [URL], _ body: (URL) throws -> URL) throws -> ToolResult {
    .files(try urls.map(body))
}

/// Parses "1.5-2, 4-5.25" into ranges; accepts mm:ss timestamps.
public func parseRanges(_ text: String) throws -> [ClosedRange<Double>] {
    try text.split(separator: ",").map { part in
        let bounds = part.split(separator: "-").map { String($0).trimmingCharacters(in: .whitespaces) }
        guard bounds.count == 2, let a = Subtitles.time(bounds[0]) ?? Double(bounds[0]),
              let b = Subtitles.time(bounds[1]) ?? Double(bounds[1]), b > a else {
            throw ConversionError("Invalid range \"\(part.trimmingCharacters(in: .whitespaces))\". Use start-end, e.g. 1.5-3")
        }
        return a...b
    }
}

/// Parses a timestamp field: seconds ("12.5") or "mm:ss" / "hh:mm:ss".
public func parseTime(_ text: String) throws -> Double {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard let t = Double(trimmed) ?? Subtitles.time(trimmed), t >= 0 else {
        throw ConversionError("Invalid time \"\(text)\". Use seconds or mm:ss")
    }
    return t
}
