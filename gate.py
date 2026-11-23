"""golem-gate: the Gate. The only way from my apps to the internet.

Every app reaches the internet through here (the firewall stops any other way for my user).
For each connection the Gate finds out which app it is (and its zone) and which site it wants:
  * if I already said ALWAYS or NEVER for that app and site, that's done;
  * otherwise it asks me on the screen (through golem-gate-ask): once / always / never.
    No answer within a minute means no.
Everything is written down: one plain sentence in the truth log, and one line of JSON in
/var/lib/golem-gate/feed.jsonl (for my AI to watch). Nothing is ever read inside the connections.

  127.0.0.1:3128   the proxy apps use (http_proxy / https_proxy point here)
  /run/golem-gate/ask.sock      golem-gate-ask (in my session) waits here for questions
  /run/golem-gate/control.sock  golem-gate on|off|status|rules|forget APP SITE (my user only)
Modes: normal (ask), hidden (ask, and everything goes through Tor), off (nothing goes out).
Rules: /var/lib/golem-gate/rules.json

HIDDEN (Tor), plainly: sites can't see where I am, and my Wi-Fi or internet company can't see which
sites I visit; .onion sites open. But my Wi-Fi can see that I use Tor, a site I log in to knows it's me,
and files I download can still give me away. Tor itself stays switched off (it makes no connections at
all) until I turn HIDDEN on.
"""
import asyncio
import json
import os
import re
import socket
import struct
import subprocess
import syslog
import time

STATE = "/var/lib/golem-gate"
RUN = "/run/golem-gate"
RULES = f"{STATE}/rules.json"
FEED = f"{STATE}/feed.jsonl"
MODE = f"{STATE}/mode"
OWNER = int(os.environ.get("GOLEM_GATE_OWNER", "1000"))
TOR_SOCKS = ("127.0.0.1", 9050)
TOR_CONTROL = "/run/tor/control"
PROBE = ("1.1.1.1", 443)            # golem-net-test asks only "could I get out?": no data, no question

syslog.openlog("golem-gate")
asker = None                         # (reader, writer) of golem-gate-ask, when my session is up
pending = {}                         # question id -> future
waiting = {}                         # (app, site) -> future: one question at a time per app and site
qid = 0


def say(msg):
    syslog.syslog(msg)


def feed(**kw):
    kw["time"] = time.strftime("%Y-%m-%dT%H:%M:%S")
    try:
        with open(FEED, "a") as f:
            f.write(json.dumps(kw) + "\n")
    except OSError:
        pass


def load(path, default):
    try:
        with open(path) as f:
            return json.load(f) if path.endswith(".json") else f.read().strip()
    except (OSError, ValueError):
        return default


def save_rules(rules):
    tmp = RULES + ".tmp"
    with open(tmp, "w") as f:
        json.dump(rules, f, indent=1, sort_keys=True)
    os.chmod(tmp, 0o644)
    os.replace(tmp, RULES)


def mode():
    return load(MODE, "normal") or "normal"


async def tor_network(on):
    """Tor connects to its network only while HIDDEN is on (DisableNetwork otherwise)."""
    try:
        r, w = await asyncio.wait_for(asyncio.open_unix_connection(TOR_CONTROL), 5)
        w.write(b"AUTHENTICATE\r\n" + f"SETCONF DisableNetwork={0 if on else 1}\r\n".encode() + b"QUIT\r\n")
        await w.drain()
        reply = (await asyncio.wait_for(r.read(), 5)).decode(errors="replace")
        w.close()
        return reply.count("250") >= 2
    except (OSError, asyncio.TimeoutError):
        return False


async def through_tor(host, port):
    """A connection to host:port through Tor's SOCKS port; the name is looked up inside Tor too."""
    r, w = await asyncio.open_connection(*TOR_SOCKS)
    w.write(b"\x05\x01\x00")
    await w.drain()
    if (await r.readexactly(2)) != b"\x05\x00":
        raise ConnectionError("Tor refused")
    name = host.encode()
    w.write(b"\x05\x01\x00\x03" + bytes([len(name)]) + name + struct.pack(">H", port))
    await w.drain()
    head = await r.readexactly(4)
    if head[1] != 0:
        raise ConnectionError("Tor could not reach it" if head[1] != 1 else "Tor isn't ready yet")
    skip = {1: 4, 4: 16}.get(head[3])
    if skip is None:
        skip = (await r.readexactly(1))[0]
    await r.readexactly(skip + 2)
    return r, w


def site_of(host):
    """github.com for api.github.com; an address stays an address."""
    host = host.strip("[]").lower().rstrip(".")
    if re.fullmatch(r"[0-9.]+|[0-9a-f:]+", host):
        return host
    parts = host.split(".")
    if len(parts) >= 3 and parts[-2] in ("co", "com", "net", "org", "gov", "ac", "edu") and len(parts[-1]) == 2:
        return ".".join(parts[-3:])
    return ".".join(parts[-2:])


def app_of(port):
    """Which app opened this connection to the Gate: 'firefox', 'YELLOW' (from its zone), or the program name."""
    try:
        out = subprocess.run(["ss", "-Htnp", "state", "established", f"( sport = :{port} )"],
                             capture_output=True, text=True, timeout=3).stdout
    except (OSError, subprocess.TimeoutExpired):
        return "unknown", "?"
    m = re.search(r"pid=(\d+)", out)
    if not m:
        return "unknown", "?"
    pid = m.group(1)
    try:
        cg = open(f"/proc/{pid}/cgroup").read()
        comm = open(f"/proc/{pid}/comm").read().strip()
    except OSError:
        return "unknown", "?"
    z = re.search(r"zone-(red|offline|yellow|green)-([^/]+?)-\d+\.scope", cg)
    if z:
        return z.group(2), z.group(1).upper()
    return comm, "not in a zone"


async def ask(app, zone, site):
    """once / always / never, from me; 'never' if no one can be asked or no answer comes."""
    global qid
    key = (app, zone, site)
    if key in waiting:
        return await asyncio.shield(waiting[key])
    if not asker:
        return "no one to ask"
    qid += 1
    fut = asyncio.get_running_loop().create_future()
    pending[qid] = fut
    waiting[key] = fut
    try:
        asker[1].write((json.dumps({"id": qid, "app": app, "zone": zone, "site": site}) + "\n").encode())
        await asker[1].drain()
        return await asyncio.wait_for(asyncio.shield(fut), 60)
    except (asyncio.TimeoutError, OSError, ConnectionError):
        return "no answer"
    finally:
        pending.pop(qid, None)
        waiting.pop(key, None)


async def decide(app, zone, site):
    if mode() == "off":
        return False, "the Gate is OFF"
    rules = load(RULES, {})
    r = rules.get(f"{app}|{zone}|{site}")
    if r in ("always", "never"):
        return r == "always", r
    if rules.get(f"{app}|{zone}|*") == "always":
        return True, "any site, for this app"
    a = await ask(app, zone, site)
    if a in ("always", "never", "anywhere"):
        rules = load(RULES, {})
        if a == "anywhere":
            rules[f"{app}|{zone}|*"] = "always"
            say(f"I decided: {app} ({zone}) may reach any site (each one is still written down)")
        else:
            rules[f"{app}|{zone}|{site}"] = a
            say(f"I decided: {app} ({zone}) may {'always' if a == 'always' else 'never'} reach {site}")
        save_rules(rules)
    return a in ("once", "always", "anywhere"), a


async def pipe(src, dst, count):
    try:
        while True:
            data = await src.read(65536)
            if not data:
                break
            count[0] += len(data)
            dst.write(data)
            await dst.drain()
    except (ConnectionError, OSError):
        pass
    finally:
        try:
            dst.close()
        except OSError:
            pass


async def client(reader, writer):
    start = time.time()
    port = writer.get_extra_info("peername")[1]
    try:
        head = await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"), 30)
    except (asyncio.TimeoutError, asyncio.IncompleteReadError, asyncio.LimitOverrunError, ConnectionError):
        writer.close()
        return
    first = head.split(b"\r\n", 1)[0].decode("latin-1")
    parts = first.split()
    if len(parts) != 3:
        writer.close()
        return
    method, target, version = parts
    if method == "CONNECT":
        host, _, p = target.rpartition(":")
        host, tport, rest = host, int(p or 443), b""
    else:
        m = re.match(r"http://([^/:]+)(?::(\d+))?(/.*)?$", target)
        if not m:
            writer.write(b"HTTP/1.1 400 Bad Request\r\n\r\n")
            writer.close()
            return
        host, tport = m.group(1), int(m.group(2) or 80)
        path = m.group(3) or "/"
        lines = head.split(b"\r\n")
        keep = [line for line in lines[1:] if line and not line.lower().startswith((b"proxy-", b"connection:"))]
        rest = f"{method} {path} {version}\r\n".encode() + b"\r\n".join(keep) + b"\r\nConnection: close\r\n\r\n"
    probe = method == "CONNECT" and (host, tport) == PROBE and b"x-golem-probe" in head.lower()
    app, zone = app_of(port)
    site = site_of(host)
    if probe:
        ok, why = mode() != "off", "the test"
    else:
        ok, why = await decide(app, zone, site)
    if not ok:
        writer.write(b"HTTP/1.1 403 Forbidden\r\nContent-Type: text/plain\r\n\r\nThe Gate said no.\r\n")
        writer.close()
        if not probe:
            say(f"{app} ({zone}) was stopped from reaching {site} ({why})")
            feed(app=app, zone=zone, site=site, host=host, port=tport, allowed=False, why=why)
        return
    hidden = mode() == "hidden"
    try:
        if hidden:
            up_r, up_w = await asyncio.wait_for(through_tor(host, tport), 60)
        else:
            up_r, up_w = await asyncio.wait_for(asyncio.open_connection(host, tport), 20)
    except (OSError, asyncio.TimeoutError, asyncio.IncompleteReadError) as e:
        writer.write(b"HTTP/1.1 502 Bad Gateway\r\n\r\n")
        writer.close()
        if not probe:
            say(f"{app} ({zone}) could not reach {site}{' through Tor' if hidden else ''}: {e or e.__class__.__name__}")
        return
    if method == "CONNECT":
        writer.write(b"HTTP/1.1 200 Connection established\r\n\r\n")
        if probe:
            writer.close()
            up_w.close()
            return
    else:
        up_w.write(rest)
    sent, got = [0], [0]
    await asyncio.gather(pipe(reader, up_w, sent), pipe(up_r, writer, got))
    secs = time.time() - start
    say(f"{app} ({zone}) talked to {site}{', hidden through Tor' if hidden else ''} ({why}): "
        f"{size(got[0])} in, {size(sent[0])} out, {secs:.0f} s")
    feed(app=app, zone=zone, site=site, host=host, port=tport, allowed=True, why=why, hidden=hidden,
         bytes_in=got[0], bytes_out=sent[0], seconds=round(secs, 1))


def size(n):
    for unit in ["bytes", "KB", "MB", "GB"]:
        if n < 1024 or unit == "GB":
            return f"{n:.0f} {unit}" if unit == "bytes" else f"{n:.1f} {unit}"
        n /= 1024


def peer_uid(writer):
    sock = writer.get_extra_info("socket")
    try:
        creds = sock.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i"))
        return struct.unpack("3i", creds)[1]
    except OSError:
        return -1


async def asker_conn(reader, writer):
    global asker
    if peer_uid(writer) not in (OWNER, 0):
        writer.close()
        return
    asker = (reader, writer)
    say("Asking is ready: the Gate can ask me")
    try:
        while True:
            line = await reader.readline()
            if not line:
                break
            try:
                a = json.loads(line)
            except ValueError:
                continue
            fut = pending.get(a.get("id"))
            if fut and not fut.done():
                fut.set_result(a.get("answer") if a.get("answer") in ("once", "always", "never", "anywhere") else "no, this time")
    finally:
        if asker and asker[1] is writer:
            asker = None


async def control(reader, writer):
    if peer_uid(writer) not in (OWNER, 0):
        writer.close()
        return
    cmd = (await reader.readline()).decode(errors="replace").split()
    out = ""
    if cmd[:1] in (["on"], ["off"], ["hidden"]):
        m = {"on": "normal", "off": "off", "hidden": "hidden"}[cmd[0]]
        with open(MODE, "w") as f:
            f.write(m + "\n")
        tor = await tor_network(m == "hidden")
        say({"normal": "The Gate is now ON: it asks, and connections go out directly",
             "off": "The Gate is now OFF: nothing goes out",
             "hidden": "The Gate is now HIDDEN: everything goes through Tor. Sites can't see where I am and my "
                       "Wi-Fi can't see which sites; but my Wi-Fi sees that I use Tor, and a site I log in to knows me"}[m]
            + ("" if tor or m != "hidden" else " (Tor didn't answer yet)"))
        out = m
    elif cmd[:1] == ["status"]:
        out = f"mode {mode()}; asking {'ready' if asker else 'not running'}; {len(load(RULES, {}))} rules"
    elif cmd[:1] == ["rules"]:
        out = "\n".join(f"{k.replace('|', '  ')}  {v}" for k, v in sorted(load(RULES, {}).items())) or "(no rules yet)"
    elif cmd[:1] == ["forget"] and len(cmd) == 4:
        rules = load(RULES, {})
        key = "|".join(cmd[1:4])
        if rules.pop(key, None):
            save_rules(rules)
            say(f"I took back the rule for {cmd[1]} ({cmd[2]}) and {cmd[3]}: it will ask again")
            out = "forgotten"
        else:
            out = "no such rule"
    else:
        out = "golem-gate on | hidden | off | status | rules | forget APP ZONE SITE"
    writer.write((out + "\n").encode())
    await writer.drain()
    writer.close()


async def main():
    os.makedirs(STATE, exist_ok=True)
    os.chmod(STATE, 0o755)
    if not os.path.exists(RULES):
        save_rules({})
    for p in (f"{RUN}/ask.sock", f"{RUN}/control.sock"):
        try:
            os.unlink(p)
        except OSError:
            pass
    proxy = await asyncio.start_server(client, "127.0.0.1", 3128)
    a = await asyncio.start_unix_server(asker_conn, f"{RUN}/ask.sock")
    c = await asyncio.start_unix_server(control, f"{RUN}/control.sock")
    for p in (f"{RUN}/ask.sock", f"{RUN}/control.sock"):
        os.chmod(p, 0o666)            # who may really use them is checked by uid, above
    await tor_network(mode() == "hidden")
    say(f"The Gate is open for asking (mode {mode()})")
    async with proxy, a, c:
        await asyncio.gather(proxy.serve_forever(), a.serve_forever(), c.serve_forever())


if __name__ == "__main__":
    asyncio.run(main())
