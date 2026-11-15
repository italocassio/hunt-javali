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

  // F8 (docs/multiplayer.md 4.7.2). At this point: host 1, a = 2, c = 3, b = 4, room unlocked.
  console.log("reentrada");
  const TOK2 = 123456;
  const TOK3 = 4294967295;
  a.inbox.length = 0;
  const unlockedTry = await joinFail(`t=join&code=${code}&name=Ana&want=2&tok=${TOK2}`);
  ok(unlockedTry.err && unlockedTry.err.code === "bad_token" && unlockedTry.code === 4401, "sala destrancada: bad_token + 4401", unlockedTry);
  host.json({ t: "lock", locked: true, tokens: { 2: TOK2, 3: TOK3 } });
  await sleep(150);
  const noTok = await joinFail(`t=join&code=${code}&name=Edu&want=2`);
  ok(noTok.err && noTok.err.code === "in_progress" && noTok.code === 4423, "sem tok em sala trancada: in_progress + 4423", noTok);
  const wrongTok = await joinFail(`t=join&code=${code}&name=Ana&want=2&tok=${TOK2 + 1}`);
  ok(wrongTok.err && wrongTok.err.code === "bad_token" && wrongTok.code === 4401, "token errado: bad_token + 4401", wrongTok);
  const noSlotTok = await joinFail(`t=join&code=${code}&name=Beto&want=4&tok=${TOK2}`);
  ok(noSlotTok.err && noSlotTok.err.code === "bad_token" && noSlotTok.code === 4401, "slot sem token: bad_token + 4401", noSlotTok);
  const badTok = await joinFail(`t=join&code=${code}&name=Ana&want=2&tok=4294967296`);
  ok(badTok.err && badTok.err.code === "bad_request" && badTok.code === 4400, "tok acima de u32: bad_request + 4400", badTok);
  const mismTok = await new Promise((resolve) => {
    const ws = new WebSocket(`${base}?t=join&code=${code}&v=0.0.1&proto=${PROTO}&want=2&tok=${TOK2 + 1}`, { headers: origin ? { Origin: origin } : {} });
    const got = {};
    ws.onmessage = (e) => (got.msg = JSON.parse(e.data));
    ws.onclose = (e) => resolve({ ...got, close: e.code });
  });
  ok(mismTok.msg && mismTok.msg.code === "version_mismatch" && mismTok.close === 4426, "version_mismatch vem antes de bad_token", mismTok);
  ok(a.closeCode === null && a.inbox.length === 0, "reentrada recusada nao mexe no socket do slot", { close: a.closeCode, inbox: a.inbox });

  // live socket swapped (half-open phone): old one gets replaced + 4411, nobody hears peer_left
  host.inbox.length = 0;
  b.inbox.length = 0;
  const a2 = await open(`t=join&code=${code}&name=Ana&want=2&tok=${TOK2}&ep=3`);
  const rejoined = await a2.type("joined");
  ok(rejoined && rejoined.id === 2 && rejoined.peers.length === 3, "token certo: joined no mesmo id, com 4 conexoes vivas", rejoined);
  const replaced = await a.type("error");
  ok(replaced && replaced.code === "replaced" && (await a.closed()) === 4411, "socket antigo: replaced + 4411", replaced);
  const pjHost = await host.type("peer_joined");
  ok(pjHost && pjHost.id === 2 && pjHost.name === "Ana" && pjHost.ep === 3, "anfitriao recebe peer_joined com ep", pjHost);
  const pjOther = await b.type("peer_joined");
  ok(pjOther && pjOther.id === 2 && pjOther.ep === 3, "os demais recebem peer_joined com ep", pjOther);
  host.send(new Uint8Array([2, 0, 1, 0x5a]));
  const relNew = await a2.bin();
  ok(relNew && Array.from(relNew).join() === "1,0,1,90", "relay depois da troca chega ao socket novo", relNew && Array.from(relNew));
  a2.send(new Uint8Array([1, 0, 1, 0x5b]));
  const relBack = await host.bin();
  ok(relBack && Array.from(relBack).join() === "2,0,1,91", "socket novo fala com o anfitriao", relBack && Array.from(relBack));
  await sleep(300);
  const strayLeft = host.inbox.find((m) => !(m instanceof Uint8Array) && m.t === "peer_left");
  ok(strayLeft === undefined, "troca de socket nao emite peer_left", strayLeft);

  // socket that just closed: peer_left without clean; the slot comes back with the same token
  host.inbox.length = 0;
  a2.ws.close();
  const dropLeft = await host.type("peer_left");
  ok(dropLeft && dropLeft.id === 2 && dropLeft.clean === undefined, "socket fechado: peer_left sem clean", dropLeft);
  const a3 = await open(`t=join&code=${code}&name=Ana&want=2&tok=${TOK2}&ep=4`);
  const rejoined3 = await a3.type("joined");
  ok(rejoined3 && rejoined3.id === 2, "slot vazio: reentrada no mesmo id", rejoined3);
  const pj3 = await host.type("peer_joined");
  ok(pj3 && pj3.id === 2 && pj3.ep === 4, "peer_joined da segunda volta leva a epoca nova", pj3);

  // explicit leave: clean; then the host revokes the slot
  host.inbox.length = 0;
  a3.json({ t: "leave" });
  const cleanLeft = await host.type("peer_left");
  ok(cleanLeft && cleanLeft.id === 2 && cleanLeft.clean === true, "leave: peer_left com clean", cleanLeft);
  host.json({ t: "lock", locked: true, tokens: { 3: TOK3 } });
  await sleep(150);
  const revoked = await joinFail(`t=join&code=${code}&name=Ana&want=2&tok=${TOK2}`);
  ok(revoked.err && revoked.err.code === "bad_token" && revoked.code === 4401, "slot revogado: bad_token + 4401", revoked);
  host.json({ t: "lock", locked: false });
  await sleep(150);
  const afterUnlock = await joinFail(`t=join&code=${code}&name=Cris&want=3&tok=${TOK3}`);
  ok(afterUnlock.err && afterUnlock.err.code === "bad_token" && afterUnlock.code === 4401, "destrancar apaga os tokens: bad_token + 4401", afterUnlock);
  const aBack = await open(`t=join&code=${code}&name=Ana&want=2`);
  const aBackJoined = await aBack.type("joined");
  ok(aBackJoined && aBackJoined.id === 2, "sala destrancada aceita entrada normal de novo", aBackJoined);
  const pjNormal = await host.type("peer_joined");
  ok(pjNormal && pjNormal.id === 2 && pjNormal.ep === 0, "entrada normal: peer_joined com ep 0", pjNormal);

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
    aBack.json({ t: "signal", to: 1, data: { kind: "candidate" } });
    const afterIdle = await host.type("signal");
    ok(afterIdle && afterIdle.from === 2, "signal depois da pausa", afterIdle);
    host.send(new Uint8Array([2, 0, 1, 7]));
    const afterBin = await aBack.bin();
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
  aBack.ws.close();
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
