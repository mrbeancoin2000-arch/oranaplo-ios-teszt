import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Apple Health export.xml parser. No HealthKit entitlement or Apple Developer membership
/// is required to parse a file that the user explicitly selects in the Files picker.
/// Streaming callback: the entire Health export is never loaded into application memory.
struct HealthXMLRecord {
    let id: String
    let type: String
    let source: String
    let device: String
    let start: Date
    let end: Date
    let value: String
    let unit: String
}

struct HealthXMLStatistics {
    var recordsSeen = 0
    var recordsAccepted = 0
    var skippedType = 0
    var invalidRecords = 0
    var batches = 0
}

enum HealthXMLFailure: LocalizedError {
    case unreadableFile
    case invalidXML(String)
    case batchFailed(String)
    var errorDescription: String? {
        switch self {
        case .unreadableFile: return "The selected Apple Health XML file cannot be opened."
        case .invalidXML(let reason): return "Invalid Apple Health XML: \(reason)"
        case .batchFailed(let reason): return "Health XML import stopped: \(reason)"
        }
    }
}

enum HealthXMLCore {
    static func parse(url: URL, allowedTypes: Set<String>, batchSize: Int = 250,
                      acceptBatch: @escaping ([HealthXMLRecord]) throws -> Void) throws -> HealthXMLStatistics {
        guard let input = InputStream(url: url) else { throw HealthXMLFailure.unreadableFile }
        let parser = XMLParser(stream: input)
        let receiver = Receiver(allowedTypes: allowedTypes, batchSize: max(1, batchSize), acceptBatch: acceptBatch)
        parser.delegate = receiver
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        let parsed = parser.parse()
        if let failure = receiver.failure { throw failure }
        guard parsed else { throw HealthXMLFailure.invalidXML(parser.parserError?.localizedDescription ?? "Unknown XML parsing error") }
        guard receiver.sawHealthData else { throw HealthXMLFailure.invalidXML("The file is not Apple Health export.xml") }
        try receiver.finish()
        return receiver.statistics
    }

    private final class Receiver: NSObject, XMLParserDelegate {
        let allowedTypes: Set<String>
        let batchSize: Int
        let acceptBatch: ([HealthXMLRecord]) throws -> Void
        var buffer: [HealthXMLRecord] = []
        var statistics = HealthXMLStatistics()
        var failure: Error?
        var sawHealthData = false
        private let dateFormat = DateFormatter()

        init(allowedTypes: Set<String>, batchSize: Int,
             acceptBatch: @escaping ([HealthXMLRecord]) throws -> Void) {
            self.allowedTypes = allowedTypes
            self.batchSize = batchSize
            self.acceptBatch = acceptBatch
            super.init()
            dateFormat.locale = Locale(identifier: "en_US_POSIX")
            dateFormat.timeZone = TimeZone(secondsFromGMT: 0)
            dateFormat.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        }
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes: [String: String]) {
            if elementName == "HealthData" { sawHealthData = true }
            guard elementName == "Record" else { return }
            statistics.recordsSeen += 1
            guard let type = attributes["type"], allowedTypes.contains(type) else {
                statistics.skippedType += 1; return
            }
            guard let startString = attributes["startDate"], let endString = attributes["endDate"],
                  let start = dateFormat.date(from: startString), let end = dateFormat.date(from: endString),
                  end >= start, let value = attributes["value"], !value.isEmpty else {
                statistics.invalidRecords += 1; return
            }
            let stable = [type, startString, endString, value, attributes["unit"] ?? "",
                          attributes["sourceName"] ?? "", attributes["sourceVersion"] ?? "",
                          attributes["creationDate"] ?? "", attributes["device"] ?? ""]
                .joined(separator: "\u{001F}")
            let record = HealthXMLRecord(id: "xml:" + stableIdentifier(stable), type: type,
                source: attributes["sourceName"] ?? "Apple Health XML",
                device: attributes["device"] ?? "",
                start: start, end: end, value: value,
                unit: attributes["unit"] ?? "")
            buffer.append(record)
            statistics.recordsAccepted += 1
            if buffer.count >= batchSize { flush(parser: parser) }
        }
        private func flush(parser: XMLParser?) {
            guard !buffer.isEmpty else { return }
            let current = buffer
            buffer.removeAll(keepingCapacity: true)
            do { try acceptBatch(current); statistics.batches += 1 }
            catch {
                failure = HealthXMLFailure.batchFailed(error.localizedDescription)
                parser?.abortParsing()
            }
        }
        func finish() throws {
            flush(parser: nil)
            if let failure { throw failure }
        }
    }

    /// Stable, deliberately non-secret identifier. FNV-1a is not used for authentication.
    private static func stableIdentifier(_ string: String) -> String {
        var left: UInt64 = 14695981039346656037
        var right: UInt64 = 1099511628211
        for byte in string.utf8 {
            left = (left ^ UInt64(byte)) &* 1099511628211
            right = (right ^ UInt64(byte)) &* 14695981039346656037
        }
        return String(format: "%016llx%016llx", left, right)
    }

    /// Convert only documented, compatible units. Never silently relabel unknown units.
    static func convertedValue(_ value: String, from sourceUnit: String, to targetUnit: String) -> String? {
        if targetUnit == "enum" { return value }
        guard let number = Double(value), number.isFinite else { return nil }
        let factors: [String: [String: Double]] = [
            "bpm": ["count/min": 1, "bpm": 1],
            "ms": ["ms": 1, "s": 1000],
            "sec": ["s": 1, "sec": 1, "min": 60],
            "min": ["min": 1, "s": 1.0 / 60.0],
            "m": ["m": 1, "km": 1000],
            "cm": ["cm": 1, "m": 100],
            "km": ["km": 1, "m": 0.001],
            "m/s": ["m/s": 1, "km/hr": 1.0 / 3.6],
            "W": ["W": 1], "kcal": ["kcal": 1, "Cal": 1],
            "count": ["count": 1], "count/min": ["count/min": 1],
            // Health XML percentages (e.g. 98) -> HealthKit fraction (0.98).
            "%": ["%": 0.01], "kg": ["kg": 1], "g": ["g": 1],
            "mg": ["mg": 1], "mcg": ["mcg": 1, "µg": 1],
            "L": ["L": 1, "mL": 0.001],
            "mL": ["mL": 1, "L": 1000],
            "mmHg": ["mmHg": 1], "mg/dL": ["mg/dL": 1],
            "degC": ["degC": 1, "°C": 1],
            "dB": ["dB": 1, "dBASPL": 1],
            "mL/kg/min": ["mL/kg/min": 1]
        ]
        guard let multiplier = factors[targetUnit]?[sourceUnit] else { return nil }
        return String(number * multiplier)
    }
}
