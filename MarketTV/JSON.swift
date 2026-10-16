import Foundation

/// Read-only view over JSONSerialization output. Missing keys and JSON null both read as "absent".
struct J {
    let raw: Any?

    init(_ raw: Any?) { self.raw = (raw is NSNull) ? nil : raw }

    subscript(key: String) -> J { J((raw as? [String: Any])?[key]) }

    subscript(index: Int) -> J {
        guard let a = raw as? [Any], a.indices.contains(index) else { return J(nil) }
        return J(a[index])
    }

    var exists: Bool { raw != nil }
    var string: String? { raw as? String }

    var number: Double? {
        guard let n = raw as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n.doubleValue
    }

    /// Same meaning as JavaScript Number.isFinite.
    var finite: Double? {
        guard let v = number, v.isFinite else { return nil }
        return v
    }

    var int: Int? { finite.map { Int($0) } }

    var bool: Bool? {
        guard let n = raw as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
        return n.boolValue
    }

    var array: [J] { (raw as? [Any])?.map { J($0) } ?? [] }
    var object: [String: J] { (raw as? [String: Any])?.mapValues { J($0) } ?? [:] }

    func jsonString() -> String? {
        guard let raw, JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
