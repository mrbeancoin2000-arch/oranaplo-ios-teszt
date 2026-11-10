import Foundation
import HealthKit

struct ExportRow: Codable, Hashable, Identifiable {
    var id: String
    var sheet: String
    var values: [String]
}

struct Metric: Identifiable, Hashable {
    let id: String           // HK raw identifier
    let label: String
    let unit: String
    let sheet: String
    let group: String
    let isCategory: Bool
    init(_ id: String, _ label: String, _ unit: String, _ sheet: String, _ group: String, category: Bool = false) {
        self.id = (category ? "HKCategoryTypeIdentifier" : "HKQuantityTypeIdentifier") + id
        self.label = label; self.unit = unit; self.sheet = sheet; self.group = group; self.isCategory = category
    }
    var sampleType: HKSampleType? {
        if isCategory { return HKObjectType.categoryType(forIdentifier: HKCategoryTypeIdentifier(rawValue: id)) }
        return HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier(rawValue: id))
    }
    var quantityUnit: HKUnit {
        switch unit {
        case "bpm": return HKUnit.count().unitDivided(by: .minute())
        case "ms": return .secondUnit(with: .milli)
        case "sec": return .second()
        case "min": return .minute()
        case "m": return .meter()
        case "cm": return .meterUnit(with: .centi)
        case "km": return .meterUnit(with: .kilo)
        case "m/s": return .meter().unitDivided(by: .second())
        case "W": return .watt()
        case "kcal": return .kilocalorie()
        case "count": return .count()
        case "count/min": return .count().unitDivided(by: .minute())
        case "%": return .percent()
        case "kg": return .gramUnit(with: .kilo)
        case "g": return .gram()
        case "mg": return .gramUnit(with: .milli)
        case "mcg": return .gramUnit(with: .micro)
        case "L": return .liter()
        case "mL": return .literUnit(with: .milli)
        case "mmHg": return .millimeterOfMercury()
        case "mg/dL": return .gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))
        case "degC": return .degreeCelsius()
        case "dB": return .decibelAWeightedSoundPressureLevel()
        case "mL/kg/min": return .literUnit(with: .milli).unitDivided(by: .gramUnit(with: .kilo)).unitDivided(by: .minute())
        default: return .count()
        }
    }
}

enum Catalog {
    // Identifiers resolved at runtime: unavailable types are skipped with a log instead of crashing.
    static let metrics: [Metric] = [
        Metric("HeartRate", "Pulzus", "bpm", "Pulzus", "sziv"),
        Metric("RestingHeartRate", "Nyugalmi pulzus", "bpm", "Pulzus", "sziv"),
        Metric("WalkingHeartRateAverage", "Sétáló pulzus", "bpm", "Pulzus", "sziv"),
        Metric("HeartRateVariabilitySDNN", "HRV SDNN", "ms", "HRV", "sziv"),
        Metric("HeartRateRecoveryOneMinute", "Edzés utáni pulzuscsökkenés", "bpm", "Pulzus", "sziv"),
        Metric("OxygenSaturation", "Véroxigén", "%", "Pulzus", "sziv"),
        Metric("RespiratoryRate", "Légzésszám", "count/min", "Alvas", "alvas"),
        Metric("AppleSleepingWristTemperature", "Alvási csuklóhőmérséklet", "degC", "Alvas", "alvas"),
        Metric("AppleSleepingBreathingDisturbances", "Alvási légzészavar", "count", "Alvas", "alvas"),
        Metric("SleepAnalysis", "Alvásszakasz", "enum", "Alvas", "alvas", category: true),
        Metric("HighHeartRateEvent", "Magas pulzus esemény", "enum", "Jelzesek", "sziv", category: true),
        Metric("LowHeartRateEvent", "Alacsony pulzus esemény", "enum", "Jelzesek", "sziv", category: true),
        Metric("IrregularHeartRhythmEvent", "Szabálytalan ritmus jelzés", "enum", "Jelzesek", "sziv", category: true),
        Metric("StepCount", "Lépések", "count", "Aktivitas", "aktivitas"),
        Metric("DistanceWalkingRunning", "Gyaloglás / futás távolság", "m", "Aktivitas", "aktivitas"),
        Metric("ActiveEnergyBurned", "Aktív energia", "kcal", "Aktivitas", "aktivitas"),
        Metric("BasalEnergyBurned", "Nyugalmi energia", "kcal", "Aktivitas", "aktivitas"),
        Metric("AppleExerciseTime", "Mozgásidő", "min", "Aktivitas", "aktivitas"),
        Metric("AppleStandTime", "Állásidő", "min", "Aktivitas", "aktivitas"),
        Metric("FlightsClimbed", "Megmászott emeletek", "count", "Aktivitas", "aktivitas"),
        Metric("WalkingSpeed", "Gyaloglási sebesség", "m/s", "Aktivitas", "aktivitas"),
        Metric("WalkingStepLength", "Lépéshossz", "cm", "Aktivitas", "aktivitas"),
        Metric("WalkingAsymmetryPercentage", "Járásaszimmetria", "%", "Aktivitas", "aktivitas"),
        Metric("WalkingDoubleSupportPercentage", "Kettős támaszfázis", "%", "Aktivitas", "aktivitas"),
        Metric("AppleWalkingSteadiness", "Járásstabilitás", "%", "Aktivitas", "aktivitas"),
        Metric("TimeInDaylight", "Természetes fény", "min", "Aktivitas", "aktivitas"),
        Metric("RunningSpeed", "Futósebesség", "m/s", "Sportmeresek", "edzes"),
        Metric("RunningPower", "Futóteljesítmény", "W", "Sportmeresek", "edzes"),
        Metric("RunningStrideLength", "Futási lépéshossz", "m", "Sportmeresek", "edzes"),
        Metric("RunningGroundContactTime", "Talajérintési idő", "ms", "Sportmeresek", "edzes"),
        Metric("RunningVerticalOscillation", "Függőleges oszcilláció", "cm", "Sportmeresek", "edzes"),
        Metric("CyclingSpeed", "Kerékpáros sebesség", "m/s", "Sportmeresek", "edzes"),
        Metric("CyclingCadence", "Kerékpáros pedálfordulat", "count/min", "Sportmeresek", "edzes"),
        Metric("CyclingPower", "Kerékpáros teljesítmény", "W", "Sportmeresek", "edzes"),
        Metric("DistanceCycling", "Kerékpározott távolság", "m", "Sportmeresek", "edzes"),
        Metric("DistanceSwimming", "Úszótávolság", "m", "Sportmeresek", "edzes"),
        Metric("SwimmingStrokeCount", "Úszókarcsapások", "count", "Sportmeresek", "edzes"),
        Metric("BodyMass", "Testsúly", "kg", "Test", "test"),
        Metric("Height", "Testmagasság", "cm", "Test", "test"),
        Metric("BodyMassIndex", "BMI", "count", "Test", "test"),
        Metric("BodyFatPercentage", "Testzsír", "%", "Test", "test"),
        Metric("LeanBodyMass", "Zsírmentes testtömeg", "kg", "Test", "test"),
        Metric("WaistCircumference", "Derékbőség", "cm", "Test", "test"),
        Metric("DietaryEnergyConsumed", "Bevitt energia", "kcal", "Taplalkozas", "taplalkozas"),
        Metric("DietaryProtein", "Fehérje", "g", "Taplalkozas", "taplalkozas"),
        Metric("DietaryCarbohydrates", "Szénhidrát", "g", "Taplalkozas", "taplalkozas"),
        Metric("DietaryFatTotal", "Zsír", "g", "Taplalkozas", "taplalkozas"),
        Metric("DietaryFiber", "Rost", "g", "Taplalkozas", "taplalkozas"),
        Metric("DietarySugar", "Cukor", "g", "Taplalkozas", "taplalkozas"),
        Metric("DietarySodium", "Nátrium", "mg", "Taplalkozas", "taplalkozas"),
        Metric("DietaryPotassium", "Kálium", "mg", "Taplalkozas", "taplalkozas"),
        Metric("DietaryMagnesium", "Magnézium", "mg", "Taplalkozas", "taplalkozas"),
        Metric("DietaryIron", "Vas", "mg", "Taplalkozas", "taplalkozas"),
        Metric("DietaryVitaminD", "D-vitamin", "mcg", "Taplalkozas", "taplalkozas"),
        Metric("DietaryWater", "Folyadék", "mL", "Taplalkozas", "taplalkozas"),
        Metric("DietaryCaffeine", "Koffein", "mg", "Taplalkozas", "taplalkozas"),
        Metric("BloodPressureSystolic", "Vérnyomás szisztolés", "mmHg", "KulsoMeresek", "kulso"),
        Metric("BloodPressureDiastolic", "Vérnyomás diasztolés", "mmHg", "KulsoMeresek", "kulso"),
        Metric("BloodGlucose", "Vércukor", "mg/dL", "KulsoMeresek", "kulso"),
        Metric("BodyTemperature", "Testhőmérséklet", "degC", "KulsoMeresek", "kulso"),
        Metric("BasalBodyTemperature", "Alaphőmérséklet", "degC", "KulsoMeresek", "kulso"),
        Metric("EnvironmentalAudioExposure", "Környezeti hangterhelés", "dB", "KulsoMeresek", "kulso"),
        Metric("HeadphoneAudioExposure", "Fejhallgató hangterhelés", "dB", "KulsoMeresek", "kulso")
    ]
    static let groups: [(String,String)] = [
        ("sziv", "Szív és keringés"), ("alvas", "Alvás"), ("aktivitas", "Aktivitás"),
        ("edzes", "Edzés"), ("test", "Testösszetétel"),
        ("taplalkozas", "Táplálkozás"), ("kulso", "Külső mérések")
    ]
    static let sheets = ["Pulzus", "HRV", "Alvas", "Edzesek", "100m", "Aktivitas", "Sportmeresek", "Test", "Taplalkozas", "KulsoMeresek", "Jelzesek", "EKG", "Akkumulator", "Naplo", "Rendszernaplo"]
    static let rawHeader = ["azonosito", "tipus", "kezdet_UTC", "veg_UTC", "ertek", "egyseg", "forras", "eszkoz", "megjegyzes", "allapot", "mentes_UTC"]
    static let segmentHeader = ["azonosito", "edzes_azonosito", "sport", "szakasz_m", "kezdet_UTC", "veg_UTC", "ido_masodperc", "sebesseg_kmh", "tempo_perc_km", "pulzus_atlag", "pulzus_min", "pulzus_max", "gps_pontossag", "mentes_UTC"]
    static let workoutHeader = ["azonosito", "sport", "kezdet_UTC", "veg_UTC", "ido_masodperc", "kaloria_kcal", "tavolsag_m", "pulzus_atlag", "pulzus_min", "pulzus_max", "megjegyzes", "mentes_UTC"]
}

enum ISO {
    static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    static func string(_ date: Date) -> String { formatter.string(from: date) }
}
