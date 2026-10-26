// The second line behind the app's own re-encode: every photo loses EXIF (GPS, camera, time),
// XMP, IPTC and comments before it is stored. Only headers are walked; the image data after the
// start-of-scan marker is copied as is, so this costs almost no CPU.

const SOS = 0xda;
const COM = 0xfe;
const APP2 = 0xe2;
const APP14 = 0xee;

function isIccProfile(bytes, at) {
  const tag = 'ICC_PROFILE';
  for (let i = 0; i < tag.length; i++) if (bytes[at + i] !== tag.charCodeAt(i)) return false;
  return true;
}

/** Keeps JFIF (APP0), the color profile (APP2 ICC) and Adobe color info (APP14). Drops every other
 * APP segment and comments. Returns null when the bytes are not a well-formed JPEG. */
export function stripJpegMetadata(bytes) {
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8) return null;
  const kept = [bytes.subarray(0, 2)];
  let i = 2;
  while (i + 4 <= bytes.length) {
    if (bytes[i] !== 0xff) return null;
    const marker = bytes[i + 1];
    if (marker === 0xff) { i += 1; continue; }
    if (marker === SOS) {
      kept.push(bytes.subarray(i));
      return concat(kept);
    }
    const length = (bytes[i + 2] << 8) | bytes[i + 3];
    const end = i + 2 + length;
    if (length < 2 || end > bytes.length) return null;
    const isApp = marker >= 0xe1 && marker <= 0xef;
    const keep = marker !== COM && (!isApp || marker === APP14 || (marker === APP2 && isIccProfile(bytes, i + 4)));
    if (keep) kept.push(bytes.subarray(i, end));
    i = end;
  }
  return null;
}

function concat(parts) {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let offset = 0;
  for (const p of parts) { out.set(p, offset); offset += p.length; }
  return out;
}
