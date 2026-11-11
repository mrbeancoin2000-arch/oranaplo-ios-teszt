// Offline sandbox-only integration checks of the optional Apps Script; no Google account used.
const fs = require('fs'), vm = require('vm'), assert = require('assert');
const code = fs.readFileSync(__dirname + '/../scripts/Ertekeles.gs', 'utf8');
class FakeSheet {
  constructor(rows) { this.rows = rows.map(r=>r.slice()); }
  getLastRow(){return this.rows.length}
  getLastColumn(){return Math.max(1,...this.rows.map(r=>r.length))}
  getRange(first, col, nRows, nCols) {
    return {
      getValues:()=>Array.from({length:nRows},(_,i)=>Array.from({length:nCols},(_,j)=>this.rows[first-1+i]?.[col-1+j] ?? '')),
      setValues:values=>{values.forEach((r,i)=>{if(!this.rows[first-1+i])this.rows[first-1+i]=[];r.forEach((v,j)=>this.rows[first-1+i][col-1+j]=v)})}
    }
  }
  clearContents(){this.rows=[]}
  setFrozenRows(){}
}
function run(age) {
 const profile=new FakeSheet([['mezo','ertek'], ['age_years',age]]);
 const external=new FakeSheet([
   ['header'],
   ['id-s','Vérnyomás szisztolés','2026-11-11T17:00:00Z','','151','mmHg','','','','aktív',''],
   ['id-d','Vérnyomás diasztolés','2026-11-11T17:00:20Z','','95','mmHg','','','','aktív',''],
 ]);
 const output=new FakeSheet([]);
 const tabs={Profil:profile, KulsoMeresek:external, Megfigyelesek:output};
 const book={getSheetByName:name=>tabs[name]||null,insertSheet:name=>(tabs[name]=new FakeSheet([])),getSpreadsheetTimeZone:()=> 'UTC'};
 class FakeDate extends Date {constructor(...args){super(...(args.length?args:['2026-11-11T21:10:00Z']))}static now(){return new Date('2026-11-11T21:10:00Z').getTime()}}
 const ctx={Date:FakeDate, Number, String, Object, Math, Set, SpreadsheetApp:{getActiveSpreadsheet:()=>book},Utilities:{formatDate:(d,tz,pattern)=>{let date=d.toISOString();if(pattern==='H')return String(d.getUTCHours()); return date.slice(0,10)}}};
 vm.createContext(ctx); vm.runInContext(code,ctx);
 const count=ctx.frissitMegfigyelesek();
 return {count, rows:tabs.Megfigyelesek.rows};
}
const adult=run(35);
assert.strictEqual(adult.count,1);
assert.strictEqual(adult.rows[1][1],'bp.review');
assert.strictEqual(run(16).count,0);
assert.strictEqual(run('').count,0);
console.log('Apps Script offline checks: adult warning / minor suppression / no age: OK');
