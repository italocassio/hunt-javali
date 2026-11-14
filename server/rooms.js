// Neutral logic of ONE room. No state of its own, no imports, no Bun/Node/Workers API.
// Every call receives the list of live connections of the room (docs/multiplayer.md section 5.1).
//
// peer = { meta, vol, send(data), close(code, reason), setMeta(meta) }
//   meta (survives hibernation): { id, host, name, v, proto, code, locked, born, left }
//        locked and born only matter on the host; left = "peer_left/host_left already handled".
//   vol  (volatile): { tokens, last }  rate bucket
// Conventions: `peers` may or may not contain the peer being handled; peers are matched by meta.id.
// `now` is in milliseconds. welcome() expects `peers` to already contain the new peer.

const CONTROL_CHARS = /[\u0000-\u001f\u007f-\u009f]/g;
const PING_TEXT = '{"t":"ping"}';

function alive(peers) {
  return peers.filter((p) => p.meta && !p.meta.left);
}

function sendJson(peer, obj) {
  peer.send(JSON.stringify(obj));
}

function fail(peer, code, close, extra) {
  sendJson(peer, { t: "error", code, ...(extra || {}) });
  peer.close(close, code);
}

function markLeft(peer) {
  try {
    peer.setMeta({ ...peer.meta, left: true });
  } catch (e) {
    // a closed socket may refuse the attachment; the flag is best effort
  }
}

function toInt(text) {
  if (text === null || text === undefined || !/^\d{1,9}$/.test(text)) return null;
  return parseInt(text, 10);
}

function cleanName(name, maxChars) {
  const clean = String(name || "").replace(CONTROL_CHARS, "").trim();
  return Array.from(clean).slice(0, maxChars).join("").trim();
}

function utf8Length(text) {
  let n = 0;
  for (let i = 0; i < text.length; i++) {
    const c = text.charCodeAt(i);
    if (c < 0x80) n += 1;
    else if (c < 0x800) n += 2;
    else if (c >= 0xd800 && c <= 0xdbff) { n += 4; i++; }
    else n += 3;
  }
  return n;
}

function expired(host, config, now) {
  return host !== undefined && now - host.meta.born > config.room_max_age_s * 1000;
}

// query string -> { t, code, v, proto, name, want } | null
export function parseHello(url) {
  let u;
  try {
    u = new URL(String(url), "http://localhost");
  } catch (e) {
    return null;
  }
  const q = u.searchParams;
  const t = q.get("t");
  if (t !== "create" && t !== "join") return null;
  const v = q.get("v");
  if (!v || v.length > 32) return null;
  const proto = toInt(q.get("proto"));
  if (proto === null) return null;
  const rawName = (q.get("name") || "").slice(0, 200);
  const code = (q.get("code") || "").toUpperCase();
  if (!/^[A-Z0-9]{0,16}$/.test(code)) return null;
  let want = 0;
  if (t === "join") {
    if (code === "") return null;
    const w = q.get("want");
    if (w !== null && w !== "") {
      want = toInt(w);
      if (want === null || want > 255) return null;
    }
  }
  return { t, code, v, proto, name: rawName, want };
}

export function makeCode(config, random) {
  const alphabet = config.room_code_alphabet;
  let code = "";
  for (let i = 0; i < config.room_code_length; i++) {
    code += alphabet[Math.floor(random() * alphabet.length)];
  }
  return code;
}

// -> { meta } | { error, close, extra, reason }   (reason = WebSocket close reason; default: error)
export function admit(peers, hello, config, now) {
  const live = alive(peers);
  const name = cleanName(hello.name, config.max_name_chars);
  if (hello.t === "create") {
    if (hello.code === "") return { error: "bad_request", close: 4400 };
    if (live.length > 0) return { error: "retry", close: 4409 };
    return {
      meta: { id: 1, host: true, name, v: hello.v, proto: hello.proto, code: hello.code, locked: false, born: now },
    };
  }
  const host = live.find((p) => p.meta.host);
  if (host === undefined) return { error: "room_not_found", close: 4404 };
  if (expired(host, config, now)) return { error: "expired", close: 4408 };
  if (hello.v !== host.meta.v || hello.proto !== host.meta.proto) {
    // Native Godot loses the JSON that arrives together with the close, so the host version also
    // travels in the close reason: "version_mismatch <host_v>" (printable ASCII, no spaces).
    const reasonV = String(host.meta.v).replace(/[^\x21-\x7e]/g, "");
    return { error: "version_mismatch", close: 4426, extra: { host_v: host.meta.v }, reason: `version_mismatch ${reasonV}` };
  }
  if (host.meta.locked) return { error: "in_progress", close: 4423 };
  if (live.length >= config.max_peers_per_room) return { error: "room_full", close: 4403 };
  const used = new Set(live.map((p) => p.meta.id));
  let id = 0;
  if (hello.want >= 2 && hello.want <= config.max_peers_per_room && !used.has(hello.want)) {
    id = hello.want;
  } else {
    for (let i = 2; i <= config.max_peers_per_room; i++) {
      if (!used.has(i)) { id = i; break; }
    }
  }
  if (id === 0) return { error: "room_full", close: 4403 };
  return { meta: { id, host: false, name, v: hello.v, proto: hello.proto, code: host.meta.code } };
}

// created/joined for the new peer, peer_joined for the others
export function welcome(peers, peer) {
  const others = alive(peers).filter((p) => p.meta.id !== peer.meta.id);
  if (peer.meta.host) {
    sendJson(peer, { t: "created", code: peer.meta.code, id: peer.meta.id });
    return;
  }
  const list = others.map((p) => ({ id: p.meta.id, name: p.meta.name })).sort((a, b) => a.id - b.id);
  sendJson(peer, { t: "joined", code: peer.meta.code, id: peer.meta.id, peers: list });
  for (const p of others) sendJson(p, { t: "peer_joined", id: peer.meta.id, name: peer.meta.name });
}

export function onMessage(peers, peer, data, config, now) {
  if (peer.meta.left) return;
  const live = alive(peers);
  const host = live.find((p) => p.meta.host);
  if (expired(host, config, now)) {
    for (const p of live) {
      markLeft(p);
      fail(p, "expired", 4408);
    }
    return;
  }
  // rate bucket
  const vol = peer.vol;
  if (vol.tokens === undefined) {
    vol.tokens = config.rate_burst;
    vol.last = now;
  }
  vol.tokens = Math.min(config.rate_burst, vol.tokens + ((now - vol.last) / 1000) * config.rate_msgs_per_s);
  vol.last = now;
  if (vol.tokens < 1) return fail(peer, "rate_limited", 4429);
  vol.tokens -= 1;

  if (typeof data === "string") return onText(live, peer, data, config);
  return onBinary(live, peer, data instanceof ArrayBuffer ? new Uint8Array(data) : data, config);
}

function onText(live, peer, text, config) {
  const tooBig = text.length > config.max_text_bytes
    || (text.length * 3 > config.max_text_bytes && utf8Length(text) > config.max_text_bytes);
  if (tooBig) return fail(peer, "too_big", 4413);
  if (text === PING_TEXT) return peer.send('{"t":"pong"}');
  let msg;
  try {
    msg = JSON.parse(text);
  } catch (e) {
    return fail(peer, "bad_request", 4400);
  }
  if (msg === null || typeof msg !== "object" || Array.isArray(msg)) return fail(peer, "bad_request", 4400);
  switch (msg.t) {
    case "signal": {
      const to = msg.to;
      if (!Number.isInteger(to) || to === peer.meta.id) return fail(peer, "bad_request", 4400);
      if (!peer.meta.host && to !== 1) return fail(peer, "bad_request", 4400);
      if (msg.data === null || typeof msg.data !== "object" || Array.isArray(msg.data)) {
        return fail(peer, "bad_request", 4400);
      }
      const target = live.find((p) => p.meta.id === to);
      if (target === undefined) return; // peer left in a race: drop, do not punish the sender
      return sendJson(target, { t: "signal", from: peer.meta.id, data: msg.data });
    }
    case "lock":
      if (!peer.meta.host || typeof msg.locked !== "boolean") return fail(peer, "bad_request", 4400);
      return peer.setMeta({ ...peer.meta, locked: msg.locked });
    case "leave":
      onClose(live, peer);
      return peer.close(1000, "leave");
    default:
      return fail(peer, "bad_request", 4400);
  }
}

function onBinary(live, peer, bytes, config) {
  if (bytes.length > config.max_binary_bytes) return fail(peer, "too_big", 4413);
  if (bytes.length < 1) return fail(peer, "bad_request", 4400);
  const to = bytes[0];
  if (to === peer.meta.id || (!peer.meta.host && to !== 1)) return fail(peer, "bad_request", 4400);
  const target = live.find((p) => p.meta.id === to);
  if (target === undefined) return; // peer left in a race: drop
  const out = new Uint8Array(bytes.length);
  out.set(bytes);
  out[0] = peer.meta.id;
  target.send(out);
}

// The runtime calls this when a socket closed; idempotent (meta.left)
export function onClose(peers, peer) {
  if (!peer.meta || peer.meta.left) return;
  const others = alive(peers).filter((p) => p.meta.id !== peer.meta.id);
  const wasHost = peer.meta.host;
  const id = peer.meta.id;
  markLeft(peer);
  if (wasHost) {
    for (const p of others) {
      markLeft(p);
      sendJson(p, { t: "host_left" });
      p.close(4410, "host_left");
    }
    return;
  }
  for (const p of others) sendJson(p, { t: "peer_left", id });
}
