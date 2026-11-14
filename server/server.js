// Local entry (Bun): same routes as worker.js, rooms kept in memory.
// Usage: bun server.js [--port 8787] [--host 0.0.0.0]
import { config, originAllowed } from "./config.js";
import { parseHello, makeCode, admit, welcome, onMessage, onClose } from "./rooms.js";

function arg(name, fallback) {
  const i = process.argv.indexOf(name);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : fallback;
}

const rooms = new Map(); // code -> Array<peer>

function random() {
  return crypto.getRandomValues(new Uint32Array(1))[0] / 4294967296;
}

function errorText(code, extra) {
  return JSON.stringify({ t: "error", code, ...(extra || {}) });
}

const server = Bun.serve({
  port: parseInt(arg("--port", "8787"), 10),
  hostname: arg("--host", undefined),
  fetch(req, srv) {
    const url = new URL(req.url);
    if (url.pathname !== "/ws") return new Response("Not found", { status: 404 });
    if ((req.headers.get("upgrade") || "").toLowerCase() !== "websocket") {
      return new Response("Upgrade required", { status: 426 });
    }
    // local server: localhost origins and no Origin header (native Godot clients)
    if (!originAllowed(req.headers.get("origin"), [], true)) {
      return new Response("origin_denied", { status: 403 });
    }
    const hello = parseHello(req.url);
    if (hello !== null && hello.t === "create") hello.code = makeCode(config, random);
    if (srv.upgrade(req, { data: { hello, peer: null, room: null } })) return undefined;
    return new Response("Upgrade failed", { status: 400 });
  },
  websocket: {
    maxPayloadLength: 65536,
    open(ws) {
      const hello = ws.data.hello;
      if (hello === null) {
        ws.send(errorText("bad_request"));
        ws.close(4400, "bad_request");
        return;
      }
      const room = rooms.get(hello.code) || [];
      const result = admit(room, hello, config, Date.now());
      if (result.error) {
        ws.send(errorText(result.error, result.extra));
        ws.close(result.close, result.reason || result.error);
        return;
      }
      const peer = {
        meta: result.meta,
        vol: {},
        send: (d) => ws.send(d),
        close: (c, r) => ws.close(c, r),
        setMeta(m) { this.meta = m; },
      };
      ws.data.peer = peer;
      ws.data.room = room;
      room.push(peer);
      rooms.set(hello.code, room);
      welcome(room, peer);
    },
    message(ws, data) {
      const { peer, room } = ws.data;
      if (peer === null) return;
      onMessage(room, peer, typeof data === "string" ? data : new Uint8Array(data), config, Date.now());
    },
    close(ws) {
      const { peer, room } = ws.data;
      if (peer === null) return;
      const i = room.indexOf(peer);
      if (i >= 0) room.splice(i, 1);
      onClose(room, peer);
      if (room.length === 0 && rooms.get(peer.meta.code) === room) rooms.delete(peer.meta.code);
    },
  },
});

console.log(`Servidor de salas local em ws://localhost:${server.port}/ws`);
