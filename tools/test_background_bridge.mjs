// Test the actual embedded JS bridge's listener/timer lifecycle without a browser.
// This does NOT simulate or establish Chrome's background scheduling guarantees.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const source = readFileSync(new URL('../networking/web_presence.gd', import.meta.url), 'utf8');
const js = source.match(/const JS := """\n([\s\S]*?)\n"""/)[1];
for (const disabled of [false, true]) {
  const listeners = new Map();
  let timer;
  const document = {
    hidden: false,
    addEventListener: (name, fn) => listeners.set(name, fn),
    removeEventListener: (name, fn) => {
      assert.equal(listeners.get(name), fn);
      listeners.delete(name);
    },
  };
  const windowListeners = new Map();
  const window = {
    addEventListener: (name, fn) => windowListeners.set(name, fn),
    removeEventListener: (name, fn) => {
      assert.equal(windowListeners.get(name), fn);
      windowListeners.delete(name);
    },
  };
  const events = [];
  vm.runInNewContext(js, {
    document, window, URLSearchParams,
    location: { search: disabled ? '?background_poll=0' : '' },
    setInterval: (fn, ms) => { assert.equal(ms, 250); timer = fn; return 42; },
    clearInterval: id => { assert.equal(id, 42); timer = undefined; },
  });
  window.gloryBackground.start((...args) => events.push(args));
  assert.deepEqual(events.pop(), ['visibility', false]);
  timer();
  assert.equal(events.length, 0, 'visible tabs do not get a second polling loop');
  document.hidden = true;
  listeners.get('visibilitychange')();
  assert.deepEqual(events.pop(), ['visibility', true]);
  timer();
  if (disabled) assert.equal(events.length, 0);
  else assert.deepEqual(events.pop(), ['tick', true]);
  listeners.get('freeze')();
  assert.deepEqual(events.pop(), ['freeze', true]);
  document.hidden = false;
  listeners.get('visibilitychange')();
  assert.deepEqual(events.pop(), ['visibility', false]);
  windowListeners.get('pagehide')({ persisted: true });
  assert.equal(events.length, 0, 'bfcache navigation keeps the session');
  windowListeners.get('pagehide')({ persisted: false });
  assert.deepEqual(events.pop(), ['pagehide', false]);
  window.gloryBackground.report('{"polls":7}');
  assert.equal(window.gloryNetworkDiagnostics.polls, 7);
  window.gloryBackground.stop();
  assert.equal(listeners.size, 0);
  assert.equal(windowListeners.size, 0);
  assert.equal(timer, undefined);
}
console.log('PASS: JS bridge visibility, timer ownership, freeze, pagehide, diagnostics, A/B disable, cleanup');
