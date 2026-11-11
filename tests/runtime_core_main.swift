import Foundation

@main
struct OfflineCoreTests {
    static var assertions = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
    static func main() throws {
        guard CommandLine.arguments.count > 1 else { fatalError("Missing synthetic fixture path") }
        let fixture = URL(fileURLWithPath: CommandLine.arguments[1])
        var free: [HealthXMLRecord] = []
        let hrType = "HKQuantityTypeIdentifierHeartRate"
        let freeStats = try HealthXMLCore.parse(url: fixture, allowedTypes: [hrType], batchSize: 1) {
            free.append(contentsOf: $0)
        }
        check(freeStats.recordsSeen == 7, "all synthetic record tags counted")
        check(freeStats.recordsAccepted == 2, "free tier accepts two valid heart measurements")
        check(freeStats.invalidRecords == 1, "bad dates rejected")
        check(freeStats.skippedType == 4, "free tier does not parse HRV, water, sleep, or unknown")
        check(free.count == 2 && free.allSatisfy { $0.type == hrType }, "free tier type isolation")
        check(free[0].start < free[1].start, "timestamps preserve local offsets")
        check(free[0].id != free[1].id, "unique record IDs")
        let repeats = try HealthXMLCore.parse(url: fixture, allowedTypes: [hrType]) { batch in
            check(batch[0].id == free[0].id, "stable ID across imports")
        }
        check(repeats.recordsAccepted == 2, "repeat count")
        var pro: [HealthXMLRecord] = []
        let proTypes: Set<String> = [hrType, "HKQuantityTypeIdentifierHeartRateVariabilitySDNN",
            "HKQuantityTypeIdentifierDietaryWater", "HKCategoryTypeIdentifierSleepAnalysis"]
        let proStats = try HealthXMLCore.parse(url: fixture, allowedTypes: proTypes, batchSize: 2) {
            pro.append(contentsOf: $0)
        }
        check(pro.count == 5 && proStats.recordsAccepted == 5, "pro supports HRV, water, sleep")
        check(proStats.batches == 3, "streamed batch count")
        check(HealthXMLCore.convertedValue("0.75", from: "L", to: "mL") == "750.0", "L to mL")
        check(HealthXMLCore.convertedValue("55", from: "ms", to: "ms") == "55.0", "HRV ms")
        check(HealthXMLCore.convertedValue("98", from: "%", to: "%") == "0.98", "percent reconciles with HealthKit fraction")
        check(HealthXMLCore.convertedValue("88", from: "furlongs", to: "bpm") == nil, "reject unknown units")
        check(HealthXMLCore.convertedValue("HKCategoryValueSleepAnalysisAsleepREM", from: "", to: "enum") != nil, "category strings")
        // Ensure a failure in the persistence callback aborts the streaming parse.
        do {
            _ = try HealthXMLCore.parse(url: fixture, allowedTypes: [hrType], batchSize: 1) { _ in
                throw HealthXMLFailure.batchFailed("test disk full")
            }
            check(false, "expected import callback failure")
        } catch { check(error.localizedDescription.contains("test disk full"), "error propagates to the caller") }
        let start = Date(timeIntervalSince1970: 100_000)
        let fixes = (0..<11).map { n in
            TrackFix(time: start.addingTimeInterval(Double(n * 40)), latitude: Double(n) * 0.0009,
                     longitude: 19, accuracyMeters: 3)
        }
        let pulse = (0..<10).map { n in HeartFix(time: start.addingTimeInterval(Double(n * 40 + 15)), beatsPerMinute: Double(100 + n)) }
        let splits = SplitMath.calculate(fixes, hearts: pulse, workoutStart: start,
                                        workoutEnd: start.addingTimeInterval(400))
        check(splits.count == 10, "ten approximately 100 m GPS segments")
        check(splits.allSatisfy { abs($0.elapsedSeconds - 39.97) < 3 }, "interpolated segment times")
        check(splits.allSatisfy { $0.heartMean != nil }, "recorded pulse attached to each section")
        check(abs(SplitMath.distanceMeters(fixes[0], fixes[1]) - 100) < 1, "Haversine distance")
        let withoutPulse = SplitMath.calculate(fixes, hearts: [], workoutStart: start,
                                               workoutEnd: start.addingTimeInterval(400))
        check(withoutPulse.allSatisfy { $0.heartMean == nil }, "never invent missing pulse")
        let outlier = TrackFix(time: start.addingTimeInterval(1), latitude: 2, longitude: 19, accuracyMeters: 3)
        let unsafe = SplitMath.calculate([fixes[0], outlier], hearts: pulse, workoutStart: start,
                                         workoutEnd: start.addingTimeInterval(400))
        check(unsafe.isEmpty, "reject GPS teleport")
        let inaccurate = TrackFix(time: start.addingTimeInterval(400), latitude: 0.01, longitude: 19, accuracyMeters: 80)
        check(SplitMath.calculate([fixes[0], inaccurate], hearts: [], workoutStart: start,
                                  workoutEnd: start.addingTimeInterval(500)).isEmpty, "reject inaccurate GPS")
        print("SWIFT RUNTIME CORE: PASS (\(assertions) assertions, Apple Health XML + 100 m GPS + HR)")
    }
}
