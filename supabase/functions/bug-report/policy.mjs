// A pure, testable whitelist. Never forward the caller's raw JSON to mail.
const CATEGORIES = new Set(['sync', 'running', 'google', 'watch', 'purchase', 'other']);
const REASONS = new Set(['none', 'network', 'authorization', 'quota', 'unknown']);

const EVENT_CODES = new Set([
  'sync.started','sync.finished','sync.failed','sheet.started','sheet.finished','sheet.failed',
  'run.started','run.paused','run.resumed','run.finished','run.interrupted',
  'run.storage_damaged','run.erased','ranking.deleted','report.failed'
]);

export function parseSafeReport(raw) {
  if (typeof raw !== 'string' || raw.length > 1500) return null;
  let value;
  try { value = JSON.parse(raw); } catch { return null; }
  if (!value || Array.isArray(value) || typeof value !== 'object') return null;
  const { category, reason_code: reason, app_version: version, platform } = value;
  if (typeof category !== 'string' || !CATEGORIES.has(category) ||
      typeof reason !== 'string' || !REASONS.has(reason) ||
      typeof version !== 'string' || !/^[0-9a-zA-Z.-]{1,32}$/.test(version) ||
      platform !== 'iOS') return null;
  if (!Array.isArray(value.event_codes) || value.event_codes.length > 12 ||
      !value.event_codes.every((code) => typeof code === 'string' && EVENT_CODES.has(code))) return null;
  return { category, reason, version, platform: 'iOS', events: [...value.event_codes] };
}

export function makeSafeEmail(report, dayUTC) {
  return [
    'ÓraNapló hibabejelentés',
    `Kategória: ${report.category}`,
    `Hibakód: ${report.reason}`,
    `Alkalmazásverzió: ${report.version}`,
    'Platform: iOS',
    `Nap (UTC): ${dayUTC}`,
    `Anonim technikai eseménykódok: ${report.events.join(', ') || 'nincs'}`,
    'Nincs továbbítva egészségadat, GPS, felhasználónév vagy hozzáférési token.'
  ].join('\n');
}
