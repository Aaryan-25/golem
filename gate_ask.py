"""golem-gate: talk to the Gate.

  golem-gate ask                  (started with my session) waits for the Gate's questions and asks me
                                  on the screen: ONCE / ALWAYS / NEVER. Esc means no, this time.
  golem-gate on | off             the Gate asks (on), or nothing goes out at all (off)
  golem-gate status | rules       how it stands; what I decided, app by app and site by site
  golem-gate forget APP ZONE SITE take back a decision: it will ask again
"""
import json
import socket
import subprocess
import sys
import time

RUN = "/run/golem-gate"
CHOICES = {"once": "ONCE: just this time", "always": "ALWAYS: this site, remember yes", "never": "NEVER: remember no",
           "anywhere": "ALWAYS: any site, for this app (each is still written down)"}


def ask_loop():
    while True:
        try:
            s = socket.socket(socket.AF_UNIX)
            s.connect(f"{RUN}/ask.sock")
            f = s.makefile("rw")
            for line in f:
                q = json.loads(line)
                where = q["zone"] if q["zone"] in ("RED", "OFFLINE", "YELLOW", "GREEN") else "outside the zones"
                title = f"THE GATE: {q['app']} ({where}) wants {q['site']}"
                r = subprocess.run(["golem-ask", title, *CHOICES.values()], capture_output=True, text=True)
                pick = r.stdout.strip()
                answer = next((k for k, v in CHOICES.items() if v == pick), "never_now")
                f.write(json.dumps({"id": q["id"], "answer": answer if answer in CHOICES else "deny"}) + "\n")
                f.flush()
        except (OSError, ValueError, KeyError):
            pass
        time.sleep(3)


def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        sys.exit(__doc__)
    if sys.argv[1] == "ask":
        ask_loop()
        return
    s = socket.socket(socket.AF_UNIX)
    try:
        s.connect(f"{RUN}/control.sock")
    except OSError:
        sys.exit("The Gate isn't running")
    s.sendall((" ".join(sys.argv[1:]) + "\n").encode())
    print(s.makefile().read().rstrip())


if __name__ == "__main__":
    main()
