/**
 * ÓraNapló – optional Google Sheets analysis, owned by the spreadsheet owner.
 * The customer manually installs this script through Extensions > Apps Script.
 * It runs only in the customer's account and never contacts the developer.
 * Not medical diagnosis or emergency monitoring. No email or third-party APIs.
 */
const ORA = Object.freeze({
  output: 'Megfigyelesek', profile: 'Profil', settings: 'ElemzesBeallitasok'
});

function onOpen() {
  SpreadsheetApp.getUi().createMenu('ÓraNapló')
    .addItem('Megfigyelések frissítése', 'frissitMegfigyelesek')
    .addItem('Napi automatikus ellenőrzés beállítása', 'telepitNapiEllenorzes')
    .addToUi();
}

function telepitNapiEllenorzes() {
  // Installable triggers run as the user who explicitly authorizes the script.
  ScriptApp.getProjectTriggers()
    .filter(t => t.getHandlerFunction() === 'frissitMegfigyelesek')
    .forEach(t => ScriptApp.deleteTrigger(t));
  ScriptApp.newTrigger('frissitMegfigyelesek').timeBased().everyDays(1).atHour(21).create();
  SpreadsheetApp.getUi().alert('A napi ellenőrzés beállítva. A futási idő hozzávetőleges.');
}

function oraRows_(book, sheetName, maxRows = 12000) {
  const sheet = book.getSheetByName(sheetName);
  if (!sheet || sheet.getLastRow() < 2) return [];
  const n = sheet.getLastRow();
  return sheet.getRange(Math.max(2, n - maxRows + 1), 1, Math.min(n - 1, maxRows), Math.max(11, sheet.getLastColumn()))
    .getValues();
}
function oraTime_(v) {
  const d = v instanceof Date ? v : new Date(String(v || ''));
  return Number.isFinite(d.getTime()) ? d : null;
}
function oraDay_(d, tz) { return Utilities.formatDate(d, tz, 'yyyy-MM-dd'); }
function oraNumber_(v) {
  const n = Number(String(v).replace(',', '.'));
  return Number.isFinite(n) ? n : NaN;
}
function oraProfile_(book) {
  const sheet = book.getSheetByName(ORA.profile);
  if (!sheet || sheet.getLastRow() < 2) return {};
  return Object.fromEntries(sheet.getRange(2, 1, sheet.getLastRow() - 1, 2).getValues()
    .map(row => [String(row[0]), row[1]]));
}
function oraSettings_(book) {
  const sheet = book.getSheetByName(ORA.settings);
  if (!sheet || sheet.getLastRow() < 2) return {};
  return Object.fromEntries(sheet.getRange(2, 1, sheet.getLastRow() - 1, 2).getValues()
    .map(row => [String(row[0]), row[1]]));
}

function frissitMegfigyelesek() {
  const book = SpreadsheetApp.getActiveSpreadsheet();
  const tz = book.getSpreadsheetTimeZone();
  const now = new Date();
  const profile = oraProfile_(book);
  const settings = oraSettings_(book);
  const events = [];
  const external = oraRows_(book, 'KulsoMeresek');
  const bp = { sys: [], dia: [] };
  external.forEach(row => {
    if (row[9] === 'törölve') return;
    const time = oraTime_(row[2]);
    if (!time || now - time > 30 * 86400000) return;
    const n = oraNumber_(row[4]);
    if (!Number.isFinite(n) || n <= 0) return;
    if (row[1] === 'Vérnyomás szisztolés') bp.sys.push({time, value:n});
    if (row[1] === 'Vérnyomás diasztolés') bp.dia.push({time, value:n});
  });
  // Adult thresholds only; date of birth is never required in this spreadsheet.
  if (Number(profile.age_years) >= 18) {
    const pairs = [];
    bp.sys.forEach(s => {
      const d = bp.dia.filter(x => Math.abs(x.time - s.time) <= 60000)
        .sort((a,b) => Math.abs(a.time-s.time) - Math.abs(b.time-s.time))[0];
      if (!d) return;
      const code = s.value > 180 || d.value > 120 ? 'bp.urgent' :
                   s.value >= 140 || d.value >= 90 ? 'bp.review' : '';
      if (code) pairs.push({code, value:`${Math.round(s.value)}/${Math.round(d.value)} mmHg`, time:s.time});
    });
    pairs.sort((a,b) => b.time-a.time);
    if (pairs.length) {
      const p = pairs[0];
      events.push([`bp-${p.time.getTime()}`,p.code,p.time.toISOString(),p.value,
                   p.code === 'bp.urgent' ? 'urgent':'review','Saját Google Sheets']);
    }
  }
  // Relative step comparison only after 20:00. Incomplete days are not interpreted as zero.
  const hour = Number(Utilities.formatDate(now, tz, 'H'));
  if (hour >= 20) {
    const all = oraRows_(book, 'Aktivitas');
    const perDay = {};
    all.forEach(row => {
      if (row[1] !== 'Lépések' || row[9] === 'törölve') return;
      const t = oraTime_(row[2]), n = oraNumber_(row[4]);
      if (!t || !Number.isFinite(n)) return;
      const day = oraDay_(t,tz);
      perDay[day] = (perDay[day] || 0) + n;
    });
    const today = oraDay_(now,tz);
    const history=[];
    for (let gap=1;gap<=7;gap++) {
      const day=oraDay_(new Date(now.getTime()-gap*86400000),tz);
      if (Object.hasOwn(perDay, day)) history.push(perDay[day]);
    }
    history.sort((a,b)=>a-b);
    const median = history[Math.floor(history.length/2)];
    if (history.length>=5 && median>=1500 && Object.hasOwn(perDay,today) && perDay[today]<median/2) {
      events.push([`steps-${today}`,'activity.lower',now.toISOString(),String(Math.round(perDay[today])),'info','Saját Google Sheets']);
    }
    // Only if user explicitly marks the fluid log complete AND sets their personal goal.
    const complete = String(settings.teljes_folyadeknaplo).trim().toUpperCase() === 'IGEN';
    const goal = oraNumber_(settings.napi_cel_ml);
    if (complete && goal>=250 && goal<=10000) {
      const fluids = oraRows_(book, 'Taplalkozas')
        .filter(row=>row[1] === 'Folyadék' && row[9] !== 'törölve' && oraTime_(row[2]) && oraDay_(oraTime_(row[2]),tz)===today)
        .map(row=>oraNumber_(row[4])).filter(Number.isFinite);
      if (fluids.length) {
        const recorded=fluids.reduce((a,b)=>a+b,0);
        if (recorded < goal*0.8) {
          events.push([`water-${today}`,'water.lower',now.toISOString(),`${Math.round(recorded)} / ${Math.round(goal)} mL`,'info','Saját Google Sheets']);
        }
      }
    }
  }
  const output = book.getSheetByName(ORA.output) || book.insertSheet(ORA.output);
  output.clearContents();
  output.getRange(1,1,1,6).setValues([['azonosito','jelzes_kod','meres_UTC','ertek','szint','forras']]);
  if (events.length) output.getRange(2,1,events.length,6).setValues(events);
  output.setFrozenRows(1);
  return events.length;
}
