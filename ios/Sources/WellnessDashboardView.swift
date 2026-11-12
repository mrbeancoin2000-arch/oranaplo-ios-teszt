import SwiftUI
import Charts

/// All displayed values are queried from HealthKit or explicitly entered by the user.
/// A dash means no permission, no data or insufficient measurements.
struct WellnessDashboardView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var insights=WellnessInsightsService.shared
    @ObservedObject private var diary=WellnessDiary.shared
    @AppStorage("oranaplo.app.language") private var language="hu"
    @AppStorage("oranaplo.wellness.unusualPulseEnabled") private var unusualPulseAlerts=false
    @AppStorage("oranaplo.widgets.enabled") private var widgetsEnabled=false
    @State private var rating=7
    @State private var medName=""
    @State private var medDose=""
    @State private var roomTemperature=""
    @State private var humidity=""
    @State private var co2=""
    @State private var reportDays=30
    @State private var reportBusy=false
    @State private var reportURL: URL?
    @State private var feedback=""
    @State private var intervalRounds=10
    @State private var intervalDistance=100
    @State private var intervalPause=60

    private func t(_ hu:String,_ en:String,_ de:String)->String {
        language == "de" ? de : language == "en" ? en : hu
    }
    private func f(_ v:Double?,digits:Int=1)->String {
        guard let v, v.isFinite else { return "—" }
        return String(format:"%.*f",digits,v)
    }
    private func formNumber(_ raw:String)->Double? {
        Double(raw.replacingOccurrences(of:",",with:".").trimmingCharacters(in:.whitespacesAndNewlines))
    }
    private var s:WellnessInsightsSnapshot { insights.snapshot }
    var body:some View {
        NavigationStack {
            Form {
                Section {
                    Button { Task { await insights.refresh() } } label: {
                        Label(t("Mérések frissítése","Refresh measurements","Messungen aktualisieren"),systemImage:"arrow.clockwise")
                    }.disabled(insights.loading)
                    if insights.loading { ProgressView() }
                    Text(t("Az eredmények tájékoztató jellegűek. Nem diagnózisok és nem valós idejű riasztások.",
                           "Results are informational, not diagnoses or real-time emergency alerts.",
                           "Diese Ergebnisse sind informativ, keine Diagnosen oder Echtzeit-Notfallwarnungen."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(t("Pulzus és HRV alapértékek","Heart rate & HRV baselines","Puls- und HRV-Basiswerte")) {
                    ForEach([7,30,90],id:\.self) { days in
                        let resting=s.resting.first{$0.days == days}
                        let hrv=s.hrv.first{$0.days == days}
                        VStack(alignment:.leading,spacing:4) {
                            Text("\(days) " + t("nap","days","Tage")).font(.headline)
                            Text(t("Nyugalmi pulzus","Resting pulse","Ruhepuls") + ": \(f(resting?.mean)) bpm · n=\(resting?.samples ?? 0)")
                            Text("HRV SDNN: \(f(hrv?.mean)) ms · n=\(hrv?.samples ?? 0)")
                        }.font(.subheadline)
                    }
                    HStack {
                        Text(t("Napi átlagok korrelációja","Correlation of daily means","Korrelation der Tagesmittel"))
                        Spacer()
                        Text(f(s.pulseHRVCorrelation, digits:2))
                    }
                    Text("\(s.matchedDays) " + t("közös mérési nap; legalább 4 szükséges.",
                         "matched days; at least 4 needed.","gemeinsame Messtage; mindestens 4 erforderlich."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(t("Testsúly és testösszetétel","Weight and body composition","Gewicht und Körperzusammensetzung")) {
                    Text(t("Testsúly","Weight","Gewicht") + ": \(f(s.currentWeight?.value)) kg")
                    Text(t("Testzsír","Body fat","Körperfett") + ": \(f(s.currentBodyFat?.value)) %")
                    Text(t("Zsírmentes tömeg","Lean body mass","Fettfreie Masse") + ": \(f(s.currentLeanMass?.value)) kg")
                    if let latest=s.currentWeight { Text(latest.source).font(.caption).foregroundStyle(.secondary) }
                }
                Section(t("Értesítések","Notifications","Benachrichtigungen")) {
                    Toggle(t("Szokatlan nyugalmi pulzus","Unusual resting pulse","Ungewöhnlicher Ruhepuls"),isOn:$unusualPulseAlerts)
                    Toggle(t("Widget gyorsítótár engedélyezése","Enable widget cache","Widget-Cache aktivieren"),isOn:$widgetsEnabled)
                    Text(t("A widgetek tényleges használatához külön aláírt WidgetKit extension és App Group szükséges.",
                           "Live widgets require a separately signed WidgetKit extension and App Group.",
                           "Für Widgets sind eine separat signierte WidgetKit-Erweiterung und App Group erforderlich."))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(t("Csak új HealthKit-adat és iOS-háttérfutási lehetőség esetén; nem sürgősségi riasztás.",
                           "Requires new HealthKit data and iOS execution; not an emergency alert.",
                           "Nur bei neuen HealthKit-Daten und iOS-Ausführung; kein Notfallalarm."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(t("Edzés utáni pulzuscsökkenés","Post-workout heart rate recovery","Pulserholung nach Training")) {
                    if s.recovery.isEmpty { Text("—").foregroundStyle(.secondary) }
                    ForEach(s.recovery) { point in
                        HStack {
                            Text("\(point.minute) min")
                            Spacer()
                            Text("\(f(point.heartRate, digits:0)) bpm")
                            Text("Δ \(f(point.drop,digits:0)) bpm").foregroundStyle(.secondary)
                        }
                    }
                    Text(t("Csak a ténylegesen mért, időben közeli pulzusértékeket használjuk.",
                           "Only actual heart rate samples close to the target times are used.",
                           "Nur tatsächlich gemessene Pulswerte nahe den Zielzeiten werden verwendet."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(t("Alvás és regeneráció","Sleep and recovery","Schlaf und Erholung")) {
                    HStack {
                        Text(t("Rendszerességi pontszám","Regularity score","Regelmäßigkeitswert"))
                        Spacer();Text(f(s.sleepRegularity,digits:0) + (s.sleepRegularity == nil ? "" : "/100"))
                    }
                    HStack {
                        Text(t("Becsült 7 napos alváselmaradás","Estimated 7-day sleep shortfall","Geschätztes 7-Tage-Schlafdefizit"))
                        Spacer();Text(f(s.sleepDebtMinutes,digits:0) + " min")
                    }
                    Text(t("Alvás és másnapi HRV – korreláció","Sleep vs next-day HRV – correlation","Schlaf vs. HRV am Folgetag – Korrelation") + ": \(f(s.sleepAndNextDayHRVCorrelation,digits:2))")
                    Text(t("Alvás és másnapi nyugalmi pulzus","Sleep vs next-day resting HR","Schlaf vs. Ruhepuls am Folgetag") + ": \(f(s.sleepAndNextDayRestingCorrelation,digits:2))")
                    Text("n=\(s.nextDayPairs)").font(.caption).foregroundStyle(.secondary)
                    Text(t("Csuklóhőmérséklet eltérése az előző éjszakák átlagától",
                           "Wrist temperature relative to previous nights",
                           "Handgelenktemperatur gegenüber früheren Nächten") + ": \(f(s.wristTempDeviation,digits:2)) °C")
                    Text(t("A becslés napi 8 óra célhoz viszonyít, és nem klinikai alváshiány-diagnózis.",
                           "Estimated relative to an 8-hour goal, not a clinical sleep deprivation diagnosis.",
                           "Schätzung relativ zu 8 Stunden, keine klinische Diagnose."))
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(s.nights.reversed()) { night in
                        DisclosureGroup("\(night.id.formatted(date:.abbreviated,time:.omitted)) · \(Int(night.asleepMinutes)) min") {
                            VStack(alignment:.leading,spacing:8) {
                                if !night.stages.isEmpty {
                                    Chart(night.stages) { stage in
                                        RectangleMark(xStart:.value("Start",stage.start),xEnd:.value("End",stage.end),y:.value("Stage",stage.stage))
                                            .foregroundStyle(by:.value("Stage",stage.stage))
                                    }.frame(height:140)
                                }
                                Text(t("Ébredési szakaszok","Awake intervals","Wachphasen") + ": \(night.awakenings)")
                                Text(t("Légzésszám","Respiratory rate","Atemfrequenz") + ": \(f(night.respiratoryMean)) /min")
                                Text(t("Csuklóhőmérséklet","Wrist temperature","Handgelenktemperatur") + ": \(f(night.wristTemperatureMean, digits:2)) °C")
                            }.font(.caption)
                        }
                    }
                }
                Section(t("Mérési források","Measurement sources","Messquellen")) {
                    ForEach(s.sourceSamples) { record in
                        VStack(alignment:.leading) {
                            Text("\(record.at.formatted(date:.abbreviated,time:.standard)) · \(f(record.value, digits:2)) \(record.unit)")
                            Text("\(record.source) · \(record.device)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section(t("Vízivás","Water intake","Wasseraufnahme")) {
                    let today=Calendar.current.startOfDay(for:Date())
                    let total=diary.water.filter { $0.date >= today }.reduce(0){$0+$1.milliliters}
                    Text("\(total) ml").font(.title2.bold())
                    HStack {
                        Button("+200 ml") { addWater(200) }
                        Spacer()
                        Button("+300 ml") { addWater(300) }
                    }
                    Text(t("A Watch-bejegyzések az iPhone-nal való sikeres átvitel után jelennek meg.",
                           "Watch entries appear after successful transfer to iPhone.",
                           "Watch-Einträge erscheinen nach erfolgreicher Übertragung aufs iPhone."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(t("Reggeli alvásértékelés","Morning sleep rating","Morgendliche Schlafbewertung")) {
                    Stepper(value:$rating,in:1...10) { Text("\(rating)/10") }
                    Button(t("Értékelés mentése","Save rating","Bewertung speichern")) {
                        do { try diary.rateSleep(rating); feedback=t("Mentve","Saved","Gespeichert") }
                        catch { feedback=translatedError(error) }
                    }
                }
                Section(t("Szobakörnyezet","Room environment","Raumklima")) {
                    TextField("°C",text:$roomTemperature).keyboardType(.decimalPad)
                    TextField(t("Páratartalom (%)","Humidity (%)","Luftfeuchtigkeit (%)"),text:$humidity).keyboardType(.decimalPad)
                    TextField("CO₂ (ppm)",text:$co2).keyboardType(.decimalPad)
                    Button(t("Szobamérés mentése","Save room readings","Raumwerte speichern")) {
                        do {
                            try diary.addRoom(temperature:formNumber(roomTemperature),humidity:formNumber(humidity),co2:formNumber(co2))
                            roomTemperature="";humidity="";co2=""; feedback=t("Mentve","Saved","Gespeichert")
                        } catch { feedback=translatedError(error) }
                    }
                    Text(t("Jelenleg kézi bevitel. Külső CO₂-szenzor csak külön integrációval használható.",
                           "Manual entry for now; external CO₂ sensors require a separate integration.",
                           "Zurzeit manuelle Eingabe; externe CO₂-Sensoren benötigen eine Integration."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(t("Gyógyszernapló","Medication journal","Medikamententagebuch")) {
                    TextField(t("Gyógyszer neve","Medication name","Medikament"),text:$medName)
                    TextField(t("Adag (pl. 1 tabletta)","Dose (e.g. 1 tablet)","Dosis (z. B. 1 Tablette)"),text:$medDose)
                    HStack {
                        Button(t("Bevéve","Taken","Eingenommen")) { saveMedicine(true) }
                        Spacer()
                        Button(t("Kihagyva","Missed","Ausgelassen")) { saveMedicine(false) }.tint(.orange)
                    }
                    ForEach(diary.medicines.suffix(6).reversed()) { entry in
                        Text("\(entry.date.formatted(date:.abbreviated,time:.shortened)) · \(entry.name) · \(entry.dose) · " + (entry.taken ? "✓" : "—"))
                            .font(.caption)
                    }
                }
                Section(t("Intervallumedzés-tervező","Interval planner","Intervallplaner")) {
                    Stepper("\(intervalRounds) × \(intervalDistance) m",value:$intervalRounds,in:1...40)
                    Picker(t("Táv","Distance","Distanz"),selection:$intervalDistance) {
                        Text("100 m").tag(100);Text("200 m").tag(200);Text("400 m").tag(400);Text("1000 m").tag(1000)
                    }
                    Stepper(t("Pihenő","Rest","Pause") + ": \(intervalPause) s",value:$intervalPause,in:0...600,step:15)
                    Text(t("Tervező; az edzést továbbra is a Futás képernyőn indítsd.",
                           "Planner only; start recording on the Running screen.",
                           "Nur Planung; Aufzeichnung auf der Laufseite starten."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(t("Orvosi PDF","Medical PDF","Ärztlicher PDF-Bericht")) {
                    Picker(t("Időszak","Period","Zeitraum"),selection:$reportDays) {
                        Text("7").tag(7);Text("30").tag(30);Text("90").tag(90);Text("365").tag(365)
                        Text(t("Összes","All","Alle")).tag(0)
                    }
                    Button {
                        reportBusy=true;reportURL=nil
                        Task {
                            do { reportURL=try await MedicalPDFReport.generate(days:reportDays,language:language) }
                            catch { feedback=translatedError(error) }
                            reportBusy=false
                        }
                    } label: {
                        Label(t("PDF előállítása","Generate PDF","PDF erstellen"),systemImage:"doc.richtext")
                    }.disabled(reportBusy)
                    if reportBusy { ProgressView() }
                    if let reportURL { ShareLink(item:reportURL) {
                        Label(t("PDF megosztása vagy mentése","Share or save PDF","PDF teilen oder speichern"),systemImage:"square.and.arrow.up")
                    } }
                    Text(t("A PDF a telefonon készül. Nagy mennyiségű adatnál a jelentés jelezheti a mintakorlátot.",
                           "PDF is generated on-device; very large reports disclose sample limits.",
                           "PDF wird lokal erstellt; große Berichte kennzeichnen Stichprobenlimits."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !feedback.isEmpty { Section { Text(feedback).foregroundStyle(.orange) } }
            }
            .navigationTitle(t("Egészségelemzés","Health insights","Gesundheitsanalyse"))
            .toolbar { ToolbarItem(placement:.topBarTrailing) { Button(t("Bezár","Close","Schließen")) { dismiss() } } }
            .task { await insights.refresh() }
        }
    }
    private func translatedError(_ error:Error) -> String {
        if error is DiaryError {
            return t("Hibás adat vagy nem olvasható helyi napló.",
                     "Invalid data or unreadable local journal.",
                     "Ungültige Daten oder nicht lesbares lokales Tagebuch.")
        }
        if error is MedicalPDFReport.ReportError {
            return t("Nincs olvasható mérés a kiválasztott időszakban.",
                     "No accessible measurements in this period.",
                     "Keine lesbaren Messwerte im gewählten Zeitraum.")
        }
        return error.localizedDescription
    }
    private func addWater(_ ml:Int) {
        do { try diary.addWater(ml); feedback=t("Mentve","Saved","Gespeichert") }
        catch { feedback=translatedError(error) }
    }
    private func saveMedicine(_ taken:Bool) {
        do {
            try diary.medication(name:medName,dose:medDose,taken:taken)
            medName="";medDose="";feedback=t("Mentve","Saved","Gespeichert")
        } catch { feedback=error.localizedDescription }
    }
}
