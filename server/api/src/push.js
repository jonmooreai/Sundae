// Push notifications through Apple (APNs), from the Worker, with no dependencies.
//
// Apple takes a signed token (ES256, the .p8 key from the developer account) that is good for
// an hour, and one HTTPS request per device. Three secrets configure it (docs/SERVER.md):
// APNS_KEY (the .p8 file's text), APNS_KEY_ID and APNS_TEAM_ID. Without them nothing is sent
// and nothing fails: the app still shows everything in its Notifications tab.

import { b64url } from './crypto.js';

// Apple asks for a new token at most every twenty minutes and at least every hour.
const TOKEN_LIFETIME_MS = 50 * 60 * 1000;
const HOSTS = { production: 'https://api.push.apple.com', sandbox: 'https://api.sandbox.push.apple.com' };

const cache = new Map();

/** True when the three secrets are there. */
export function pushConfigured(env) {
  return Boolean(env.APNS_KEY && env.APNS_KEY_ID && env.APNS_TEAM_ID);
}

function pemToDer(pem) {
  const base64 = String(pem).replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const bytes = atob(base64);
  const out = new Uint8Array(bytes.length);
  for (let i = 0; i < bytes.length; i++) out[i] = bytes.charCodeAt(i);
  return out;
}

/** The provider token for this key, made once and kept for fifty minutes. */
async function providerToken(env, now) {
  const kept = cache.get(env.APNS_KEY_ID);
  if (kept && now - kept.at < TOKEN_LIFETIME_MS) return kept.token;
  const key = await crypto.subtle.importKey('pkcs8', pemToDer(env.APNS_KEY), { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const enc = new TextEncoder();
  const header = b64url(enc.encode(JSON.stringify({ alg: 'ES256', kid: env.APNS_KEY_ID })));
  const claims = b64url(enc.encode(JSON.stringify({ iss: env.APNS_TEAM_ID, iat: Math.floor(now / 1000) })));
  const signature = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, enc.encode(`${header}.${claims}`));
  const token = `${header}.${claims}.${b64url(new Uint8Array(signature))}`;
  cache.set(env.APNS_KEY_ID, { token, at: now });
  return token;
}

/** For tests: forget the kept token. */
export function resetPushCache() {
  cache.clear();
}

/**
 * One notification to each device given. `alert` is `{ title, body }` (body optional) and `data`
 * travels alongside for the app to open the right screen. Returns the tokens Apple says are gone
 * (the app was deleted, or the token is stale), for the caller to remove.
 */
export async function sendPush(env, devices, { alert, data = {}, thread = 'sundae', collapse = null }, now = Date.now()) {
  if (!pushConfigured(env) || !devices.length) return [];
  const fetchFn = env.FETCH || globalThis.fetch;
  const topic = env.APPLE_BUNDLE_ID || 'com.jonmooreai.sundae';
  let token;
  try {
    token = await providerToken(env, now);
  } catch (error) {
    console.error('push: the APNs key could not be read', error?.message || error);
    return [];
  }
  const payload = JSON.stringify({ aps: { alert, sound: 'default', 'thread-id': thread }, ...data });
  const gone = [];
  await Promise.all(devices.map(async (device) => {
    const host = HOSTS[device.environment] || HOSTS.production;
    const headers = {
      authorization: `bearer ${token}`,
      'apns-topic': topic,
      'apns-push-type': 'alert',
      'apns-priority': '10',
      'apns-expiration': String(Math.floor(now / 1000) + 24 * 3600),
      'content-type': 'application/json',
    };
    if (collapse) headers['apns-collapse-id'] = collapse;
    try {
      const response = await fetchFn(`${host}/3/device/${device.token}`, { method: 'POST', headers, body: payload });
      if (response.status === 200) return;
      let reason = '';
      try { reason = (await response.json())?.reason || ''; } catch { /* no body */ }
      if (response.status === 410 || reason === 'BadDeviceToken' || reason === 'Unregistered' || reason === 'DeviceTokenNotForTopic') {
        gone.push(device.token);
      } else {
        console.error('push: Apple answered', response.status, reason);
      }
    } catch (error) {
      console.error('push: could not reach Apple', error?.message || error);
    }
  }));
  return gone;
}
