const test = require('node:test');
const assert = require('node:assert/strict');
const app = require('../src/server');

let server;
let baseUrl;

test.before(async () => {
  server = app.listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

test.after(() => server.close());

test('/health responde "¡Ya estoy aquí!"', async () => {
  const res = await fetch(`${baseUrl}/health`);
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.status, 'ok');
  assert.equal(body.message, '¡Ya estoy aquí!');
});

test('/api/version devuelve el héroe actual', async () => {
  const res = await fetch(`${baseUrl}/api/version`);
  const body = await res.json();
  assert.ok(body.hero);
  assert.ok(body.version);
});

test('Solo se aceptan votos "pasa" o "rompe"', async () => {
  const bad = await fetch(`${baseUrl}/api/vote`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ choice: 'tal vez' }),
  });
  assert.equal(bad.status, 400);

  const ok = await fetch(`${baseUrl}/api/vote`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ choice: 'pasa' }),
  });
  const body = await ok.json();
  assert.equal(body.pasa, 1);
});
