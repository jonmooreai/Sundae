// The second line behind the app's own re-encode: every photo loses EXIF (GPS, camera, time),
// XMP, IPTC and comments before it is stored. Only headers are walked; the image data after the
// start-of-scan marker is copied as is, and only its FF bytes are looked at, so this costs almost
// no CPU.
//
// It also refuses frames bigger than the app ever sends (2048 px photos, 600 px avatars). A
// phone decodes a photo at full size, so a small, very compressible file 20000 px across would
// need gigabytes of memory to show.

const SOS = 0xda;
const EOI = 0xd9;
const DNL = 0xdc;
const COM = 0xfe;
const APP2 = 0xe2;
const APP14 = 0xee;
const MAX_SIDE = 4096;

/** The start-of-frame markers, which carry the image's size: C0 to CF, except DHT, JPG and DAC. */
const isFrame = (marker) => marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc;

function isIccProfile(bytes, at) {
  const tag = 'ICC_PROFILE';
  for (let i = 0; i < tag.length; i++) if (bytes[at + i] !== tag.charCodeAt(i)) return false;
  return true;
}

/** Keeps JFIF (APP0), the color profile (APP2 ICC) and Adobe color info (APP14). Drops every other
 * APP segment and comments. Returns null when the bytes are not a well-formed JPEG of one frame,
 * up to MAX_SIDE each way. */
export function stripJpegMetadata(bytes) {
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8) return null;
  const kept = [bytes.subarray(0, 2)];
  let framed = false;
  let i = 2;
  while (i + 4 <= bytes.length) {
    if (bytes[i] !== 0xff) return null;
    const marker = bytes[i + 1];
    if (marker === 0xff) { i += 1; continue; }
    if (marker === SOS) {
      if (!framed || !oneFrame(bytes, i + 2 + ((bytes[i + 2] << 8) | bytes[i + 3]))) return null;
      kept.push(bytes.subarray(i));
      return concat(kept);
    }
    const length = (bytes[i + 2] << 8) | bytes[i + 3];
    const end = i + 2 + length;
    if (length < 2 || end > bytes.length) return null;
    if (isFrame(marker)) {
      // Height, then width. A height of 0 would be given later, after the scan, past this check.
      const height = (bytes[i + 5] << 8) | bytes[i + 6];
      const width = (bytes[i + 7] << 8) | bytes[i + 8];
      if (framed || length < 8 || !width || !height || width > MAX_SIDE || height > MAX_SIDE) return null;
      framed = true;
    }
    const isApp = marker >= 0xe1 && marker <= 0xef;
    const keep = marker !== COM && (!isApp || marker === APP14 || (marker === APP2 && isIccProfile(bytes, i + 4)));
    if (keep) kept.push(bytes.subarray(i, end));
    i = end;
  }
  return null;
}

/** Whether the rest of the image, up to its end marker, has no second frame and no DNL (a height
 * given after the scan). Image data never holds a bare FF, which is written FF 00, so only the
 * FF bytes need looking at, and any other marker heads a segment to step over. */
function oneFrame(bytes, from) {
  let k = from;
  while ((k = bytes.indexOf(0xff, k)) !== -1 && k + 1 < bytes.length) {
    const marker = bytes[k + 1];
    if (marker === EOI) return true;
    if (isFrame(marker) || marker === DNL) return false;
    if (marker === 0x00 || marker === 0xff || (marker >= 0xd0 && marker <= 0xd7)) k += 1;
    else k += 2 + ((bytes[k + 2] << 8) | bytes[k + 3]);
  }
  return true;
}

function concat(parts) {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let offset = 0;
  for (const p of parts) { out.set(p, offset); offset += p.length; }
  return out;
}
