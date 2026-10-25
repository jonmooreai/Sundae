// Turns a cell, a day and the places around the cell into three ideas. Pure and deterministic:
// the same inputs give the same ideas on every edge, with nothing stored.

import { center, distanceMeters } from './geohash.js';

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
      { text: 'Have the first coffee of the day at {name}.', reason: 'Sit by the window. Photograph the cup, then whatever is outside the glass.' },
      { text: 'Finally go into {name}.', reason: 'You walk past it every day. Order what the person ahead of you ordered.' },
    ],
    afternoon: [
      { text: 'Take your afternoon slump to {name}.', reason: 'One table, one hour, no laptop. Shoot the light on the table at the end.' },
    ],
    evening: [
      { text: 'Get a decaf and a slice at {name} before it closes.', reason: 'Closing-time cafés are the quietest rooms in town. Photograph the chairs going up.' },
    ],
  },
  bakery: {
    morning: [
      { text: 'Be first in line at {name}.', reason: 'The bread comes out around now. Shoot the steam, the paper bags, the person ahead of you.' },
      { text: 'Buy something still warm at {name}.', reason: 'Eat it on the step outside. The photo is the crumbs.' },
    ],
    afternoon: [
      { text: 'Pick up tomorrow’s breakfast at {name}.', reason: 'Get the thing you never get. Photograph it before anyone else sees it.' },
    ],
    evening: [],
  },
  park: {
    morning: [
      { text: 'Walk {name} before the dog people leave.', reason: 'Low sun, long shadows, a bench to drink coffee on. Take the wide shot and one detail.' },
    ],
    afternoon: [
      { text: 'Lie on the grass at {name} for twenty minutes.', reason: 'Phone face down, then one photo straight up. That is the whole assignment.' },
      { text: 'Read a chapter at {name}.', reason: 'Bring the book you keep not finishing. Shoot the page and the view past it.' },
    ],
    evening: [
      { text: 'Catch the last light at {name}.', reason: 'Ten minutes of color. Bring someone, or shoot the people who did.' },
    ],
  },
  viewpoint: {
    morning: [
      { text: 'See the city wake up from {name}.', reason: 'Get there early enough to watch the lights go off. One frame, then put the phone away.' },
    ],
    afternoon: [
      { text: 'Walk up to {name} and look at where you live.', reason: 'Find your street from up there. Photograph the direction of home.' },
    ],
    evening: [
      { text: 'Catch the sunset from {name}.', reason: 'Fifteen minutes uphill, ten minutes of color. Bring someone.' },
    ],
  },
  library: {
    morning: [],
    afternoon: [
      { text: 'Spend an hour at {name}.', reason: 'Find the oldest book on the shelf nearest the window. Photograph the spine, not the cover.' },
      { text: 'Get a library card at {name}, or use the one you have.', reason: 'Borrow something on a whim. Shoot the stamp or the due date.' },
    ],
    evening: [],
  },
  bookstore: {
    morning: [],
    afternoon: [
      { text: 'Buy a book you have never heard of at {name}.', reason: 'Pick by the first sentence. Photograph it in your hands, outside the shop.' },
    ],
    evening: [
      { text: 'Browse {name} until they turn the lights down.', reason: 'The staff picks shelf is the review. Shoot the handwritten cards.' },
    ],
  },
  market: {
    morning: [
      { text: 'Buy one thing you cannot name at {name}.', reason: 'Ask what it is. Shoot it at home before you cook it.' },
    ],
    afternoon: [
      { text: 'Make dinner only from what you find at {name}.', reason: 'Three ingredients, no list. Photograph the haul on the counter.' },
    ],
    evening: [],
  },
  museum: {
    morning: [],
    afternoon: [
      { text: 'Go see one room at {name}.', reason: 'One room, not the whole place. Photograph the thing you looked at longest.' },
    ],
    evening: [
      { text: 'See if {name} is open late tonight.', reason: 'Empty galleries after dark are a different museum. Shoot a guard, politely.' },
    ],
  },
  gallery: {
    morning: [],
    afternoon: [
      { text: 'Walk into {name} like you meant to.', reason: 'It is free and nobody will ask you anything. Photograph the floor and one wall.' },
    ],
    evening: [
      { text: 'Check whether {name} has an opening tonight.', reason: 'Free wine, strangers, art. Shoot the crowd, not the work.' },
    ],
  },
  garden: {
    morning: [
      { text: 'Walk through {name} while it is still wet.', reason: 'Everything looks better before ten. Photograph one plant you cannot name.' },
    ],
    afternoon: [
      { text: 'Find a bench at {name} and stay put.', reason: 'Half an hour, one spot. Shoot what changes.' },
    ],
    evening: [],
  },
  trail: {
    morning: [
      { text: 'Do the first mile of {name} before work.', reason: 'Out and back, no summit. Photograph the turnaround point.' },
    ],
    afternoon: [
      { text: 'Walk {name} until the phone has no signal.', reason: 'Then one photo and turn around. The photo is the proof.' },
    ],
    evening: [],
  },
  waterfront: {
    morning: [
      { text: 'Walk the water at {name} before anyone is out.', reason: 'Flat light, gulls, somebody fishing. Shoot the horizon low in the frame.' },
    ],
    afternoon: [],
    evening: [
      { text: 'Walk to the end of {name} and back.', reason: 'The lights come on behind you on the way back. That is the photo.' },
    ],
  },
  diner: {
    morning: [
      { text: 'Have breakfast at the counter at {name}.', reason: 'Order eggs however the person next to you did. Photograph the mug, not the plate.' },
    ],
    afternoon: [],
    evening: [
      { text: 'Eat at {name}, at the counter, alone or not.', reason: 'The line is the review. Shoot the counter, the specials board, the faces.' },
    ],
  },
  record_store: {
    morning: [],
    afternoon: [
      { text: 'Flip through the dollar bin at {name}.', reason: 'Pick the cover that makes you laugh. Shoot it in your hands, out on the sidewalk.' },
    ],
    evening: [
      { text: 'Ask the person at {name} what they are playing.', reason: 'Buy it if you can. Photograph the sleeve under the shop lights.' },
    ],
  },
  ice_cream: {
    morning: [],
    afternoon: [
      { text: 'Get the flavor you would never get at {name}.', reason: 'Eat it walking. Photograph the last bite, the cone, the sidewalk.' },
    ],
    evening: [
      { text: 'Walk to {name} after dinner.', reason: 'The after-dinner walk is the point; the cone is the excuse. Shoot the queue.' },
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
    .filter((p) => p && p.name && THEMES[p.category])
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
  return ideas;
}
