# golem-echo-hands: the only way an Echo can do anything besides talk. It runs outside Echo's zone, on my
# screen, and listens on a socket in Echo's folder. When an Echo asks to use an extension, it asks ME
# (once / always / never) the first time, runs the extension in its own zone, and writes down every action.
# Extensions live where Echo can't write: ~/.local/share/golem-echo/extensions/<name>/
#   extension.json  {"does": "what it does, in plain words", "needs": ["clipboard", ...], "zone": "red"}
#   <name>          a script (sh, bash or python3): it gets Echo's words on its input and answers on its output
# Permissions live where Echo can't write either: ~/.config/golem-echo/permissions.json
import json
import os
import signal
import socket
import subprocess
import threading
import time

HOME = os.path.expanduser("~")
D = os.path.join(HOME, "zones", "golem-echo", "echo")
SOCK = os.path.join(D, "hands.sock")
EXT = os.path.join(HOME, ".local", "share", "golem-echo", "extensions")
PERM = os.path.join(HOME, ".config", "golem-echo", "permissions.json")
ZONES = ("red", "offline", "yellow", "green")
running = {}
lock = threading.Lock()


def log(msg):
    subprocess.run(["logger", "-t", "golem", "Echo: " + msg], check=False)


def load(p, default):
    try:
        with open(p, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def write(p, data):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p + ".new", "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    os.replace(p + ".new", p)


def extensions():
    out = {}
    for n in sorted(os.listdir(EXT)) if os.path.isdir(EXT) else []:
        meta = load(os.path.join(EXT, n, "extension.json"), None)
        prog = os.path.join(EXT, n, n)
        if isinstance(meta, dict) and os.access(prog, os.X_OK):
            z = meta.get("zone", "red")
            out[n] = {"does": str(meta.get("does", "")), "needs": [str(x) for x in meta.get("needs", [])],
                      "zone": z if z in ZONES else "red"}
    return out


def mirror():
    """Copies for the app to show (Echo can read these; changing them changes nothing)."""
    write(os.path.join(D, "extensions.json"), extensions())
    write(os.path.join(D, "permissions.json"), load(PERM, {}))


def action(rec):
    rec["t"] = time.strftime("%Y-%m-%d %H:%M:%S")
    with open(os.path.join(D, "actions.jsonl"), "a", encoding="utf-8") as f:
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")


def allowed(echo, name, ext):
    perms = load(PERM, {})
    key = f"{echo}/{name}"
    if perms.get(key) in ("always", "never"):
        return perms[key] == "always"
    q = f"ECHO {echo.upper()} WANTS TO USE {name.upper()}: {ext['does']} (needs: {', '.join(ext['needs']) or 'nothing'}; zone {ext['zone'].upper()})"
    r = subprocess.run(["golem-ask", q, "only this time", "always", "never", "not now"], capture_output=True, text=True)
    ans = r.stdout.strip()
    if ans in ("always", "never"):
        perms[key] = ans
        write(PERM, perms)
        mirror()
        log(f"I said {ans} to {echo} using {name}")
    return ans in ("only this time", "always")


def command(name, z):
    """The zone's sandbox can't see my home, so a script is handed to its interpreter as text (sh, bash, python3)."""
    prog = os.path.join(EXT, name, name)
    if z == "green":
        return ["zone", "green", prog]
    with open(prog, encoding="utf-8", errors="replace") as f:
        text = f.read()
    first = text.splitlines()[0] if text else ""
    interp = first[2:].split() if first.startswith("#!") else ["sh"]
    if interp and os.path.basename(interp[0]) == "env":
        interp = interp[1:]
    if not interp or os.path.basename(interp[0]) not in ("sh", "bash", "python3", "python"):
        interp = ["sh"]
    return ["zone", z, interp[0], "-c", text]


def use(echo, name, give):
    exts = extensions()
    if name not in exts:
        return {"ok": False, "why": f"there is no extension called {name}"}
    ext = exts[name]
    if not allowed(echo, name, ext):
        action({"echo": echo, "use": name, "give": give[:300], "ok": False, "why": "not allowed"})
        log(f"{echo} was not allowed to use {name}")
        return {"ok": False, "why": "I did not allow it"}
    env = dict(os.environ, ECHO_NAME=echo)
    if "screen" not in ext["needs"]:
        env.pop("DISPLAY", None)                  # no screen unless it needs one
    p = subprocess.Popen(command(name, ext["zone"]), stdin=subprocess.PIPE,
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=env, start_new_session=True)
    with lock:
        running[p.pid] = p
    try:
        out, _ = p.communicate(give, timeout=120)
        ok, why = p.returncode == 0, "" if p.returncode == 0 else f"it stopped with code {p.returncode}"
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL)
        out, ok, why = "", False, "it took longer than 2 minutes, so it was stopped"
    finally:
        with lock:
            running.pop(p.pid, None)
    out = (out or "")[:4000]
    action({"echo": echo, "use": name, "give": give[:300], "ok": ok, "out": out[:300], "why": why})
    log(f"{echo} used {name}" + ("" if ok else f" ({why})"))
    return {"ok": ok, "out": out, "why": why}


def train(slug):
    """I pressed TRAIN: the trainer runs in its own zone (OFFLINE, NVIDIA allowed) and writes its progress."""
    if not slug.replace("-", "").isalnum() or not os.path.isdir(os.path.join(D, "echos", slug)):
        return {"ok": False, "why": "no such Echo"}
    if subprocess.run(["golem-echo-trainer", "check"], capture_output=True).returncode:
        return {"ok": False, "why": "the trainer isn't set up yet: in a terminal, type golem-echo-trainer"}
    with lock:
        if any(getattr(p, "golem_train", None) for p in running.values()):
            return {"ok": False, "why": "an Echo is already training"}
    env = dict(os.environ)
    env.pop("DISPLAY", None)                      # no window, no room
    p = subprocess.Popen(["zone", "golem-echo-train", slug], env=env, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
    p.golem_train = slug
    with lock:
        running[p.pid] = p

    def wait():
        p.wait()
        with lock:
            running.pop(p.pid, None)
    threading.Thread(target=wait, daemon=True).start()
    action({"echo": slug, "use": "TRAIN", "give": "", "ok": True, "out": "started on the NVIDIA card"})
    log(f"training {slug} started")
    return {"ok": True}


def stop():
    with lock:
        for p in list(running.values()):
            try:
                os.killpg(p.pid, signal.SIGKILL)
            except OSError:
                pass
    action({"echo": "-", "use": "STOP", "ok": True})


def serve(conn):
    with conn:
        try:
            req = json.loads(conn.makefile("r", encoding="utf-8").readline())
            if req.get("stop"):
                stop()
                res = {"ok": True}
            elif "forget" in req:                 # taking a permission away is always fine
                perms = load(PERM, {})
                perms.pop(str(req["forget"]), None)
                write(PERM, perms)
                mirror()
                log(f"permission forgotten: {req['forget']}")
                res = {"ok": True}
            elif "train" in req:
                res = train(str(req["train"]))
            elif "use" in req:
                res = use(str(req.get("echo", "?"))[:40], str(req["use"]), str(req.get("give", ""))[:4000])
            else:
                mirror()
                res = {"ok": True}
        except (ValueError, OSError, AttributeError) as err:
            res = {"ok": False, "why": str(err)}
        try:
            conn.sendall((json.dumps(res, ensure_ascii=False) + "\n").encode())
        except OSError:
            pass


def main():
    os.makedirs(D, exist_ok=True)
    os.makedirs(EXT, exist_ok=True)
    mirror()
    if os.path.exists(SOCK):
        os.unlink(SOCK)
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.bind(SOCK)
    os.chmod(SOCK, 0o600)
    s.listen(4)
    while True:
        conn, _ = s.accept()
        threading.Thread(target=serve, args=(conn,), daemon=True).start()


if __name__ == "__main__":
    main()
