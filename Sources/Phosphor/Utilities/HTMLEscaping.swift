import Foundation

extension String {
    /// Escapes characters that are unsafe to interpolate into HTML text or
    /// attribute contexts. Every HTML exporter routes device-controlled values
    /// (chat titles, sender names, message bodies) through this so a crafted
    /// group subject or sender such as `<img src=x onerror=...>` cannot inject
    /// script into an exported document.
    var htmlEscaped: String {
        var out = ""
        out.reserveCapacity(count)
        for ch in self {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(ch)
            }
        }
        return out
    }
}
