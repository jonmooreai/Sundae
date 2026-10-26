// Turns a cell, a day and the places around the cell into three ideas. Pure and deterministic:
// the same inputs give the same ideas on every edge, with nothing stored.

import { center, distanceMeters } from './geohash.js';
import { isSafeIdea, isSafePlace, makesNoBusinessClaims } from './guard.js';

/** A walk, in meters: the cell plus a fifteen-minute walk. */
export const WALK_METERS = 1200;
/** Worth the trip: twenty miles. */
export const RADIUS_METERS = 32187;

/** Meters per minute on foot, for the "about 8 minutes" line. */
const WALK_PACE = 80;

/**
 * What to do at each kind of place, by time of day. {name} is the place. Written once, served
 * millions of times. Every line is something you could photograph.
 */
export const THEMES = {
  cafe: {
    morning: [
      { text: "Get a drink you've never ordered at {name}.", reason: 'Take a photo of the cup before the first sip.' },
      { text: 'Take a coffee break at {name}.', reason: 'Ten minutes with no phone, then snap a pic of the view from where you are.' },
    ],
    afternoon: [
      { text: "Get a drink you've never ordered at {name}.", reason: 'Take a photo of the cup before the first sip.' },
      { text: 'Take a coffee break at {name}.', reason: 'Ten minutes with no phone, then snap a pic of the view from where you are.' },
    ],
    evening: [],
  },
  bakery: {
    morning: [
      { text: "Pick something you've never tried at {name}.", reason: 'Take a photo of it before the first bite.' },
      { text: 'Bring a treat from {name} to a friend.', reason: 'Snap a pic of it before you hand it over.' },
    ],
    afternoon: [
      { text: "Pick something you've never tried at {name}.", reason: 'Take a photo of it before the first bite.' },
      { text: 'Bring a treat from {name} to a friend.', reason: 'Snap a pic of it before you hand it over.' },
    ],
    evening: [],
  },
  restaurant: {
    morning: [],
    afternoon: [
      { text: 'Try {name}.', reason: "Order something you've never had. Snap a pic before the first bite." },
      { text: 'Take a friend to {name}.', reason: 'Order two things and share. Take a photo of the table.' },
    ],
    evening: [
      { text: 'Try {name}.', reason: "Order something you've never had. Snap a pic before the first bite." },
      { text: 'Take a friend to {name}.', reason: 'Order two things and share. Take a photo of the table.' },
    ],
  },
  market: {
    morning: [
      { text: "Buy one thing you've never cooked at {name}.", reason: 'Take a photo of it at home before you cook it.' },
      { text: 'Shop for one meal at {name}.', reason: 'Three things, no list. Snap a pic of the haul.' },
    ],
    afternoon: [
      { text: "Buy one thing you've never cooked at {name}.", reason: 'Take a photo of it at home before you cook it.' },
      { text: 'Shop for one meal at {name}.', reason: 'Three things, no list. Snap a pic of the haul.' },
    ],
    evening: [],
  },
  library: {
    morning: [
      { text: 'Spend an hour at {name}.', reason: "Pick a book you'd never choose. Take a photo of the cover." },
      { text: 'Read for a while at {name}.', reason: 'Snap a pic of the page you stopped on.' },
    ],
    afternoon: [
      { text: 'Spend an hour at {name}.', reason: "Pick a book you'd never choose. Take a photo of the cover." },
      { text: 'Read for a while at {name}.', reason: 'Snap a pic of the page you stopped on.' },
    ],
    evening: [],
  },
  museum: {
    morning: [],
    afternoon: [
      { text: 'Spend an hour at {name}.', reason: 'Pick one thing and give it five minutes. Take a photo if photos are allowed.' },
    ],
    evening: [],
  },
  gallery: {
    morning: [],
    afternoon: [
      { text: 'Walk through {name}.', reason: "Find the piece you'd take home. Take a photo if photos are allowed." },
    ],
    evening: [],
  },
  bookstore: {
    morning: [
      { text: 'Browse {name} for twenty minutes.', reason: 'Pick a book by its first sentence. Take a photo of it in your hands.' },
    ],
    afternoon: [
      { text: 'Browse {name} for twenty minutes.', reason: 'Pick a book by its first sentence. Take a photo of it in your hands.' },
    ],
    evening: [],
  },
  record_store: {
    morning: [],
    afternoon: [
      { text: 'Browse the records at {name}.', reason: 'Pick the cover you like most. Snap a pic of it.' },
    ],
    evening: [],
  },
  ice_cream: {
    morning: [],
    afternoon: [
      { text: 'Get something sweet at {name}.', reason: 'Take a photo of it before it melts.' },
    ],
    evening: [
      { text: 'Get something sweet at {name}.', reason: 'Take a photo of it before it melts.' },
    ],
  },
  garden: {
    morning: [
      { text: 'Walk through {name}.', reason: "Take a photo of one plant you can't name." },
    ],
    afternoon: [
      { text: 'Walk through {name}.', reason: "Take a photo of one plant you can't name." },
    ],
    evening: [],
  },
  park: {
    morning: [
      { text: 'Take an early walk at {name}.', reason: 'Low sun and long shadows. Take a photo of the wide view and one small detail.' },
    ],
    afternoon: [
      { text: 'Sit somewhere at {name} for twenty minutes.', reason: "Phone down first. Then snap a pic of what's in front of you." },
      { text: 'Read a chapter at {name}.', reason: 'Bring the book you keep not finishing. Take a photo of the page and the view.' },
    ],
    evening: [
      { text: 'Catch the last light at {name}.', reason: 'Bring a friend and take photos of the sky as it changes.' },
    ],
  },
  trail: {
    morning: [
      { text: "Walk part of {name} and turn back when you're ready.", reason: 'Stay on the marked trail. Take a photo at your turnaround point.' },
    ],
    afternoon: [
      { text: "Walk part of {name} and turn back when you're ready.", reason: 'Stay on the marked trail. Take a photo at your turnaround point.' },
    ],
    evening: [],
  },
  waterfront: {
    morning: [
      { text: 'Walk along the water at {name}.', reason: 'Take a photo with the horizon low in the frame.' },
    ],
    afternoon: [
      { text: 'Walk along the water at {name}.', reason: 'Take a photo with the horizon low in the frame.' },
    ],
    evening: [
      { text: 'Watch the sky change at {name}.', reason: 'Stay for the color after sunset. Take photos every few minutes.' },
    ],
  },
  viewpoint: {
    morning: [
      { text: 'See the morning from {name}.', reason: 'Take one photo, then put the phone away and look.' },
    ],
    afternoon: [
      { text: 'Go to {name} and find your street.', reason: 'Take a photo looking toward home.' },
    ],
    evening: [
      { text: 'Watch the sunset from {name}.', reason: 'Bring a friend. Take photos as the color changes.' },
    ],
  },
};

/** Kinds of place that are businesses: their lines may not assume what the place has. */
export const BUSINESSES = new Set(['cafe', 'bakery', 'restaurant', 'market', 'library', 'museum', 'gallery', 'bookstore', 'record_store', 'ice_cream']);

const SLOTS = ['morning', 'afternoon', 'evening'];

/** A small, fast seeded generator so a (cell, day) pair always picks the same way. */
export function seeded(key) {
  let h = 1779033703 ^ key.length;
  for (let i = 0; i < key.length; i++) {
    h = Math.imul(h ^ key.charCodeAt(i), 3432918353);
    h = (h << 13) | (h >>> 19);
  }
  let state = (h ^ (h >>> 16)) >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function fill(template, place) {
  return template.replaceAll('{name}', place.name);
}

/**
 * @param {string} cell five or six character geohash
 * @param {string} day YYYY-MM-DD, the caller's local date
 * @param {{id:string,name:string,category:string,lat:number,lon:number}[]} places candidates near the cell
 * @returns {object[]} up to three ideas, one per part of the day, in wire shape
 */
export function generate(cell, day, places) {
  const rng = seeded(`${cell}:${day}`);
  const origin = center(cell);
  const nearby = places
    .filter((p) => p && p.name && THEMES[p.category] && isSafePlace(p.name))
    .map((p) => ({ ...p, meters: distanceMeters(origin, p) }))
    .filter((p) => p.meters <= RADIUS_METERS)
    .sort((a, b) => a.meters - b.meters);

  const ideas = [];
  const usedPlaces = new Set();
  const usedCategories = new Set();
  SLOTS.forEach((slot, index) => {
    const candidates = nearby.filter((p) => !usedPlaces.has(p.id) && THEMES[p.category][slot]?.length);
    if (!candidates.length) return;
    // A category not used yet today, then chance. The morning idea stays close to home; the
    // afternoon and evening may be worth the drive.
    const fresh = candidates.filter((p) => !usedCategories.has(p.category));
    const ranked = fresh.length ? fresh : candidates;
    const pool = index === 0 ? ranked.slice(0, 8) : ranked;
    const place = pool[Math.floor(rng() * pool.length)];
    const variants = THEMES[place.category][slot];
    const variant = variants[Math.floor(rng() * variants.length)];
    if (BUSINESSES.has(place.category) && !(makesNoBusinessClaims(variant.text) && makesNoBusinessClaims(variant.reason))) return;
    usedPlaces.add(place.id);
    usedCategories.add(place.category);
    ideas.push({
      // The day and a slot. Never the cell: this id travels with the account when marked done.
      id: `local:${day}:${index}`,
      text: fill(variant.text, place),
      reason: fill(variant.reason, place),
      time_of_day: slot,
      place: {
        name: place.name,
        walk_minutes: place.meters <= WALK_METERS ? Math.max(1, Math.round(place.meters / WALK_PACE)) : null,
        distance_meters: Math.round(place.meters),
        latitude: Math.round(place.lat * 1e5) / 1e5,
        longitude: Math.round(place.lon * 1e5) / 1e5,
      },
    });
  });
  // Last word: anything that fails the guard is dropped, never shown.
  return ideas.filter(isSafeIdea);
}
