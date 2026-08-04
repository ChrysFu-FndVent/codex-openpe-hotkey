import Foundation

public struct ReleaseVersion: Comparable, Equatable {
    public let components: [Int]

    public init?(_ value: String) {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingPrefix("v")
        let versionPart = normalized.split(separator: "-", maxSplits: 1).first ?? ""
        let components = versionPart.split(separator: ".").map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              components.count <= 4 else {
            return nil
        }
        self.components = components.compactMap(Int.init)
    }

    public static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    public static func == (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

private extension String {
    func trimmingPrefix(_ prefix: Character) -> String {
        first == prefix ? String(dropFirst()) : self
    }
}
