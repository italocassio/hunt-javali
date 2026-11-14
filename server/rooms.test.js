// bun test. The rig plays the role of the runtime: it keeps the sockets, and in "hibernate" mode
// it rebuilds every peer object from the stored meta only before each call (volatile state lost).
import { describe, test, expect } from "bun:test";
import { config } from "./config.js";
import { parseHello, makeCode, admit, welcome, onMessage, onClose } from "./rooms.js";

class Rig {
  constructor(mode, cfg = config) {
    this.mode = mode;
    this.cfg = cfg;
    this.socks = [];
    this.now = 1_000_000;
    this.nextCode = "K7QF2";
  }

  makePeer(sock) {
    return {
      meta: sock.meta,
      vol: sock.vol,
      send: (d) => sock.out.push(d),
      close: (c) => { if (sock.closed === null) sock.closed = c; },
      setMeta(m) { this.meta = m; sock.meta = m; },
    };
  }

  // the Durable Object went idle and woke up: volatile state is gone
  hibernate() {
    for (const s of this.socks) s.vol = {};
  }

  // live connections, like ctx.getWebSockets() / the room array
  peers() {
    const list = this.socks.filter((s) => s.closed === null && s.meta !== null).map((s) => {
      if (this.mode === "stable") {
        s.peer = s.peer || this.makePeer(s);
        s.peer.meta = s.meta;
        s.peer.vol = s.vol;
        return s.peer;
      }
      return this.makePeer(s);
    });
    return list;
  }

  // runtime close handlers for sockets the server closed (a no-op for left peers)
  settle() {
    for (let guard = 0; guard < 20; guard++) {
      const pending = this.socks.filter((s) => s.closed !== null && !s.handled && s.meta !== null);
      if (pending.length === 0) return;
      for (const s of pending) {
        s.handled = true;
        onClose(this.peers(), this.makePeer(s));
      }
    }
  }

  connect(query, opts = {}) {
    const sock = { meta: null, closed: null, handled: false, out: [], vol: {}, peer: null };
    this.socks.push(sock);
    const hello = parseHello("wss://x/ws?" + query);
    if (hello === null) {
      sock.out.push(JSON.stringify({ t: "error", code: "bad_request" }));
      sock.closed = 4400;
      return this.wrapConn(sock);
    }
    if (hello.t === "create") hello.code = opts.code || this.nextCode;
    const room = this.peers().filter((p) => p.meta.code === hello.code);
    const result = admit(room, hello, this.cfg, this.now);
    if (result.error) {
      sock.out.push(JSON.stringify({ t: "error", code: result.error, ...(result.extra || {}) }));
      sock.closed = result.close;
      sock.closeReason = result.reason || result.error;
      sock.handled = true;
      return this.wrapConn(sock);
    }
    sock.meta = result.meta;
    welcome(this.peers(), this.makePeer(sock));
    this.settle();
    return this.wrapConn(sock);
  }

  send(conn, data) {
    const sock = conn.sock;
    if (sock.closed !== null) return;
    const peer = this.peers().find((p) => p.meta.id === sock.meta.id) || this.makePeer(sock);
    onMessage(this.peers(), peer, data, this.cfg, this.now);
    this.settle();
  }

  drop(conn) {
    conn.sock.closed = conn.sock.closed ?? 1001;
    this.settle();
  }

  wrapConn(sock) {
    const rig = this;
    return {
      sock,
      get texts() { return sock.out.filter((m) => typeof m === "string").map((m) => JSON.parse(m)); },
      get bins() { return sock.out.filter((m) => typeof m !== "string"); },
      get closed() { return sock.closed; },
      get id() { return sock.meta && sock.meta.id; },
      clear() { sock.out.length = 0; },
      send(d) { rig.send(this, d); },
    };
  }
}

const Q = (extra) => `v=0.4.0&proto=1&${extra}`;

for (const mode of ["stable", "hibernate"]) {
  describe(`room (${mode})`, () => {
    const setup = () => {
      const rig = new Rig(mode);
      const host = rig.connect(Q("t=create&name=Italo"));
      return { rig, host };
    };

    test("create", () => {
      const { host } = setup();
      expect(host.texts).toEqual([{ t: "created", code: "K7QF2", id: 1 }]);
      expect(host.closed).toBeNull();
    });

    test("create on a used code gives retry", () => {
      const { rig } = setup();
      const again = rig.connect(Q("t=create"));
      expect(again.texts).toEqual([{ t: "error", code: "retry" }]);
      expect(again.closed).toBe(4409);
    });

    test("join lists peers and tells the others", () => {
      const { rig, host } = setup();
      host.clear();
      const a = rig.connect(Q("t=join&code=k7qf2&name=Ana"));
      expect(a.texts).toEqual([{ t: "joined", code: "K7QF2", id: 2, peers: [{ id: 1, name: "Italo" }] }]);
      expect(host.texts).toEqual([{ t: "peer_joined", id: 2, name: "Ana" }]);
      const b = rig.connect(Q("t=join&code=K7QF2&name=Beto"));
      expect(b.texts[0].peers).toEqual([{ id: 1, name: "Italo" }, { id: 2, name: "Ana" }]);
      expect(b.id).toBe(3);
    });

    test("id is want when free, otherwise smallest free", () => {
      const { rig } = setup();
      expect(rig.connect(Q("t=join&code=K7QF2&want=4")).id).toBe(4);
      expect(rig.connect(Q("t=join&code=K7QF2&want=4")).id).toBe(2);
      expect(rig.connect(Q("t=join&code=K7QF2&want=1")).id).toBe(3);
    });

    test("room full", () => {
      const { rig } = setup();
      for (let i = 0; i < 3; i++) rig.connect(Q("t=join&code=K7QF2"));
      const late = rig.connect(Q("t=join&code=K7QF2"));
      expect(late.texts).toEqual([{ t: "error", code: "room_full" }]);
      expect(late.closed).toBe(4403);
    });

    test("freed id is reused", () => {
      const { rig } = setup();
      const a = rig.connect(Q("t=join&code=K7QF2"));
      rig.connect(Q("t=join&code=K7QF2"));
      rig.drop(a);
      expect(rig.connect(Q("t=join&code=K7QF2")).id).toBe(2);
    });

    test("version and proto mismatch", () => {
      const { rig } = setup();
      const a = rig.connect("t=join&code=K7QF2&v=0.3.9&proto=1");
      expect(a.texts).toEqual([{ t: "error", code: "version_mismatch", host_v: "0.4.0" }]);
      expect(a.closed).toBe(4426);
      expect(a.sock.closeReason).toBe("version_mismatch 0.4.0");
      const b = rig.connect("t=join&code=K7QF2&v=0.4.0&proto=2");
      expect(b.closed).toBe(4426);
      expect(b.sock.closeReason).toBe("version_mismatch 0.4.0");
    });

    test("other admit errors keep the error name as close reason", () => {
      const { rig } = setup();
      const a = rig.connect(Q("t=join&code=ZZZZZ"));
      expect(a.sock.closeReason).toBe("room_not_found");
    });

    test("room not found", () => {
      const { rig } = setup();
      const a = rig.connect(Q("t=join&code=ZZZZZ"));
      expect(a.texts).toEqual([{ t: "error", code: "room_not_found" }]);
      expect(a.closed).toBe(4404);
    });

    test("bad hello", () => {
      const { rig } = setup();
      for (const q of ["t=nope&v=1&proto=1", "t=join&v=1&proto=1", "t=create&proto=1", "t=create&v=1", "t=join&code=AB%20C&v=1&proto=1"]) {
        const c = rig.connect(q);
        expect(c.texts).toEqual([{ t: "error", code: "bad_request" }]);
        expect(c.closed).toBe(4400);
      }
    });

    test("lock refuses entry with in_progress; unlock reopens", () => {
      const { rig, host } = setup();
      host.send('{"t":"lock","locked":true}');
      const a = rig.connect(Q("t=join&code=K7QF2"));
      expect(a.texts).toEqual([{ t: "error", code: "in_progress" }]);
      expect(a.closed).toBe(4423);
      host.send('{"t":"lock","locked":false}');
      expect(rig.connect(Q("t=join&code=K7QF2")).id).toBe(2);
    });

    test("only the host can lock", () => {
      const { rig } = setup();
      const a = rig.connect(Q("t=join&code=K7QF2"));
      a.send('{"t":"lock","locked":true}');
      expect(a.closed).toBe(4400);
    });

    test("signal is relayed with from", () => {
      const { rig, host } = setup();
      const a = rig.connect(Q("t=join&code=K7QF2"));
      rig.connect(Q("t=join&code=K7QF2"));
      host.clear();
      a.clear();
      a.send(JSON.stringify({ t: "signal", to: 1, data: { kind: "offer", sdp: "x" } }));
      expect(host.texts).toEqual([{ t: "signal", from: 2, data: { kind: "offer", sdp: "x" } }]);
      host.send(JSON.stringify({ t: "signal", to: 2, data: { kind: "answer", sdp: "y" } }));
      expect(a.texts).toEqual([{ t: "signal", from: 1, data: { kind: "answer", sdp: "y" } }]);
    });

    test("signal to a vanished peer is dropped without punishing the sender", () => {
      const { rig, host } = setup();
      host.send(JSON.stringify({ t: "signal", to: 3, data: {} }));
      expect(host.closed).toBeNull();
      expect(rig.socks.length).toBe(1);
    });

    test("star rule: a client talks only to id 1", () => {
      const { rig, host } = setup();
      const a = rig.connect(Q("t=join&code=K7QF2"));
      const b = rig.connect(Q("t=join&code=K7QF2"));
      b.clear();
      a.send(JSON.stringify({ t: "signal", to: 3, data: {} }));
      expect(a.closed).toBe(4400);
      expect(a.texts.at(-1)).toEqual({ t: "error", code: "bad_request" });
      expect(b.texts.filter((m) => m.t === "signal")).toEqual([]);
      expect(b.texts).toEqual([{ t: "peer_left", id: 2 }]);
      b.clear();
      b.send(new Uint8Array([2, 0, 1, 0, 9]));
      expect(b.closed).toBe(4400);
      expect(host.closed).toBeNull();
    });

    test("signal needs an object data and an integer to", () => {
      const { rig } = setup();
      const a = rig.connect(Q("t=join&code=K7QF2"));
      a.send('{"t":"signal","to":1}');
      expect(a.closed).toBe(4400);
      const b = rig.connect(Q("t=join&code=K7QF2"));
      b.send('{"t":"signal","to":"1","data":{}}');
      expect(b.closed).toBe(4400);
    });

    test("binary relay swaps the first byte for from", () => {
      const { rig, host } = setup();
      const a = rig.connect(Q("t=join&code=K7QF2"));
      host.clear();
      a.clear();
      a.send(new Uint8Array([1, 0, 2, 7, 8, 0, 1, 9]));
      expect(host.bins.length).toBe(1);
      expect(Array.from(host.bins[0])).toEqual([2, 0, 2, 7, 8, 0, 1, 9]);
      host.send(new Uint8Array([2, 0, 1, 5]));
      expect(Array.from(a.bins[0])).toEqual([1, 0, 1, 5]);
    });

    test("binary to an absent id is dropped; to self is refused", () => {
      const { rig, host } = setup();
      host.send(new Uint8Array([4, 1]));
      expect(host.closed).toBeNull();
      host.send(new Uint8Array([1, 1]));
      expect(host.closed).toBe(4400);
      expect(rig.socks.length).toBe(1);
    });

    test("ping gets pong", () => {
      const { host } = setup();
      host.clear();
      host.send('{"t":"ping"}');
      expect(host.texts).toEqual([{ t: "pong" }]);
    });

    test("leave equals closing: peer_left once", () => {
      const { rig, host } = setup();
      const a = rig.connect(Q("t=join&code=K7QF2"));
      host.clear();
      a.send('{"t":"leave"}');
      rig.settle();
      expect(a.closed).toBe(1000);
      expect(host.texts).toEqual([{ t: "peer_left", id: 2 }]);
    });

    test("a client dropping sends peer_left", () => {
      const { rig, host } = setup();
      const a = rig.connect(Q("t=join&code=K7QF2"));
      rig.connect(Q("t=join&code=K7QF2"));
      host.clear();
      rig.drop(a);
      expect(host.texts).toEqual([{ t: "peer_left", id: 2 }]);
    });

    test("host leaving destroys the room", () => {
      const { rig, host } = setup();
      const a = rig.connect(Q("t=join&code=K7QF2"));
      const b = rig.connect(Q("t=join&code=K7QF2"));
      a.clear();
      b.clear();
      rig.drop(host);
      for (const c of [a, b]) {
        expect(c.texts).toEqual([{ t: "host_left" }]);
        expect(c.closed).toBe(4410);
      }
      expect(rig.connect(Q("t=join&code=K7QF2")).texts[0].code).toBe("room_not_found");
      expect(rig.connect(Q("t=create")).texts[0].t).toBe("created");
    });

    test("limit: text too big", () => {
      const { rig } = setup();
      const a = rig.connect(Q("t=join&code=K7QF2"));
      a.send(JSON.stringify({ t: "signal", to: 1, data: { sdp: "x".repeat(config.max_text_bytes) } }));
      expect(a.texts.at(-1)).toEqual({ t: "error", code: "too_big" });
      expect(a.closed).toBe(4413);
      const b = rig.connect(Q("t=join&code=K7QF2"));
      b.send(JSON.stringify({ t: "signal", to: 1, data: { sdp: "x".repeat(config.max_text_bytes - 40) } }));
      expect(b.closed).toBeNull();
    });

    test("limit: text size counts utf-8 bytes", () => {
      const { rig } = setup();
      const a = rig.connect(Q("t=join&code=K7QF2"));
      a.send(JSON.stringify({ t: "signal", to: 1, data: { s: "ç".repeat(config.max_text_bytes / 2) } }));
      expect(a.closed).toBe(4413);
    });

    test("limit: binary too big", () => {
      const { rig } = setup();
      const a = rig.connect(Q("t=join&code=K7QF2"));
      const ok = new Uint8Array(config.max_binary_bytes);
      ok[0] = 1;
      a.send(ok);
      expect(a.closed).toBeNull();
      const big = new Uint8Array(config.max_binary_bytes + 1);
      big[0] = 1;
      a.send(big);
      expect(a.closed).toBe(4413);
    });

    test("limit: rate bucket (burst, then refill)", () => {
      const { rig, host } = setup();
      for (let i = 0; i < config.rate_burst; i++) host.send('{"t":"lock","locked":false}');
      expect(host.closed).toBeNull();
      rig.now += 1000; // refills rate_msgs_per_s tokens
      for (let i = 0; i < config.rate_msgs_per_s; i++) host.send('{"t":"lock","locked":false}');
      expect(host.closed).toBeNull();
      host.send('{"t":"lock","locked":false}');
      expect(host.texts.at(-1)).toEqual({ t: "error", code: "rate_limited" });
      expect(host.closed).toBe(4429);
    });

    test("limit: hibernation resets only the volatile bucket", () => {
      const { rig, host } = setup();
      for (let i = 0; i < config.rate_burst; i++) host.send('{"t":"lock","locked":false}');
      rig.hibernate();
      host.send('{"t":"lock","locked":false}');
      expect(host.closed).toBeNull();
      expect(host.id).toBe(1);
    });

    test("limit: invalid json, non-object and unknown type", () => {
      const { rig } = setup();
      for (const bad of ["not json", "[1]", "42", '{"t":"nope"}', "{}"]) {
        const c = rig.connect(Q("t=join&code=K7QF2"));
        c.send(bad);
        expect(c.closed).toBe(4400);
      }
    });

    test("limit: name is cut and cleaned", () => {
      const rig = new Rig(mode);
      rig.connect(Q("t=create&name=" + encodeURIComponent("  Cacador\u0007 de Javalis Bravos ")));
      const a = rig.connect(Q("t=join&code=K7QF2"));
      expect(a.texts[0].peers[0].name).toBe("Cacador de J");
      expect(Array.from(a.texts[0].peers[0].name).length).toBeLessThanOrEqual(config.max_name_chars);
    });

    test("limit: room age checked on join and on message", () => {
      const { rig, host } = setup();
      const a = rig.connect(Q("t=join&code=K7QF2"));
      rig.now += config.room_max_age_s * 1000 - 1;
      expect(rig.connect(Q("t=join&code=K7QF2")).id).toBe(3);
      rig.now += 2;
      const late = rig.connect(Q("t=join&code=K7QF2"));
      expect(late.texts).toEqual([{ t: "error", code: "expired" }]);
      expect(late.closed).toBe(4408);
      a.send('{"t":"ping"}');
      expect(a.texts.at(-1)).toEqual({ t: "error", code: "expired" });
      expect(a.closed).toBe(4408);
      expect(host.closed).toBe(4408);
    });

    test("limit: max_peers_per_room is honored when configured lower", () => {
      const rig = new Rig(mode, { ...config, max_peers_per_room: 2 });
      rig.connect(Q("t=create"));
      expect(rig.connect(Q("t=join&code=K7QF2")).id).toBe(2);
      expect(rig.connect(Q("t=join&code=K7QF2")).closed).toBe(4403);
    });
  });
}

describe("helpers", () => {
  test("makeCode uses the alphabet and length", () => {
    let n = 0;
    const code = makeCode(config, () => (n++ * 7) % 33 / 33);
    expect(code.length).toBe(config.room_code_length);
    for (const ch of code) expect(config.room_code_alphabet.includes(ch)).toBe(true);
    expect(config.room_code_alphabet).not.toMatch(/[IO01]/);
    for (let i = 0; i < 200; i++) expect(makeCode(config, Math.random)).toMatch(/^[A-HJ-NP-Z2-9]{5}$/);
  });

  test("parseHello", () => {
    expect(parseHello("wss://h/ws?t=join&code=abc12&v=0.4.0&proto=1&name=Ana&want=3"))
      .toEqual({ t: "join", code: "ABC12", v: "0.4.0", proto: 1, name: "Ana", want: 3 });
    expect(parseHello("/ws?t=create&v=0.4.0&proto=1")).toEqual({ t: "create", code: "", v: "0.4.0", proto: 1, name: "", want: 0 });
    expect(parseHello("/ws?t=create&v=0.4.0&proto=x")).toBeNull();
    expect(parseHello("/ws")).toBeNull();
  });
});

describe("rooms.js is neutral", () => {
  test("no import and no runtime API", async () => {
    const raw = await Bun.file(new URL("./rooms.js", import.meta.url)).text();
    const src = raw.split(/\r?\n/).filter((l) => !l.trim().startsWith("//")).join(" ");
    expect(src).not.toMatch(/^\s*import\s/m);
    expect(src).not.toMatch(/\b(Bun|process|require|WebSocketPair|Deno)\b/);
  });
});
