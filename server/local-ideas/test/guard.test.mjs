import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { APPROVED_PHOTO_PHRASES, BLOCKED_PHRASES, BLOCKED_WORDS, BUSINESS_CLAIM_WORDS, SENSITIVE_PLACE_WORDS, isSafePlace, isSafeText, makesNoBusinessClaims } from '../src/guard.js';
import { BUSINESSES, THEMES, generate } from '../src/ideas.js';
import { center } from '../src/geohash.js';

const here = path.dirname(fileURLToPath(import.meta.url));

test('the lines that must never appear are refused', () => {
  for (const line of [
    'Shoot a guard, politely.',
    'Free wine, strangers, art. Shoot the crowd, not the work.',
    'Shoot the counter, the specials board, the faces.',
    'Walk the trail until the phone has no signal.',
    'Order what the person ahead of you ordered.',
    'Catch the last light. Bring someone, or shoot the people who did.',
    'A parking garage roof counts.',
    'Photograph the steam and the paper bags.',
    'Capture the light on the table.',
    'Snap the menu board.',
  ]) {
    assert.equal(isSafeText(line), false, line);
  }
});

test('business lines may not assume meals, hours, counters or menus', () => {
  for (const line of ['Have breakfast at the counter at Chicken Salad Chick.', 'Photograph the mug, not the plate.',
    'Order the special.', 'See whether it is open late tonight.', 'The bread comes out around now. Be first in line.']) {
    assert.equal(makesNoBusinessClaims(line), false, line);
  }
  assert.equal(makesNoBusinessClaims('Try Chicken Salad Chick.'), true);
});

test('ordinary lines pass', () => {
  for (const line of [
    'Take a photo of the steam.',
    'Take photos as the color changes.',
    'Take a photograph of the view.',
    'Snap a pic of it before you hand it over.',
    'Watch the sunset from somewhere high.',
  ]) {
    assert.equal(isSafeText(line), true, line);
  }
});

test('solemn and sensitive places are never used', () => {
  for (const name of ['Indiana War Memorials', 'Crown Hill Cemetery', "St. Mary's Church", 'Riley Children’s Hospital',
    'Lincoln Memorial', 'Holocaust Museum', 'Marion County Jail', 'Veterans Park', 'Oak Elementary School']) {
    assert.equal(isSafePlace(name), false, name);
  }
  for (const name of ['Warwick Park', 'Tartine Bakery', 'Newfields', 'Mission Dolores Park', 'Central Library']) {
    assert.equal(isSafePlace(name), true, name);
  }
});

test('every line the server can write passes, whatever the place is called', () => {
  for (const [category, slots] of Object.entries(THEMES)) {
    for (const [slot, lines] of Object.entries(slots)) {
      for (const line of lines) {
        for (const name of ['Tartine', 'The Corner Spot', 'Riverside']) {
          for (const text of [line.text, line.reason]) {
            assert.equal(isSafeText(text.replaceAll('{name}', name)), true, `${category}/${slot}: ${text}`);
            if (BUSINESSES.has(category)) assert.equal(makesNoBusinessClaims(text), true, `${category}/${slot} claims: ${text}`);
          }
        }
      }
    }
  }
});

test('a war memorial nearby is skipped, the bakery next to it is used', () => {
  const cell = '9q8yyk';
  const c = center(cell);
  const places = [
    { id: 'm', name: 'Indiana War Memorials', category: 'museum', lat: c.lat + 0.0005, lon: c.lon },
    { id: 'b', name: 'Tartine Bakery', category: 'bakery', lat: c.lat + 0.001, lon: c.lon },
  ];
  const ideas = generate(cell, '2026-10-21', places);
  assert.ok(ideas.length >= 1);
  assert.ok(ideas.every((i) => !i.place.name.includes('Memorial')));
});

test('the server and the app hold the same lists', () => {
  const swift = readFileSync(path.join(here, '../../../Shared/IdeaGuard.swift'), 'utf8');
  const list = (name) => {
    const start = swift.indexOf(`static let ${name}`);
    const open = swift.indexOf('= [', start) + 2;
    const end = swift.indexOf(']', open + 1);
    return [...swift.slice(open, end).matchAll(/"([^"]+)"/g)].map((m) => m[1]);
  };
  assert.deepEqual(new Set(list('blockedWords')), BLOCKED_WORDS);
  assert.deepEqual(list('blockedPhrases'), BLOCKED_PHRASES);
  assert.deepEqual(new Set(list('sensitivePlaceWords')), SENSITIVE_PLACE_WORDS);
  assert.deepEqual(list('approvedPhotoPhrases'), APPROVED_PHOTO_PHRASES);
  assert.deepEqual(new Set(list('businessClaimWords')), BUSINESS_CLAIM_WORDS);
});
