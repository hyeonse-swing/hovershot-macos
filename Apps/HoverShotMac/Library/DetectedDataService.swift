import Foundation

public enum DetectedDataKind: String, Equatable, Sendable {
    case link
    case email
    case phoneNumber
}

public struct DetectedDataItem: Equatable, Sendable {
    public var id: String {
        "\(kind.rawValue):\(displayValue)"
    }

    public let kind: DetectedDataKind
    public let displayValue: String
    public let url: URL?

    public init(
        kind: DetectedDataKind,
        displayValue: String,
        url: URL?
    ) {
        self.kind = kind
        self.displayValue = displayValue
        self.url = url
    }
}

public struct DetectedDataService {
    public init() {}

    public func detect(in text: String) -> [DetectedDataItem] {
        guard text.isEmpty == false else {
            return []
        }

        let checkingTypes: NSTextCheckingResult.CheckingType = [
            .link,
            .phoneNumber
        ]

        guard let detector = try? NSDataDetector(types: checkingTypes.rawValue) else {
            return []
        }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var items: [DetectedDataItem] = []
        var seenIDs = Set<String>()

        detector.enumerateMatches(in: text, options: [], range: nsRange) { result, _, _ in
            guard let result else {
                return
            }

            let item: DetectedDataItem?

            if let phoneNumber = result.phoneNumber {
                item = DetectedDataItem(
                    kind: .phoneNumber,
                    displayValue: phoneNumber,
                    url: nil
                )
            } else if let url = result.url {
                if url.scheme == "mailto" {
                    let rawEmail = url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
                    let email = rawEmail.removingPercentEncoding ?? rawEmail
                    item = DetectedDataItem(
                        kind: .email,
                        displayValue: email,
                        url: url
                    )
                } else {
                    item = DetectedDataItem(
                        kind: .link,
                        displayValue: url.absoluteString,
                        url: url
                    )
                }
            } else {
                item = nil
            }

            guard let item, seenIDs.insert(item.id).inserted else {
                return
            }

            items.append(item)
        }

        return items
    }
}
