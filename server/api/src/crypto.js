// Tokens, signatures and Sign in with Apple, all with Web Crypto. No dependencies.

const encoder = new TextEncoder();

export function b64url(bytes) {
  let s = '';
  const view = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  for (let i = 0; i < view.length; i += 0x8000) s += String.fromCharCode(...view.subarray(i, i + 0x8000));
  return btoa(s).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
}

export function fromB64url(text) {
  const s = atob(text.replaceAll('-', '+').replaceAll('_', '/') + '='.repeat((4 - (text.length % 4)) % 4));
  const out = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
  return out;
}

export function randomToken(bytes = 32) {
  return b64url(crypto.getRandomValues(new Uint8Array(bytes)));
}

const ALPHABET = '0123456789abcdefghjkmnpqrstvwxyz';
export function newId(prefix) {
  const bytes = crypto.getRandomValues(new Uint8Array(12));
  return `${prefix}_${[...bytes].map((b) => ALPHABET[b % 32]).join('')}`;
}

export async function sha256Hex(text) {
  const digest = await crypto.subtle.digest('SHA-256', encoder.encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

async function hmacKey(secret) {
  return crypto.subtle.importKey('raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign', 'verify']);
}

export async function hmac(secret, message) {
  return b64url(await crypto.subtle.sign('HMAC', await hmacKey(secret), encoder.encode(message)));
}

/** Compares two strings without leaking where they differ. */
export function sameString(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/** A short signed token: base64url(JSON payload) + "." + HMAC. */
export async function signToken(payload, secret) {
  const body = b64url(encoder.encode(JSON.stringify(payload)));
  return `${body}.${await hmac(secret, body)}`;
}

export async function verifyToken(token, secret, now = Date.now()) {
  if (typeof token !== 'string' || !token.includes('.')) return null;
  const [body, sig] = token.split('.');
  if (!sameString(sig, await hmac(secret, body))) return null;
  try {
    const payload = JSON.parse(new TextDecoder().decode(fromB64url(body)));
    if (typeof payload.exp !== 'number' || payload.exp * 1000 <= now) return null;
    return payload;
  } catch {
    return null;
  }
}

// MARK: Sign in with Apple

let appleKeys = { keys: null, at: 0 };

async function defaultFetchKeys() {
  if (appleKeys.keys && Date.now() - appleKeys.at < 3600_000) return appleKeys.keys;
  const response = await fetch('https://appleid.apple.com/auth/keys');
  if (!response.ok) throw new Error('apple keys unavailable');
  const { keys } = await response.json();
  appleKeys = { keys, at: Date.now() };
  return keys;
}

/**
 * Checks an identity token from Sign in with Apple: Apple's signature, issuer, audience
 * (this app's bundle id) and expiry. Returns the stable user id (`sub`) or null.
 */
export async function verifyAppleIdentityToken(token, { bundleId, fetchKeys = defaultFetchKeys, now = Date.now() } = {}) {
  try {
    const [h, p, s] = token.split('.');
    const header = JSON.parse(new TextDecoder().decode(fromB64url(h)));
    const payload = JSON.parse(new TextDecoder().decode(fromB64url(p)));
    if (header.alg !== 'RS256') return null;
    const jwk = (await fetchKeys()).find((k) => k.kid === header.kid);
    if (!jwk) return null;
    const key = await crypto.subtle.importKey('jwk', jwk, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
    const ok = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, fromB64url(s), encoder.encode(`${h}.${p}`));
    if (!ok) return null;
    if (payload.iss !== 'https://appleid.apple.com') return null;
    const audiences = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
    if (!audiences.includes(bundleId)) return null;
    if (typeof payload.exp !== 'number' || payload.exp * 1000 <= now) return null;
    return typeof payload.sub === 'string' && payload.sub ? payload.sub : null;
  } catch {
    return null;
  }
}
