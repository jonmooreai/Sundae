// The same checks as Shared/IdeaGuard.swift in the app. A test keeps the two lists identical.
// Every idea the server returns passes these: nothing violent, nothing aimed at strangers,
// kids or staff, no alcohol or drugs, nothing risky, and never a solemn or sensitive place.

export const BLOCKED_WORDS = new Set([
  'shoot', 'shoots', 'shooting', 'shot', 'shots', 'gun', 'guns', 'rifle', 'pistol', 'weapon', 'weapons',
  'kill', 'kills', 'killing', 'murder', 'stab', 'knife', 'knives', 'bomb', 'bombs', 'explode', 'explosion',
  'attack', 'fight', 'fighting', 'punch', 'hunt', 'hunting', 'blood', 'bleed', 'dead', 'death', 'die',
  'dying', 'corpse', 'war', 'wars', 'battle', 'target', 'trigger', 'ammo', 'hostage', 'victim', 'victims',
  'guard', 'guards', 'stranger', 'strangers', 'crowd', 'crowds', 'faces', 'kid', 'kids', 'child',
  'children', 'toddler', 'baby', 'babies', 'teen', 'teens',
  'wine', 'beer', 'beers', 'cocktail', 'cocktails', 'drunk', 'alcohol', 'booze', 'liquor',
  'drug', 'drugs', 'weed', 'smoke', 'smoking', 'vape',
  'trespass', 'trespassing', 'sneak', 'dare', 'cliff', 'cliffs', 'tracks', 'rooftop', 'roof',
  'memorial', 'cemetery', 'grave', 'graves', 'funeral', 'hospital', 'prison', 'jail',
  'capture', 'captures', 'capturing', 'photograph', 'photographs', 'photographing', 'photographed',
  'snap', 'snaps', 'snapping',
]);

/** The only ways an idea may ask for a picture; removed before the word check. */
export const APPROVED_PHOTO_PHRASES = ['take a photograph', 'take photographs', 'snap a pic'];

/** Words a line about a business may not use: it might not have the thing, or not be open. */
export const BUSINESS_CLAIM_WORDS = new Set([
  'breakfast', 'brunch', 'lunch', 'dinner', 'supper', 'counter', 'counters', 'mug', 'mugs', 'menu',
  'menus', 'special', 'specials', 'booth', 'booths', 'window', 'windows', 'patio', 'closing',
  'closes', 'close', 'open', 'opens', 'opening', 'late', 'tonight', 'early', 'warm', 'fresh', 'hot',
  'line', 'queue', 'staff', 'barista', 'chef', 'owner', 'famous', 'known', 'best', 'favorite',
]);

export const BLOCKED_PHRASES = [
  'no signal', 'alone at night', 'after dark alone', 'photo of them', 'photograph them',
  'the person ahead', 'people who', "someone you don't know", 'open fire', 'fire at',
  'photograph the staff', 'photograph the cashier', 'photograph the line', 'photograph the queue',
];

export const SENSITIVE_PLACE_WORDS = new Set([
  'memorial', 'memorials', 'monument', 'cemetery', 'cemeteries', 'graveyard', 'grave', 'tomb',
  'mausoleum', 'crypt', 'funeral', 'mortuary', 'crematory', 'crematorium', 'burial',
  'church', 'cathedral', 'chapel', 'basilica', 'mosque', 'masjid', 'synagogue', 'temple', 'shrine',
  'parish', 'abbey', 'monastery', 'gurdwara',
  'hospital', 'clinic', 'medical', 'hospice', 'emergency', 'urgent', 'rehab', 'rehabilitation',
  'prison', 'jail', 'correctional', 'detention', 'penitentiary', 'courthouse', 'court',
  'police', 'sheriff', 'military', 'armory', 'army', 'navy', 'marine', 'marines', 'veteran',
  'veterans', 'va', 'war', 'battlefield', 'holocaust', 'genocide', 'massacre', 'remembrance',
  'school', 'elementary', 'kindergarten', 'preschool', 'daycare', 'shelter',
]);

/** Letters only, so "Warwick Park" is "warwick" and "park", never "war". */
export function words(text) {
  return new Set(
    text.toLowerCase()
      .split(/[^\p{L}']+/u)
      .map((w) => w.replaceAll("'s", '').replaceAll("'", ''))
      .filter(Boolean),
  );
}

export function isSafeText(text) {
  let lower = text.toLowerCase();
  if (BLOCKED_PHRASES.some((p) => lower.includes(p))) return false;
  for (const phrase of APPROVED_PHOTO_PHRASES) lower = lower.replaceAll(phrase, ' ');
  for (const w of words(lower)) if (BLOCKED_WORDS.has(w)) return false;
  return true;
}

export function makesNoBusinessClaims(text) {
  for (const w of words(text)) if (BUSINESS_CLAIM_WORDS.has(w)) return false;
  return true;
}

export function isSafePlace(name) {
  for (const w of words(name)) if (SENSITIVE_PLACE_WORDS.has(w)) return false;
  return true;
}

export function isSafeIdea(idea) {
  return isSafeText(idea.text) && isSafeText(idea.reason) && (!idea.place || isSafePlace(idea.place.name));
}
