const test = require('node:test');
const assert = require('node:assert/strict');
const { powerLevel, isValidRelease } = require('../src/hero');
const release = require('../src/release.json');

test('Deku al 50% usa el 50% de su poder', () => {
  assert.equal(powerLevel(50), 50);
});

test('Deku nunca pasa del 100% (o se rompe los brazos)', () => {
  assert.equal(powerLevel(150), 100);
});

test('El poder nunca es negativo', () => {
  assert.equal(powerLevel(-20), 0);
});

test('La release tiene héroe, versión semántica y poder', () => {
  assert.ok(isValidRelease(release), 'release.json inválido');
});
