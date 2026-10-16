import Foundation
import JavaScriptCore

enum InterpreterError: LocalizedError {
    case missing(String)
    case engine
    case script(String)

    var errorDescription: String? {
        switch self {
        case .missing(let what): return "The dashboard's app.js no longer contains \(what)."
        case .engine: return "JavaScript engine unavailable."
        case .script(let message): return "Interpretation code failed to load: \(message)"
        }
    }
}

private final class ErrorBox { var message: String? }

/// Runs the dashboard's OWN presentation logic, extracted at runtime from the live /app.js:
/// the `market-interpretation-v1` block (five overview cards and overall reading) and `warningLanguage`
/// (plain-English downturn names). Nothing is re-implemented in Swift, so the TV cannot drift from Safari.
@MainActor
final class Interpreter {
    private var context: JSContext?
    private let errors = ErrorBox()
    private(set) var loadedCommit: String?
    private(set) var lastError: String?
    private(set) var hasWarningLanguage = false

    var isReady: Bool { context != nil }

    func load(appJS: String, commit: String?) throws {
        func constLine(_ name: String) throws -> String {
            guard let r = appJS.range(of: "const \(name) = ") ?? appJS.range(of: "const \(name)=") else {
                throw InterpreterError.missing("the `\(name)` helper")
            }
            let end = appJS[r.lowerBound...].firstIndex(of: "\n") ?? appJS.endIndex
            return String(appJS[r.lowerBound..<end])
        }
        guard let begin = appJS.range(of: "// BEGIN market-interpretation-v1"),
              let end = appJS.range(of: "// END market-interpretation-v1", range: begin.upperBound..<appJS.endIndex) else {
            throw InterpreterError.missing("the market-interpretation-v1 block")
        }
        var source = "'use strict';\n"
        source += try constLine("fmt") + "\n"
        source += try constLine("signed") + "\n"
        source += try constLine("pct") + "\n"
        source += String(appJS[begin.lowerBound..<end.upperBound]) + "\n"

        hasWarningLanguage = false
        // The function ends at the next top-level function or marked block, whichever comes first.
        if let w = appJS.range(of: "function warningLanguage("),
           let next = [appJS.range(of: "\nfunction ", range: w.upperBound..<appJS.endIndex),
                       appJS.range(of: "\n// BEGIN ", range: w.upperBound..<appJS.endIndex)].compactMap({ $0 }).min(by: { $0.lowerBound < $1.lowerBound }) {
            source += String(appJS[w.lowerBound..<next.lowerBound]) + "\n"
            hasWarningLanguage = true
        }
        source += """
        function __interpret(s){const o=JSON.parse(s);return JSON.stringify(interpretRecord(o.snapshot||o));}
        function __warning(s){return typeof warningLanguage==='function'?JSON.stringify(warningLanguage(JSON.parse(s))):'null';}
        """

        guard let ctx = JSContext() else { throw InterpreterError.engine }
        let box = errors
        box.message = nil
        ctx.exceptionHandler = { _, value in box.message = value?.toString() ?? "unknown error" }
        ctx.evaluateScript(source)
        if let message = box.message { throw InterpreterError.script(message) }
        context = ctx
        loadedCommit = commit
    }

    /// `text` is the record as JSON: the /api/latest body or just its snapshot.
    func interpret(_ text: String) -> J? {
        guard let ctx = context else { return nil }
        errors.message = nil
        let result = ctx.objectForKeyedSubscript("__interpret")?.call(withArguments: [text])
        if let message = errors.message { lastError = message; return nil }
        guard let s = result?.toString(), let d = s.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) else {
            lastError = "No interpretation returned."
            return nil
        }
        lastError = nil
        return J(o)
    }

    func warningLanguage(_ card: J) -> (name: String, meaning: String)? {
        guard let ctx = context, hasWarningLanguage, let json = card.jsonString() else { return nil }
        errors.message = nil
        let result = ctx.objectForKeyedSubscript("__warning")?.call(withArguments: [json])
        guard errors.message == nil, let s = result?.toString(), let d = s.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) else { return nil }
        let j = J(o)
        guard let name = j["name"].string else { return nil }
        return (name, j["meaning"].string ?? "")
    }
}
