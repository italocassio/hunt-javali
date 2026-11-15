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
      expect(host.texts).toEqual([{ t: "peer_joined", id: 2, name: "Ana", ep: 0 }]);
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

    test("leave: peer_left once, marked clean", () => {
      const { rig, host } = setup();
      const a = rig.connect(Q("t=join&code=K7QF2"));
      host.clear();
      a.send('{"t":"leave"}');
      rig.settle();
      expect(a.closed).toBe(1000);
      expect(host.texts).toEqual([{ t: "peer_left", id: 2, clean: true }]);
    });

    test("a client dropping sends peer_left", () => {
      const { rig, host } = setup();
      const a = rig.connect(Q("t=join&code=K7QF2"));
      rig.connect(Q("t=join&code=K7QF2"));
      host.clear();
      rig.drop(a);
      expect(host.texts).toEqual([{ t: "peer_left", id: 2 }]);
    });

    // --- F8: re-entry (docs/multiplayer.md section 4.7.2) ---

    const TOK_A = 123456;
    const TOK_B = 4294967295;
    const lock = (host, tokens) => host.send(JSON.stringify(tokens === undefined ? { t: "lock", locked: true } : { t: "lock", locked: true, tokens }));
    const rejoin = (rig, want, tok, extra = "") => rig.connect(Q(`t=join&code=K7QF2&name=Ana&want=${want}&tok=${tok}${extra}`));
    const hostMeta = (rig) => rig.socks[0].meta;

    test("lock stores, replaces and erases tokens", () => {
      const { rig, host } = setup();
      lock(host, { 2: TOK_A, 3: TOK_B });
      expect(hostMeta(rig).locked).toBe(true);
      expect(hostMeta(rig).tokens).toEqual({ 2: TOK_A, 3: TOK_B });
      lock(host, { 3: TOK_B });
      expect(hostMeta(rig).tokens).toEqual({ 3: TOK_B });
      lock(host);
      expect(hostMeta(rig).locked).toBe(true);
      expect(hostMeta(rig).tokens).toBeUndefined();
      lock(host, { 2: TOK_A });
      host.send('{"t":"lock","locked":false}');
      expect(hostMeta(rig).locked).toBe(false);
      expect(hostMeta(rig).tokens).toBeUndefined();
      host.send(JSON.stringify({ t: "lock", locked: false, tokens: { 2: TOK_A } }));
      expect(hostMeta(rig).tokens).toBeUndefined();
      expect(host.closed).toBeNull();
      lock(host, { 2: TOK_B, 3: TOK_B, 4: TOK_B });
      expect(JSON.stringify(hostMeta(rig)).length).toBeLessThan(2048);
    });

    test("lock refuses a malformed tokens map", () => {
      const bad = [[1, 2], "x", null, 7, { 1: 5 }, { 5: 5 }, { 2: 0 }, { 2: 4294967296 }, { 2: 1.5 }, { 2: "9" }, { a: 5 }, { "02": 5 }, { 2: -1 }];
      for (const tokens of bad) {
        const { rig, host } = setup();
        host.send(JSON.stringify({ t: "lock", locked: true, tokens }));
        expect(host.texts.at(-1)).toEqual({ t: "error", code: "bad_request" });
        expect(host.closed).toBe(4400);
        expect(hostMeta(rig).tokens).toBeUndefined();
      }
    });

    test("re-entry with the right token gets the same id in a locked room", () => {
      const { rig, host } = setup();
      const a = rig.connect(Q("t=join&code=K7QF2&name=Ana"));
      const b = rig.connect(Q("t=join&code=K7QF2&name=Beto"));
      lock(host, { 2: TOK_A, 3: TOK_B });
      rig.drop(a);
      host.clear();
      b.clear();
      const back = rejoin(rig, 2, TOK_A, "&ep=3");
      expect(back.closed).toBeNull();
      expect(back.texts).toEqual([{ t: "joined", code: "K7QF2", id: 2, peers: [{ id: 1, name: "Italo" }, { id: 3, name: "Beto" }] }]);
      expect(back.sock.meta.ep).toBe(3);
      expect(host.texts).toEqual([{ t: "peer_joined", id: 2, name: "Ana", ep: 3 }]);
      expect(b.texts).toEqual([{ t: "peer_joined", id: 2, name: "Ana", ep: 3 }]);
      // the largest u32 works too (10 digits)
      rig.drop(b);
      expect(rejoin(rig, 3, TOK_B).id).toBe(3);
    });

    test("re-entry without ep announces ep 0", () => {
      const { rig, host } = setup();
      const a = rig.connect(Q("t=join&code=K7QF2&name=Ana"));
      lock(host, { 2: TOK_A });
      rig.drop(a);
      host.clear();
      expect(rejoin(rig, 2, TOK_A).id).toBe(2);
      expect(host.texts).toEqual([{ t: "peer_joined", id: 2, name: "Ana", ep: 0 }]);
    });

    test("re-entry replaces a live socket even with 4 live connections", () => {
      const { rig, host } = setup();
      const a = rig.connect(Q("t=join&code=K7QF2&name=Ana"));
      const b = rig.connect(Q("t=join&code=K7QF2&name=Beto"));
      const c = rig.connect(Q("t=join&code=K7QF2&name=Cris"));
      lock(host, { 2: TOK_A, 3: 77, 4: 88 });
      for (const x of [host, a, b, c]) x.clear();
      const back = rejoin(rig, 2, TOK_A, "&ep=1");
      expect(back.id).toBe(2);
      expect(back.closed).toBeNull();
      // the old socket is told and closed; nobody hears a peer_left
      expect(a.texts).toEqual([{ t: "error", code: "replaced" }]);
      expect(a.closed).toBe(4411);
      expect(a.sock.meta.left).toBe(true);
      for (const x of [host, b, c]) expect(x.texts).toEqual([{ t: "peer_joined", id: 2, name: "Ana", ep: 1 }]);
      // the runtime reports the old socket closed later: nothing is emitted
      for (const x of [host, b, c, back]) x.clear();
      onClose(rig.peers(), rig.makePeer(a.sock));
      rig.drop(a);
      for (const x of [host, b, c, back]) expect(x.texts).toEqual([]);
      expect(rig.peers().length).toBe(4);
    });

    test("relay after the swap reaches only the new socket", () => {
      const { rig, host } = setup();
      const a = rig.connect(Q("t=join&code=K7QF2&name=Ana"));
      lock(host, { 2: TOK_A });
      const back = rejoin(rig, 2, TOK_A, "&ep=2");
      for (const x of [host, a, back]) x.clear();
      host.send(new Uint8Array([2, 0, 1, 9]));
      host.send(JSON.stringify({ t: "signal", to: 2, data: { kind: "answer", ep: 2 } }));
      expect(a.bins.length).toBe(0);
      expect(a.texts).toEqual([]);
      expect(Array.from(back.bins[0])).toEqual([1, 0, 1, 9]);
      expect(back.texts).toEqual([{ t: "signal", from: 1, data: { kind: "answer", ep: 2 } }]);
      // and the new socket talks to the host; the replaced one is ignored
      back.send(new Uint8Array([1, 0, 1, 4]));
      a.send(new Uint8Array([1, 0, 1, 5]));
      expect(host.bins.map((m) => Array.from(m))).toEqual([[2, 0, 1, 4]]);
    });

    test("bad_token: wrong token, slot without token, revoked slot, unlocked room", () => {
      const { rig, host } = setup();
      const a = rig.connect(Q("t=join&code=K7QF2&name=Ana"));
      const b = rig.connect(Q("t=join&code=K7QF2&name=Beto"));
      const refused = (conn) => {
        expect(conn.texts).toEqual([{ t: "error", code: "bad_token" }]);
        expect(conn.closed).toBe(4401);
        expect(conn.sock.closeReason).toBe("bad_token");
      };
      // unlocked room (tokens never registered)
      refused(rejoin(rig, 2, TOK_A));
      lock(host, { 2: TOK_A });
      host.clear();
      a.clear();
      refused(rejoin(rig, 2, TOK_A + 1)); // wrong token
      refused(rejoin(rig, 3, TOK_A)); // slot without token
      refused(rejoin(rig, 0, TOK_A)); // no slot asked
      refused(rejoin(rig, 1, TOK_A)); // the host slot
      refused(rejoin(rig, 9, TOK_A)); // outside the room
      // a refused re-entry touches nobody
      expect(a.closed).toBeNull();
      expect(b.closed).toBeNull();
      expect(a.texts).toEqual([]);
      expect(host.texts).toEqual([]);
      lock(host, { 3: 55 }); // revoked: the lock was sent again without slot 2
      refused(rejoin(rig, 2, TOK_A));
      lock(host); // locked without tokens
      refused(rejoin(rig, 3, 55));
      lock(host, { 2: TOK_A });
      host.send('{"t":"lock","locked":false}'); // unlocked: tokens are gone
      refused(rejoin(rig, 2, TOK_A));
      host.send('{"t":"lock","locked":true}');
      refused(rejoin(rig, 2, TOK_A));
    });

    test("join without tok into a locked room is still in_progress", () => {
      const { rig, host } = setup();
      const a = rig.connect(Q("t=join&code=K7QF2&name=Ana"));
      lock(host, { 2: TOK_A });
      rig.drop(a);
      for (const q of ["t=join&code=K7QF2&want=2", "t=join&code=K7QF2&want=2&tok=0", "t=join&code=K7QF2&want=2&tok=", "t=join&code=K7QF2&want=2&ep=4"]) {
        const c = rig.connect(Q(q));
        expect(c.texts).toEqual([{ t: "error", code: "in_progress" }]);
        expect(c.closed).toBe(4423);
      }
    });

    test("entry errors come in order: not found, expired, version, then bad_token", () => {
      const { rig, host } = setup();
      rig.connect(Q("t=join&code=K7QF2&name=Ana"));
      lock(host, { 2: TOK_A });
      const nf = rig.connect(Q(`t=join&code=ZZZZZ&want=2&tok=${TOK_A}`));
      expect(nf.closed).toBe(4404);
      const vm = rig.connect(`t=join&code=K7QF2&v=0.3.9&proto=1&want=2&tok=${TOK_A + 1}`);
      expect(vm.texts).toEqual([{ t: "error", code: "version_mismatch", host_v: "0.4.0" }]);
      expect(vm.closed).toBe(4426);
      const vmRight = rig.connect(`t=join&code=K7QF2&v=0.3.9&proto=1&want=2&tok=${TOK_A}`);
      expect(vmRight.closed).toBe(4426);
      expect(rig.peers().length).toBe(2); // the live slot 2 was not replaced by a refused entry
      rig.now += config.room_max_age_s * 1000 + 1;
      const old = rejoin(rig, 2, TOK_A);
      expect(old.texts).toEqual([{ t: "error", code: "expired" }]);
      expect(old.closed).toBe(4408);
    });

    test("re-entry ignores room_full and the token survives hibernation", () => {
      const { rig, host } = setup();
      const a = rig.connect(Q("t=join&code=K7QF2&name=Ana"));
      rig.connect(Q("t=join&code=K7QF2&name=Beto"));
      rig.connect(Q("t=join&code=K7QF2&name=Cris"));
      lock(host, { 2: TOK_A });
      rig.hibernate();
      rig.drop(a);
      rig.hibernate();
      const back = rejoin(rig, 2, TOK_A, "&ep=15");
      expect(back.id).toBe(2);
      expect(rig.peers().length).toBe(4);
      // a second fall and return: the token is still good
      rig.drop(back);
      expect(rejoin(rig, 2, TOK_A, "&ep=1").id).toBe(2);
    });

    test("peer_left is clean on leave and plain on a closed socket", () => {
      const { rig, host } = setup();
      const a = rig.connect(Q("t=join&code=K7QF2&name=Ana"));
      const b = rig.connect(Q("t=join&code=K7QF2&name=Beto"));
      host.clear();
      b.clear();
      rig.drop(a);
      expect(host.texts).toEqual([{ t: "peer_left", id: 2 }]);
      expect(b.texts).toEqual([{ t: "peer_left", id: 2 }]);
      host.clear();
      b.send('{"t":"leave"}');
      expect(b.closed).toBe(1000);
      expect(host.texts).toEqual([{ t: "peer_left", id: 3, clean: true }]);
      // a peer closed for misbehaving is not a clean exit
      const c = rig.connect(Q("t=join&code=K7QF2&name=Cris"));
      host.clear();
      c.send("not json");
      expect(host.texts).toEqual([{ t: "peer_left", id: c.id }]);
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
      .toEqual({ t: "join", code: "ABC12", v: "0.4.0", proto: 1, name: "Ana", want: 3, tok: 0, ep: 0 });
    expect(parseHello("/ws?t=create&v=0.4.0&proto=1"))
      .toEqual({ t: "create", code: "", v: "0.4.0", proto: 1, name: "", want: 0, tok: 0, ep: 0 });
    expect(parseHello("/ws?t=create&v=0.4.0&proto=x")).toBeNull();
    expect(parseHello("/ws")).toBeNull();
  });
});

describe("parseHello: tok and ep (F8)", () => {
  const J = (extra) => parseHello("/ws?t=join&code=ABC12&v=0.4.0&proto=1&want=2" + extra);

  test("valid values", () => {
    expect(J("&tok=123456&ep=3")).toEqual({ t: "join", code: "ABC12", v: "0.4.0", proto: 1, name: "", want: 2, tok: 123456, ep: 3 });
    expect(J("&tok=1").tok).toBe(1);
    expect(J("&tok=4294967295").tok).toBe(4294967295); // 10 digits: beyond the 9 of toInt
    expect(J("&tok=0000000007").tok).toBe(7);
    expect(J("&tok=5&ep=0").ep).toBe(0);
    expect(J("&tok=5&ep=15").ep).toBe(15);
    expect(J("&tok=5&ep=07").ep).toBe(7);
  });

  test("absent, empty or zero tok is a normal entry", () => {
    for (const extra of ["", "&tok=", "&tok=0", "&tok=0000000000"]) {
      const h = J(extra);
      expect(h.tok).toBe(0);
      expect(h.ep).toBe(0);
    }
  });

  test("invalid values are refused", () => {
    for (const extra of ["&tok=4294967296", "&tok=99999999999", "&tok=-1", "&tok=1.5", "&tok=abc", "&tok=1e3", "&tok=%201",
      "&tok=5&ep=16", "&tok=5&ep=-1", "&tok=5&ep=x", "&tok=5&ep=", "&tok=5&ep=1.0", "&ep=99", "&tok=5&ep=100"]) {
      expect(J(extra)).toBeNull();
    }
  });

  test("create ignores tok and ep", () => {
    expect(parseHello("/ws?t=create&v=0.4.0&proto=1&tok=abc&ep=99"))
      .toEqual({ t: "create", code: "", v: "0.4.0", proto: 1, name: "", want: 0, tok: 0, ep: 0 });
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
