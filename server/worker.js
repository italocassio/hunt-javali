// Production entry: Worker (route + Origin) and Room Durable Object (WebSocket Hibernation API).
// All room logic lives in rooms.js; this file only adapts the runtime.
import { config, parseOrigins, originAllowed } from "./config.js";
import { parseHello, makeCode, admit, welcome, onMessage, onClose } from "./rooms.js";

function random() {
  return crypto.getRandomValues(new Uint32Array(1))[0] / 4294967296;
}

function errorText(code, extra) {
  return JSON.stringify({ t: "error", code, ...(extra || {}) });
}

// Accepts the upgrade only to deliver an error + close (browsers never see HTTP error bodies of an upgrade).
function rejectSocket(code, close, extra) {
  const pair = new WebSocketPair();
  const server = pair[1];
  server.accept();
  server.send(errorText(code, extra));
  server.close(close, code);
  return new Response(null, { status: 101, webSocket: pair[0] });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname !== "/ws") return new Response("Not found", { status: 404 });
    if ((request.headers.get("Upgrade") || "").toLowerCase() !== "websocket") {
      return new Response("Upgrade required", { status: 426 });
    }
    if (!originAllowed(request.headers.get("Origin"), parseOrigins(env.ALLOWED_ORIGINS), false)) {
      return new Response("origin_denied", { status: 403 });
    }
    const hello = parseHello(request.url);
    if (hello === null) return rejectSocket("bad_request", 4400);
    const code = hello.t === "create" ? makeCode(config, random) : hello.code;
    url.searchParams.set("code", code);
    const stub = env.ROOMS.get(env.ROOMS.idFromName(code));
    return stub.fetch(new Request(url, request));
  },
};

export class Room {
  constructor(ctx, env) {
    this.ctx = ctx;
    this.env = env;
    this.vols = new Map(); // id -> volatile rate bucket (resets when the object hibernates: acceptable)
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair('{"t":"ping"}', '{"t":"pong"}'));
  }

  wrap(ws, meta) {
    const vols = this.vols;
    const peer = {
      meta,
      get vol() {
        let v = vols.get(this.meta.id);
        if (v === undefined) {
          v = {};
          vols.set(this.meta.id, v);
        }
        return v;
      },
      send: (d) => ws.send(d),
      close: (c, r) => ws.close(c, r),
      setMeta(m) {
        this.meta = m;
        ws.serializeAttachment(m);
      },
    };
    return peer;
  }

  // Live connections rebuilt from the attachments only (no in-memory state needed).
  peers() {
    const list = [];
    for (const ws of this.ctx.getWebSockets()) {
      const meta = ws.deserializeAttachment();
      if (meta) list.push(this.wrap(ws, meta));
    }
    return list;
  }

  peerOf(ws) {
    const meta = ws.deserializeAttachment();
    return meta ? this.wrap(ws, meta) : null;
  }

  async fetch(request) {
    const hello = parseHello(request.url);
    const pair = new WebSocketPair();
    const [client, server] = [pair[0], pair[1]];
    if (hello === null) {
      server.accept();
      server.send(errorText("bad_request"));
      server.close(4400, "bad_request");
      return new Response(null, { status: 101, webSocket: client });
    }
    const result = admit(this.peers(), hello, config, Date.now());
    if (result.error) {
      server.accept();
      server.send(errorText(result.error, result.extra));
      server.close(result.close, result.reason || result.error);
      return new Response(null, { status: 101, webSocket: client });
    }
    this.ctx.acceptWebSocket(server, [String(result.meta.id)]);
    server.serializeAttachment(result.meta);
    welcome(this.peers(), this.wrap(server, result.meta));
    return new Response(null, { status: 101, webSocket: client });
  }

  webSocketMessage(ws, message) {
    const peer = this.peerOf(ws);
    if (peer === null) return;
    const data = typeof message === "string" ? message : new Uint8Array(message);
    onMessage(this.peers(), peer, data, config, Date.now());
  }

  closed(ws, code) {
    const peer = this.peerOf(ws);
    if (peer === null) return;
    try {
      ws.close(code && code >= 1000 && code < 5000 && code !== 1005 && code !== 1006 ? code : 1000, "closed");
    } catch (e) {
      // already closed
    }
    onClose(this.peers(), peer);
    this.vols.delete(peer.meta.id);
  }

  webSocketClose(ws, code) {
    this.closed(ws, code);
  }

  webSocketError(ws) {
    this.closed(ws, 1011);
  }
}
