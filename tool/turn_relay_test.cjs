// Drives the deployed web build in 1 host + N guest browser contexts with ICE forced through TURN
// (iceTransportPolicy 'relay'), then checks the selected candidate pair type and tile sync.
// Run: NODE_PATH=<dir with playwright>/node_modules [CHROME_BIN=<chromium>] node tool/turn_relay_test.cjs
// Env: APP_URL, GUESTS (1), TOGGLES (10), RELAY (1; 0 = normal ICE), LOCAL_SIGNALLING (0; 1 = PeerServer on 127.0.0.1:9443)
// Prints candidate types and protocols only; never the ICE config, which holds TURN credentials.
const { chromium } = require('playwright');

const APP_URL = process.env.APP_URL || 'https://silvernetgroupsggw.github.io/Bingownia/';
const GUESTS = Number(process.env.GUESTS || 1);
const TOGGLES = Number(process.env.TOGGLES || 10);
const RELAY = process.env.RELAY !== '0';
const LOCAL = process.env.LOCAL_SIGNALLING === '1';
const SIZE = 3;
const board = {
  id: 'turn-test',
  title: 'TURN test',
  size: SIZE,
  tiles: Array.from({ length: SIZE * SIZE }, (_, i) => ({ id: `t${i}`, text: `Pole ${i}`, isChecked: false })),
};

function instrument({ relay, boardJson }) {
  if (boardJson) localStorage.setItem('flutter.saved_bingo_boards', JSON.stringify(boardJson));
  const Orig = window.RTCPeerConnection;
  const msgs = (window.__msgs = []);
  window.__pcs = [];
  const watch = (ch) =>
    ch.addEventListener('message', (e) => {
      if (typeof e.data === 'string') msgs.push({ t: performance.now(), dir: 'in', d: e.data });
    });
  class PC extends Orig {
    constructor(cfg = {}, ...rest) {
      super(relay ? { ...cfg, iceTransportPolicy: 'relay' } : cfg, ...rest);
      window.__pcs.push(this);
      this.addEventListener('datachannel', (e) => watch(e.channel));
    }
    createDataChannel(...args) {
      const ch = super.createDataChannel(...args);
      watch(ch);
      return ch;
    }
  }
  window.RTCPeerConnection = PC;
  const send = RTCDataChannel.prototype.send;
  RTCDataChannel.prototype.send = function (d) {
    if (typeof d === 'string') msgs.push({ t: performance.now(), dir: 'out', d });
    return send.call(this, d);
  };
}

async function selectedPairs(page) {
  return page.evaluate(async () => {
    const out = [];
    for (const pc of window.__pcs) {
      if (pc.connectionState !== 'connected') continue;
      const stats = await pc.getStats();
      const byId = new Map();
      stats.forEach((s) => byId.set(s.id, s));
      stats.forEach((s) => {
        if (s.type !== 'transport' || !s.selectedCandidatePairId) return;
        const pair = byId.get(s.selectedCandidatePairId);
        const l = byId.get(pair.localCandidateId);
        const r = byId.get(pair.remoteCandidateId);
        out.push({
          local: l.candidateType,
          remote: r.candidateType,
          protocol: l.protocol,
          relayProtocol: l.relayProtocol,
          bytesSent: pair.bytesSent,
          bytesReceived: pair.bytesReceived,
        });
      });
    }
    return out;
  });
}

async function enableSemantics(page) {
  await page.waitForSelector('flt-semantics-placeholder', { state: 'attached', timeout: 30000 });
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder').click());
}

const parse = (m) => {
  try {
    return JSON.parse(m.d);
  } catch {
    return null;
  }
};
const lastTiles = async (page, dir) => {
  const msgs = await page.evaluate(() => window.__msgs);
  const tiles = msgs.map((m) => ({ ...m, j: parse(m) })).filter((m) => m.dir === dir && m.j && m.j.type === 'tiles');
  return tiles.length ? tiles[tiles.length - 1].j.checked.slice().sort((a, b) => a - b) : [];
};
const until = async (fn, ms, what) => {
  const end = Date.now() + ms;
  for (;;) {
    if (await fn()) return;
    if (Date.now() > end) throw new Error(`timeout: ${what}`);
    await new Promise((r) => setTimeout(r, 100));
  }
};

(async () => {
  const args = ['--no-sandbox'];
  if (LOCAL)
    args.push(
      '--host-resolver-rules=MAP 0.peerjs.com 127.0.0.1:9443',
      '--ignore-certificate-errors',
      // The public github.io page may not reach a loopback address otherwise (Private Network Access).
      '--disable-features=BlockInsecurePrivateNetworkRequests,PrivateNetworkAccessSendPreflights,PrivateNetworkAccessRespectPreflightResults,LocalNetworkAccessChecks',
    );
  const browser = await chromium.launch({
    executablePath: process.env.CHROME_BIN || undefined,
    args,
  });
  const result = { relayForced: RELAY, localSignalling: LOCAL, guests: GUESTS };
  let step = 'launch';
  const pages = [];
  try {
    const hostCtx = await browser.newContext({ viewport: { width: 800, height: 1400 } });
    await hostCtx.addInitScript(instrument, { relay: RELAY, boardJson: JSON.stringify([board]) });
    const host = await hostCtx.newPage();
    pages.push(host);
    let roomId;
    host.on('websocket', (ws) => {
      const m = ws.url().match(/[?&]id=bingo-sggw-([A-Z0-9]+)/);
      if (m) roomId = m[1];
    });
    step = 'APP_URL);';
    await host.goto(APP_URL);
    await enableSemantics(host);
    step = "'button', { name: 'Moje plansze' }).clic";
    await host.getByRole('button', { name: 'Moje plansze' }).click();
    step = "'button', { name: 'Więcej' }).click";
    await host.getByRole('button', { name: 'Więcej' }).click();
    step = "'Utwórz pokój').click";
    await host.getByRole('menuitem', { name: 'Utwórz pokój' }).click();
    step = "'textbox', { name: 'Nick' }).fill";
    await host.getByRole('textbox', { name: 'Nick' }).fill('Host');
    await host.getByRole('button', { name: 'Dalej' }).click();
    await until(() => roomId, 20000, 'host peer registered with signalling');
    await host.getByText(`Pokój: ${roomId}`).waitFor({ timeout: 20000 });
    result.roomId = roomId;

    const guests = [];
    for (let g = 0; g < GUESTS; g++) {
      const ctx = await browser.newContext({ viewport: { width: 800, height: 1400 } });
      await ctx.addInitScript(instrument, { relay: RELAY, boardJson: null });
      const page = await ctx.newPage();
      pages.push(page);
      await page.goto(`${APP_URL}?room=${roomId}`);
      await enableSemantics(page);
      step = "'textbox', { name: 'Jak się nazywasz?' }";
    await page.getByRole('textbox', { name: 'Jak się nazywasz?' }).fill(`Gosc${g}`);
      const t = Date.now();
      await page.getByRole('button', { name: 'Dołącz' }).click();
      await host.getByText(`Gosc${g}`).waitFor({ timeout: 20000 });
      result[`join${g}Ms`] = Date.now() - t;
      guests.push(page);
    }

    step = "'button', { name: 'Zacznij grę' }).click";
    await host.getByRole('button', { name: 'Zacznij grę' }).click();
    for (const p of [host, ...guests]) await p.getByText('Pole 0').waitFor({ timeout: 20000 });

    const counts = Array(SIZE * SIZE).fill(0);
    const expected = () => counts.flatMap((c, i) => (c % 2 ? [i] : []));
    const same = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);
    const rtts = [];
    for (let n = 0; n < TOGGLES; n++) {
      const who = n % 2 === 0 ? guests[n % guests.length] : host;
      const index = (n * 4 + 1) % (SIZE * SIZE);
      counts[index]++;
      step = `toggle ${n}`;
      await who.getByText(`Pole ${index}`, { exact: true }).click();
      await until(
        async () => {
          for (const g of guests) if (!same(await lastTiles(g, 'in'), expected())) return false;
          return same(await lastTiles(host, 'out'), expected());
        },
        15000,
        `toggle ${n} synced`,
      );
      if (who !== host) {
        const rtt = await who.evaluate(() => {
          const m = window.__msgs;
          const out = m.findLast((x) => x.dir === 'out' && x.d.includes('"toggle"'));
          const back = m.find((x) => x.t > out.t && x.dir === 'in' && x.d.includes('"tiles"'));
          return back ? back.t - out.t : null;
        });
        if (rtt != null) rtts.push(rtt);
      }
    }
    const want = `${expected().length} / ${SIZE * SIZE}`;
    for (const p of [host, ...guests]) await p.getByText(want).waitFor({ timeout: 10000 });
    result.toggles = TOGGLES;
    result.finalChecked = expected();
    result.uiCounterMatches = true;
    rtts.sort((a, b) => a - b);
    result.guestToggleRoundTripMs = rtts.length
      ? { n: rtts.length, median: Math.round(rtts[rtts.length >> 1]), max: Math.round(rtts[rtts.length - 1]) }
      : null;
    result.hostPairs = await selectedPairs(host);
    result.guestPairs = await Promise.all(guests.map(selectedPairs));
    const all = [...result.hostPairs, ...result.guestPairs.flat()];
    result.allRelay = all.length > 0 && all.every((p) => p.local === 'relay' && p.remote === 'relay');
    result.ok = true;
  } catch (e) {
    result.ok = false;
    result.step = step;
    result.error = String(e.message || e).split('\n')[0];
    if (process.env.SHOT_DIR)
      for (const [i, p] of pages.entries()) await p.screenshot({ path: `${process.env.SHOT_DIR}/fail-${i}.png` }).catch(() => {});
  } finally {
    await browser.close();
  }
  console.log(JSON.stringify(result, null, 2));
  process.exit(result.ok ? 0 : 1);
})();
