// Week math in each person's own time zone. A week runs Monday 00:00 to Sunday 23:59 local.

const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

export function safeZone(tz) {
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: tz });
    return tz;
  } catch {
    return 'UTC';
  }
}

/** The wall-clock parts of `date` in `tz`. weekday: 0 Sunday to 6 Saturday. */
export function zonedParts(date, tz) {
  const format = new Intl.DateTimeFormat('en-US', {
    timeZone: safeZone(tz), year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23', weekday: 'short',
  });
  const p = Object.fromEntries(format.formatToParts(date).map((x) => [x.type, x.value]));
  return {
    y: Number(p.year), m: Number(p.month), d: Number(p.day),
    hour: Number(p.hour), minute: Number(p.minute), second: Number(p.second),
    weekday: WEEKDAYS.indexOf(p.weekday),
  };
}

const pad = (n) => String(n).padStart(2, '0');

export function localDate(date, tz) {
  const p = zonedParts(date, tz);
  return `${p.y}-${pad(p.m)}-${pad(p.d)}`;
}

export function addDays(day, n) {
  const [y, m, d] = day.split('-').map(Number);
  const t = new Date(Date.UTC(y, m - 1, d + n));
  return `${t.getUTCFullYear()}-${pad(t.getUTCMonth() + 1)}-${pad(t.getUTCDate())}`;
}

export function isValidDay(day) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) return false;
  const [y, m, d] = day.split('-').map(Number);
  const t = new Date(Date.UTC(y, m - 1, d));
  return t.getUTCFullYear() === y && t.getUTCMonth() === m - 1 && t.getUTCDate() === d;
}

/** Monday of the week containing `date`, in `tz`. A Sunday belongs to the week that started six days before. */
export function weekStart(date, tz) {
  const p = zonedParts(date, tz);
  return addDays(`${p.y}-${pad(p.m)}-${pad(p.d)}`, -((p.weekday + 6) % 7));
}

export function isSunday(date, tz) {
  return zonedParts(date, tz).weekday === 0;
}

/** The instant local midnight starts `day` in `tz`. */
export function zonedMidnight(day, tz) {
  const [y, m, d] = day.split('-').map(Number);
  const target = Date.UTC(y, m - 1, d);
  let guess = target;
  for (let i = 0; i < 3; i++) {
    const p = zonedParts(new Date(guess), tz);
    const offset = Date.UTC(p.y, p.m - 1, p.d, p.hour, p.minute, p.second) - guess;
    guess = target - offset;
  }
  return new Date(guess);
}

/** The newest `count` week starts, newest first. */
export function recentWeekStarts(date, tz, count) {
  const first = weekStart(date, tz);
  return Array.from({ length: count }, (_, i) => addDays(first, -7 * i));
}
