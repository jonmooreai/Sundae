// Geohash, the same algorithm as Shared/Geohash.swift in the app. No dependencies.

const BASE32 = '0123456789bcdefghjkmnpqrstuvwxyz';

/** A cell the app would send: five or six base32 characters. */
export function isValidCell(value) {
  return /^[0-9b-hj-km-np-z]{5,6}$/.test(value);
}

export function encode(latitude, longitude, precision) {
  const lat = Math.min(Math.max(latitude, -90), 90);
  const lon = Math.min(Math.max(longitude, -180), 180);
  let latLow = -90, latHigh = 90, lonLow = -180, lonHigh = 180;
  let hash = '', bits = 0, value = 0, even = true;
  while (hash.length < Math.max(precision, 1)) {
    if (even) {
      const mid = (lonLow + lonHigh) / 2;
      if (lon >= mid) { value = value * 2 + 1; lonLow = mid; } else { value *= 2; lonHigh = mid; }
    } else {
      const mid = (latLow + latHigh) / 2;
      if (lat >= mid) { value = value * 2 + 1; latLow = mid; } else { value *= 2; latHigh = mid; }
    }
    even = !even;
    if (++bits === 5) { hash += BASE32[value]; bits = 0; value = 0; }
  }
  return hash;
}

/** The box a cell covers. */
export function bounds(hash) {
  let latLow = -90, latHigh = 90, lonLow = -180, lonHigh = 180, even = true;
  for (const ch of hash.toLowerCase()) {
    const index = BASE32.indexOf(ch);
    if (index < 0) throw new Error(`bad geohash ${hash}`);
    for (let bit = 4; bit >= 0; bit--) {
      const on = (index >> bit) & 1;
      if (even) {
        const mid = (lonLow + lonHigh) / 2;
        if (on) lonLow = mid; else lonHigh = mid;
      } else {
        const mid = (latLow + latHigh) / 2;
        if (on) latLow = mid; else latHigh = mid;
      }
      even = !even;
    }
  }
  return { latLow, latHigh, lonLow, lonHigh };
}

export function center(hash) {
  const b = bounds(hash);
  return { lat: (b.latLow + b.latHigh) / 2, lon: (b.lonLow + b.lonHigh) / 2 };
}

/** Meters between two points. Good enough for walking distances. */
export function distanceMeters(a, b) {
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLon = toRad(b.lon - a.lon);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLon / 2) ** 2;
  return 2 * 6371000 * Math.asin(Math.sqrt(h));
}
