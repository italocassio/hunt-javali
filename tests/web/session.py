"""Development helper: keeps one phone session alive and executes snippets dropped in an inbox folder.

    python tests/web/session.py <inbox_dir> [idle_timeout_s]

Each file <inbox>/NNN.py is exec'd with `p` (Phone) in scope; stdout goes to NNN.out. A file named
STOP ends the session (Chrome and the server are always killed on exit).
"""
import contextlib
import io
import os
import sys
import time
import traceback

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from phone import Phone  # noqa: E402


def main():
    inbox = sys.argv[1]
    idle = float(sys.argv[2]) if len(sys.argv) > 2 else 900.0
    os.makedirs(inbox, exist_ok=True)
    p = Phone("dev")
    try:
        p.start()
        ok = p.wait_game_loaded()
        with open(os.path.join(inbox, "READY"), "w") as f:
            f.write("loaded" if ok else "load-timeout")
        last = time.time()
        done = set()
        while time.time() - last < idle:
            if os.path.exists(os.path.join(inbox, "STOP")):
                break
            for name in sorted(os.listdir(inbox)):
                if not name.endswith(".py") or name in done:
                    continue
                done.add(name)
                last = time.time()
                buf = io.StringIO()
                with contextlib.redirect_stdout(buf):
                    try:
                        exec(compile(open(os.path.join(inbox, name), encoding="utf-8").read(), name, "exec"),
                             {"p": p, "time": time})
                    except Exception:
                        traceback.print_exc(file=buf)
                with open(os.path.join(inbox, name[:-3] + ".out"), "w", encoding="utf-8") as f:
                    f.write(buf.getvalue())
            time.sleep(0.3)
    finally:
        p.stop()


if __name__ == "__main__":
    main()
