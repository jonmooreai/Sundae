// Turns a cell, a day and the places around the cell into three ideas. Pure and deterministic:
// the same inputs give the same ideas on every edge, with nothing stored.

import { center, distanceMeters } from './geohash.js';
import { isSafeIdea, isSafePlace } from './guard.js';

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
      { text: 'Have the first coffee of the day at {name}.', reason: 'Sit by the window. Photograph the cup, then the view outside.' },
      { text: 'Finally go into {name}.', reason: 'You walk past it all the time. Order something you never get.' },
    ],
    afternoon: [
      { text: 'Take your afternoon break at {name}.', reason: 'One table, one hour, no laptop. Photograph the light on the table.' },
    ],
    evening: [
      { text: 'Get a decaf and a slice at {name} before it closes.', reason: 'Closing time is the quietest hour. Photograph the empty chairs.' },
    ],
  },
  bakery: {
    morning: [
      { text: 'Be first in line at {name}.', reason: 'The bread comes out around now. Photograph the steam and the paper bags.' },
      { text: 'Buy something still warm at {name}.', reason: 'Eat it on a bench outside. Photograph the crumbs.' },
    ],
    afternoon: [
      { text: "Pick up tomorrow's breakfast at {name}.", reason: 'Get the thing you never get. Photograph it before the first bite.' },
    ],
    evening: [],
  },
  park: {
    morning: [
      { text: 'Walk {name} early.', reason: 'Low sun, long shadows, a bench for your coffee. Photograph the wide view and one detail.' },
    ],
    afternoon: [
      { text: 'Lie on the grass at {name} for twenty minutes.', reason: 'Phone face down, then one photo straight up at the sky.' },
      { text: 'Read a chapter at {name}.', reason: 'Bring the book you keep not finishing. Photograph the page and the view past it.' },
    ],
    evening: [
      { text: 'Catch the last light at {name}.', reason: 'Ten minutes of color. Bring a friend and photograph the sky.' },
    ],
  },
  viewpoint: {
    morning: [
      { text: 'See the city wake up from {name}.', reason: 'Get there in time to watch the lights go off. One photo, then just look.' },
    ],
    afternoon: [
      { text: 'Go to {name} and look at where you live.', reason: 'Find your street from there. Photograph the direction of home.' },
    ],
    evening: [
      { text: 'Catch the sunset from {name}.', reason: 'Ten minutes of color. Bring a friend.' },
    ],
  },
  library: {
    morning: [],
    afternoon: [
      { text: 'Spend an hour at {name}.', reason: 'Find the oldest book on the shelf nearest the window. Photograph the spine.' },
      { text: 'Get a library card at {name}, or use the one you have.', reason: 'Borrow something on a whim. Photograph the due date slip.' },
    ],
    evening: [],
  },
  bookstore: {
    morning: [
      { text: 'Be the first one into {name}.', reason: 'Quiet aisles, coffee in hand. Buy the book with the best first sentence.' },
    ],
    afternoon: [
      { text: "Buy a book you've never heard of at {name}.", reason: 'Pick it by the first sentence. Photograph it in your hands outside.' },
    ],
    evening: [
      { text: 'Browse {name} before it closes.', reason: 'Start with the staff picks shelf. Photograph the handwritten cards.' },
    ],
  },
  market: {
    morning: [
      { text: "Buy one thing you can't name at {name}.", reason: 'Ask what it is. Photograph it at home before you cook it.' },
    ],
    afternoon: [
      { text: 'Make dinner only from what you find at {name}.', reason: 'Three ingredients, no list. Photograph the haul on the counter.' },
    ],
    evening: [],
  },
  museum: {
    morning: [],
    afternoon: [
      { text: 'Go see one room at {name}.', reason: 'One room, not the whole place. Photograph the piece you looked at longest.' },
    ],
    evening: [
      { text: 'See whether {name} has a late opening this week.', reason: 'Quiet galleries feel like a different museum. Photograph your favorite room.' },
    ],
  },
  gallery: {
    morning: [],
    afternoon: [
      { text: 'Walk into {name} like you meant to.', reason: "It's free and quiet. Photograph the floor and one wall." },
    ],
    evening: [
      { text: 'See whether {name} has an opening this week.', reason: "New work, a good room. Photograph the piece you'd take home." },
    ],
  },
  garden: {
    morning: [
      { text: 'Walk through {name} while it is still wet.', reason: 'Everything looks better before ten. Photograph one plant you cannot name.' },
    ],
    afternoon: [
      { text: 'Find a bench at {name} and stay put.', reason: 'Half an hour, one spot. Photograph what changes.' },
    ],
    evening: [],
  },
  trail: {
    morning: [
      { text: 'Do the first mile of {name} before work.', reason: 'Out and back, no summit. Photograph the turnaround point.' },
    ],
    afternoon: [
      { text: 'Walk {name} for an hour, then turn around.', reason: 'Stay on the marked trail. Photograph the best view on the way back.' },
    ],
    evening: [],
  },
  waterfront: {
    morning: [
      { text: 'Walk along the water at {name}.', reason: 'Flat light and gulls. Keep the horizon low in the photo.' },
    ],
    afternoon: [],
    evening: [
      { text: 'Walk to the end of {name} and back.', reason: 'The lights come on behind you on the way back. That is the photo.' },
    ],
  },
  diner: {
    morning: [
      { text: 'Have breakfast at the counter at {name}.', reason: "Order whatever they're known for. Photograph the mug, not the plate." },
    ],
    afternoon: [],
    evening: [
      { text: 'Have dinner at the counter at {name}.', reason: 'Order the special. Photograph the menu board and your plate.' },
    ],
  },
  record_store: {
    morning: [],
    afternoon: [
      { text: 'Flip through the dollar bin at {name}.', reason: 'Pick the cover that makes you laugh. Photograph it in your hands.' },
    ],
    evening: [
      { text: "Ask what's playing at {name}.", reason: 'Buy it if you can. Photograph the sleeve under the shop lights.' },
    ],
  },
  ice_cream: {
    morning: [],
    afternoon: [
      { text: "Get a flavor you'd never pick at {name}.", reason: 'Eat it walking. Photograph the cone against the sky.' },
    ],
    evening: [
      { text: 'Walk to {name} after dinner.', reason: 'The walk is the point and the cone is the excuse. Photograph the sign.' },
    ],
  },
};

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
