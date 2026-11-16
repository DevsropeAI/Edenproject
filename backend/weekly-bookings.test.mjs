import { test } from 'node:test';
import assert from 'node:assert/strict';
import { nextWeeklyTime } from './weekly-bookings.mjs';

test('weekly bookings are created in the lead window and skip missed dates', () => {
  const original = '2026-11-01T12:00:00Z';
  assert.equal(nextWeeklyTime(original, Date.parse('2026-11-06T12:00:00Z')), null);
  assert.equal(nextWeeklyTime(original, Date.parse('2026-11-07T12:00:00Z')), Date.parse('2026-11-08T12:00:00Z'));
  assert.equal(nextWeeklyTime(original, Date.parse('2026-11-21T15:00:00Z')), Date.parse('2026-11-22T12:00:00Z'));
});
