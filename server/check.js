// Protocol check against a running server (local Bun, wrangler dev or production).
// Usage: bun check.js <ws-url> [--origin <origin>] [--idle <seconds>]
//   --origin  sends this Origin header (needed against production); also checks that a wrong origin gets 403.
//   --idle    waits N seconds with a live room, then checks that it still relays (hibernation).
const args = process.argv.slice(2);
const base = args.find((a) => !a.startsWith("--") && args[args.indexOf(a) - 1] !== "--origin" && args[args.indexOf(a) - 1] !== "--idle");
const opt = (name) => (args.includes(name) ? args[args.indexOf(name) + 1] : undefined);
const origin = opt("--origin");
const idle = opt("--idle") ? parseInt(opt("--idle"), 10) : 0;
if (!base) {
  console.error("Uso: bun check.js <url ws://.../ws> [--origin <origem>] [--idle <segundos>]");
  process.exit(2);
}

const V = "9.9.9";
const PROTO = 1;
let failures = 0;
let passed = 0;

function ok(cond, label, detail) {
  if (cond) {
    passed++;
    console.log("  ok   " + label);
  } else {
    failures++;
    console.log("  FAIL " + label + (detail === undefined ? "" : " -> " + JSON.stringify(detail)));
  }
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function url(query) {
  return `${base}?v=${V}&proto=${PROTO}&${query}`;
}

// Client with an inbox. next(pred) resolves with the first matching message (kept in order).
function open(query, headers) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url(query), { headers: headers || (origin ? { Origin: origin } : {}) });
    ws.binaryType = "arraybuffer";
    const c = { ws, inbox: [], closeCode: null, waiters: [] };
    const wake = () => {
      for (const w of c.waiters.slice()) {
        const i = c.inbox.findIndex(w.pred);
        if (i >= 0 || (w.untilClose && c.closeCode !== null)) {
          c.waiters.splice(c.waiters.indexOf(w), 1);
          w.resolve(i >= 0 ? c.inbox.splice(i, 1)[0] : null);
        }
      }
    };
    ws.onmessage = (e) => {
      c.inbox.push(typeof e.data === "string" ? JSON.parse(e.data) : new Uint8Array(e.data));
      wake();
    };
    ws.onclose = (e) => {
      c.closeCode = e.code;
      wake();
    };
    ws.onopen = () => resolve(c);
    ws.onerror = () => {
      if (ws.readyState !== WebSocket.OPEN) reject(new Error("falha ao abrir " + query));
    };
    c.next = (pred, ms = 5000) =>
      new Promise((res) => {
        const w = { pred, resolve: res, untilClose: false };
        c.waiters.push(w);
        wake();
        setTimeout(() => {
          const i = c.waiters.indexOf(w);
          if (i >= 0) {
            c.waiters.splice(i, 1);
            res(null);
          }
        }, ms);
      });
    c.type = (t) => c.next((m) => !(m instanceof Uint8Array) && m.t === t);
    c.bin = () => c.next((m) => m instanceof Uint8Array);
    c.closed = async (ms = 5000) => {
      const end = Date.now() + ms;
      while (c.closeCode === null && Date.now() < end) await sleep(20);
      return c.closeCode;
    };
    c.send = (d) => ws.send(d);
    c.json = (o) => ws.send(JSON.stringify(o));
  });
}

// join expecting an error + close
async function joinFail(query) {
  const c = await open(query);
  const err = await c.type("error");
  const code = await c.closed();
  return { err, code };
}

async function main() {
  const http = base.replace(/^ws/, "http");
  console.log("Servidor: " + base + (origin ? "  origem: " + origin : ""));

  console.log("rotas HTTP");
  const notFound = await fetch(new URL("/nada", http), origin ? { headers: { Origin: origin } } : {});
  ok(notFound.status === 404, "caminho diferente de /ws responde 404", notFound.status);
  const noUpgrade = await fetch(http, origin ? { headers: { Origin: origin } } : {});
  ok(noUpgrade.status === 426, "sem Upgrade responde 426", noUpgrade.status);
  const wrongOrigin = await open("t=create&name=Intruso", { Origin: "https://evil.example" }).then(
    () => "aberto",
    () => "recusado",
  );
  ok(wrongOrigin === "recusado", "origem errada nao abre o WebSocket", wrongOrigin);
  const wrongHttp = await fetch(http, {
    headers: { Origin: "https://evil.example", Upgrade: "websocket", Connection: "Upgrade", "Sec-WebSocket-Version": "13", "Sec-WebSocket-Key": "dGhlIHNhbXBsZSBub25jZQ==" },
  }).catch(() => null);
  if (wrongHttp !== null) ok(wrongHttp.status === 403, "origem errada recebe HTTP 403", wrongHttp.status);
  else console.log("  (fetch com Upgrade nao suportado pelo cliente; 403 conferido so pelo WebSocket)");

  console.log("criar e entrar");
  const host = await open("t=create&name=Italo");
  const created = await host.type("created");
  ok(created && /^[A-HJ-NP-Z2-9]{5}$/.test(created.code) && created.id === 1, "created com codigo de 5 caracteres e id 1", created);
  const code = created.code;

  const mism = await new Promise((resolve) => {
    const ws = new WebSocket(`${base}?t=join&code=${code}&v=0.0.1&proto=${PROTO}`, { headers: origin ? { Origin: origin } : {} });
    const got = {};
    ws.onmessage = (e) => (got.msg = JSON.parse(e.data));
    ws.onclose = (e) => resolve({ ...got, close: e.code });
  });
  ok(mism.msg && mism.msg.code === "version_mismatch" && mism.msg.host_v === V && mism.close === 4426, "versao diferente: version_mismatch + 4426 + host_v", mism);

  const nf = await joinFail("t=join&code=ZZZZZ");
  ok(nf.err && nf.err.code === "room_not_found" && nf.code === 4404, "codigo inexistente: room_not_found + 4404", nf);

  const badReq = await new Promise((resolve) => {
    const ws = new WebSocket(`${base}?t=join`, { headers: origin ? { Origin: origin } : {} });
    const got = {};
    ws.onmessage = (e) => (got.msg = JSON.parse(e.data));
    ws.onclose = (e) => resolve({ ...got, close: e.code });
  });
  ok(badReq.msg && badReq.msg.code === "bad_request" && badReq.close === 4400, "URL sem parametros: bad_request + 4400", badReq);

  const a = await open(`t=join&code=${code}&name=Ana&want=2`);
  const joined = await a.type("joined");
  ok(joined && joined.id === 2 && joined.code === code && joined.peers.length === 1 && joined.peers[0].id === 1 && joined.peers[0].name === "Italo", "joined com id e lista de peers", joined);
  const pj = await host.type("peer_joined");
  ok(pj && pj.id === 2 && pj.name === "Ana", "anfitriao recebe peer_joined", pj);
  const b = await open(`t=join&code=${code}&name=Beto&want=4`);
  const joinedB = await b.type("joined");
  ok(joinedB && joinedB.id === 4 && joinedB.peers.length === 2, "want=4 livre vira id 4", joinedB);
  const c = await open(`t=join&code=${code}&name=Cris&want=4`);
  const joinedC = await c.type("joined");
  ok(joinedC && joinedC.id === 3, "want ocupado vira o menor id livre (3)", joinedC);
  const full = await joinFail(`t=join&code=${code}&name=Dani`);
  ok(full.err && full.err.code === "room_full" && full.code === 4403, "sala cheia: room_full + 4403", full);

  console.log("sinalizacao, relay, ping");
  a.json({ t: "signal", to: 1, data: { kind: "offer", sdp: "v=0" } });
  const sig = await host.type("signal");
  ok(sig && sig.from === 2 && sig.data.kind === "offer", "signal do cliente chega ao anfitriao com from", sig);
  host.json({ t: "signal", to: 3, data: { kind: "answer", sdp: "v=0" } });
  const sig2 = await c.type("signal");
  ok(sig2 && sig2.from === 1 && sig2.data.kind === "answer", "signal do anfitriao chega ao cliente", sig2);
  b.send(new Uint8Array([1, 0, 3, 0xaa, 0xbb, 0xcc]));
  const rel = await host.bin();
  ok(rel && Array.from(rel).join() === "4,0,3,170,187,204", "relay binario cliente -> anfitriao troca o byte por from", rel && Array.from(rel));
  host.send(new Uint8Array([3, 0, 2, 1, 2]));
  const rel2 = await c.bin();
  ok(rel2 && Array.from(rel2).join() === "1,0,2,1,2", "relay binario anfitriao -> cliente", rel2 && Array.from(rel2));
  a.send('{"t":"ping"}');
  const pong = await a.type("pong");
  ok(pong !== null, "ping responde pong");

  console.log("trancar");
  host.json({ t: "lock", locked: true });
  await sleep(150);
  const locked = await joinFail(`t=join&code=${code}&name=Edu`);
  ok(locked.err && locked.err.code === "in_progress" && locked.code === 4423, "sala trancada: in_progress + 4423", locked);
  host.json({ t: "lock", locked: false });
  await sleep(150);

  console.log("regra da estrela");
  c.json({ t: "signal", to: 2, data: {} });
  const starErr = await c.type("error");
  ok(starErr && starErr.code === "bad_request" && (await c.closed()) === 4400, "cliente falando com outro cliente: bad_request + 4400", starErr);
  const left = await host.type("peer_left");
  ok(left && left.id === 3, "anfitriao recebe peer_left", left);

  console.log("limites");
  const big = await open(`t=join&code=${code}&name=Grande`);
  await big.type("joined");
  big.send("x".repeat(9000));
  const tooBig = await big.type("error");
  ok(tooBig && tooBig.code === "too_big" && (await big.closed()) === 4413, "texto acima do limite: too_big + 4413", tooBig);
  const bigBin = await open(`t=join&code=${code}&name=Grande2`);
  await bigBin.type("joined");
  const payload = new Uint8Array(2301);
  payload[0] = 1;
  bigBin.send(payload);
  const tooBigBin = await bigBin.type("error");
  ok(tooBigBin && tooBigBin.code === "too_big" && (await bigBin.closed()) === 4413, "binario acima do limite: too_big + 4413", tooBigBin);
  const junk = await open(`t=join&code=${code}&name=Lixo`);
  await junk.type("joined");
  junk.send("isto nao e json");
  const jerr = await junk.type("error");
  ok(jerr && jerr.code === "bad_request" && (await junk.closed()) === 4400, "JSON invalido: bad_request + 4400", jerr);

  if (idle > 0) {
    console.log(`sala parada por ${idle} s`);
    await sleep(idle * 1000);
    a.json({ t: "signal", to: 1, data: { kind: "candidate" } });
    const afterIdle = await host.type("signal");
    ok(afterIdle && afterIdle.from === 2, "signal depois da pausa", afterIdle);
    host.send(new Uint8Array([2, 0, 1, 7]));
    const afterBin = await a.bin();
    ok(afterBin && Array.from(afterBin).join() === "1,0,1,7", "relay binario depois da pausa", afterBin && Array.from(afterBin));
    const late = await open(`t=join&code=${code}&name=Tardio`);
    const lateJoined = await late.type("joined");
    ok(lateJoined && lateJoined.peers.length >= 2, "entrada nova depois da pausa lista os peers", lateJoined);
    late.ws.close();
  }

  console.log("taxa");
  const flood = await open(`t=join&code=${code}&name=Flood`);
  await flood.type("joined");
  for (let i = 0; i < 400; i++) flood.json({ t: "signal", to: 1, data: {} });
  const rl = await flood.next((m) => m.t === "error" && m.code === "rate_limited", 8000);
  ok(rl !== null && (await flood.closed()) === 4429, "rajada: rate_limited + 4429", rl);

  console.log("anfitriao sai");
  a.ws.close();
  host.ws.close();
  const hl = await b.type("host_left");
  ok(hl !== null && (await b.closed()) === 4410, "host_left + 4410 para os demais", hl);
  const gone = await joinFail(`t=join&code=${code}&name=Tarde`);
  ok(gone.err && gone.err.code === "room_not_found", "sala destruida: room_not_found", gone);

  console.log(`\n${passed} ok, ${failures} falhas`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error("Erro no roteiro:", e);
  process.exit(1);
});
