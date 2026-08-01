import Foundation

enum Diagnostics {
    private static let formatter = ISO8601DateFormatter()

    static func log(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        FileHandle.standardError.write(data)
    }
}
