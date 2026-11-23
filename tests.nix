# Automated tests: GitHub starts Golem in a virtual laptop and checks it, on every change.
# (The real laptop still has the last word: see TESTS.md.)
{ pkgs, modules, golemRev }:
pkgs.testers.runNixOSTest {
  name = "golem";
  node.specialArgs = { inherit golemRev; };
  node.pkgsReadOnly = false;    # Golem allows one closed part (NVIDIA's driver, nvidia.nix)
  # A small web server on the test network, for the internet part of the truth log.
  nodes.web = { ... }: {
    services.nginx = {
      enable = true;
      virtualHosts.web = { default = true; locations."/".return = "200 hello"; };
    };
    networking.firewall.allowedTCPPorts = [ 80 ];
  };
  nodes.machine = { lib, pkgs, ... }: {
    imports = modules;
    virtualisation.memorySize = 2048;
    virtualisation.qemu.options = [ "-device qemu-xhci,id=xhci" ];   # a USB port to plug things into
    networking.networkmanager.unmanaged = [ "eth1" ];               # the test network stays as the test set it
    environment.systemPackages = [ pkgs.socat pkgs.curl pkgs.xorg.xdpyinfo ];
    # Echo's hands: a tiny extension, allowed in advance, used once through the socket
    environment.etc."golem-test-echo.sh".text = ''
      x=$HOME/.local/share/golem-echo/extensions/say-hi
      mkdir -p "$x" "$HOME/.config/golem-echo"
      echo '{"does": "says hi", "needs": [], "zone": "red"}' > "$x/extension.json"
      printf '#!/bin/sh\necho "hi from $ECHO_NAME, got: $(cat)"\n' > "$x/say-hi"
      chmod +x "$x/say-hi"
      echo '{"Mitra/say-hi": "always"}' > "$HOME/.config/golem-echo/permissions.json"
      echo '{"echo": "Mitra", "use": "say-hi", "give": "abc"}' | socat -t 60 - UNIX-CONNECT:"$HOME/zones/golem-echo/echo/hands.sock"
      echo '{"echo": "Mitra", "use": "nothing-here", "give": ""}' | socat -t 10 - UNIX-CONNECT:"$HOME/zones/golem-echo/echo/hands.sock"
      echo '{"train": "mitra"}' | socat -t 10 - UNIX-CONNECT:"$HOME/zones/golem-echo/echo/hands.sock"
    '';
    # Wires: a file with my own function; the wires' code goes after it and uses it; the file then runs
    environment.etc."golem-test-wires.sh".text = ''
      set -e
      f=$HOME/wired.py
      printf 'def double(x):\n    return x * 2\n' > "$f"
      GOLEM_WIRES_URL_ONLY=1 golem-wires "$f" > /tmp/wires-url & p=$!
      for _ in $(seq 50); do [ -s /tmp/wires-url ] && break; sleep 0.2; done
      u=$(cat /tmp/wires-url)
      curl -s --noproxy '*' "$u" | grep -q '"name": "double"'
      curl -s --noproxy '*' -d '{"code": "box1 = 21\nbox2 = double(box1)\nprint(box2)", "boxes": {"boxes": []}}' "''${u}save"
      kill $p
      python3 "$f"
    '';
    environment.etc."golem-test-room.sh".text = ''
      if DISPLAY=:0 xdpyinfo >/dev/null 2>&1; then echo SEES-MY-SCREEN; else echo BLIND; fi
      echo "room=$DISPLAY"
      if xdpyinfo >/dev/null 2>&1; then echo ROOM-OK; fi
    '';
    # the test laptop's small disk is always nearly full: no drive alert here
    systemd.tmpfiles.rules = [ "f /var/lib/golem/settings.conf 0644 root root - alert_disk=off"
      # the test's own answer to the Gate, given once in advance: bash in YELLOW may always reach the test web server
      "d /var/lib/golem-gate 0755 golem-gate golem-gate -"
      "f /var/lib/golem-gate/rules.json 0644 golem-gate golem-gate - {\"bash|YELLOW|web\": \"always\", \"golem-browser|YELLOW|web\": \"always\"}" ];
    # through the Gate, the only way out (gate.nix)
    environment.etc."golem-test-long.sh".text = ''
      exec 3<>/dev/tcp/127.0.0.1/3128
      printf 'CONNECT web:80 HTTP/1.1\r\n\r\n' >&3
      sleep 90
    '';
    environment.etc."golem-test-fetch.sh".text = ''
      exec 3<>/dev/tcp/127.0.0.1/3128
      sleep 2
      printf 'GET http://web/ HTTP/1.0\r\nHost: web\r\n\r\n' >&3
      cat <&3 >/dev/null
    '';
    boot.loader.grub.enable = lib.mkForce false;     # the test machine starts the kernel directly
    boot.growPartition = lib.mkForce false;
  };

  enableOCR = true;      # lets the test read the screen when something goes wrong
  testScript = ''
    web.start()
    machine.wait_for_unit("multi-user.target")

    with subtest("Step 3: Wi-Fi off at start, no internet clock, nothing comes in"):
        machine.succeed("grep -q WirelessEnabled=false /var/lib/NetworkManager/NetworkManager.state")
        machine.fail("systemctl is-active systemd-timesyncd")
        machine.succeed("iptables -S | grep -q DROP")

    with subtest("Step 5: the key and window settings are valid"):
        machine.succeed("i3 -C -c /etc/i3/config")

    with subtest("Step A: Golem starts straight in, no lock screen"):
        if machine.execute("timeout 180 sh -c 'until pgrep -x i3 && pgrep -u lilgolemwitch -x xss-lock; do sleep 1; done'")[0] != 0:
            print(machine.execute("journalctl -b --no-pager -t golem -t login -t systemd-logind | tail -30; tail -30 /home/lilgolemwitch/.local/share/xorg/Xorg.0.log; ps aux | grep -E 'X|i3|startx' | grep -v grep")[1])
            raise Exception("the desktop did not start")
        machine.wait_for_x()
        machine.fail("pgrep i3lock")
        machine.sleep(3)

    with subtest("Step A: the text-only start exists, and golem-why answers"):
        machine.succeed("test -e /run/current-system/specialisation/text-only/etc/golem/text-only")
        machine.fail("test -e /etc/golem/text-only")
        out = machine.succeed("su - lilgolemwitch -c golem-why")
        assert "Problems on this start" in out, out

    realm_seen = "su - lilgolemwitch -c 'DISPLAY=:0 xdotool search --onlyvisible --class golem-realm'"

    with subtest("Step B: Golem wakes up into the Start panel; Esc goes to the desktop"):
        if machine.execute("timeout 120 sh -c 'until journalctl -b -t golem -o cat | grep -q \"The realm woke up\"; do sleep 1; done'")[0] != 0:
            print(machine.execute("set +e +o pipefail; journalctl -b -t golem --no-pager | tail -20; cat /run/user/1000/golem-realm.err; ps -u lilgolemwitch -o args; which golem-realm; grep -n realm $(ps -o args= -C i3 | awk '{print $3}') ; su - lilgolemwitch -c 'DISPLAY=:0 timeout 20 golem-realm --daemon; cat /run/user/1000/golem-realm.err' 2>&1 | tail -30")[1])
            raise Exception("the realm did not wake up")
        machine.wait_until_succeeds(realm_seen, timeout=30)
        machine.sleep(5)
        machine.screenshot("start_panel")
        machine.send_key("esc")
        machine.wait_until_fails(realm_seen, timeout=30)

    with subtest("Step B: Super+Escape brings it back; SLUMBER opens its own list; Esc twice leaves"):
        machine.send_key("meta_l-esc")
        machine.wait_until_succeeds(realm_seen, timeout=30)
        machine.sleep(3)
        for _ in range(5):
            machine.send_key("down")
            machine.sleep(1)
        machine.send_key("ret")
        machine.sleep(2)
        machine.screenshot("slumber")
        machine.succeed(realm_seen)
        machine.send_key("esc")
        machine.sleep(1)
        machine.succeed(realm_seen)
        machine.send_key("esc")
        machine.wait_until_fails(realm_seen, timeout=30)
        machine.fail("journalctl -b -t golem -o cat | grep -q 'Start panel: SLEEP'")

    def as_me(cmd):
        return machine.succeed(
            "su - lilgolemwitch -c 'export XDG_RUNTIME_DIR=/run/user/1000 "
            "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; " + cmd + "'"
        ).strip()

    with subtest("Step 5: Alt+Enter opens a terminal"):
        machine.sleep(5)                              # let the window manager settle
        machine.send_key("alt-ret")
        machine.wait_until_succeeds("pgrep -u lilgolemwitch -f bin/xterm", timeout=60)

    with subtest("Step C: windows as sand: maximise and back, minimise and bring back"):
        machine.sleep(2)
        machine.send_key("alt-f")
        machine.sleep(3)
        machine.send_key("alt-f")
        machine.sleep(3)
        machine.send_key("meta_l-m")
        machine.wait_until_succeeds("journalctl -b -t golem -o cat | grep -q 'WINDOW minimised'", timeout=30)
        machine.sleep(2)
        machine.send_key("meta_l-shift-m")
        machine.sleep(2)
        machine.wait_until_fails(realm_seen, timeout=30)
        machine.succeed("pgrep -u lilgolemwitch -f realm.py")
        machine.succeed("pgrep -u lilgolemwitch -f bin/xterm")
        machine.succeed("grep -q window_sand /etc/golem/settings-schema.json")

    def close_menu():
        for _ in range(10):
            machine.sleep(2)
            if machine.execute("pgrep -u lilgolemwitch rofi")[0] != 0:
                return
            machine.send_key("esc")
        raise Exception("Esc did not close the menu")

    with subtest("Step 5: Super+H shows the key list, Alt+Space the launcher"):
        machine.send_key("meta_l-h")
        machine.wait_until_succeeds("pgrep -u lilgolemwitch -f 'rofi.*KEYS'", timeout=60)
        close_menu()
        machine.send_key("alt-spc")
        if machine.execute("timeout 30 sh -c 'until pgrep -u lilgolemwitch -f rofi.*drun; do sleep 1; done'")[0] != 0:
            print(machine.execute("ps -u lilgolemwitch -o pid,args; journalctl -b --no-pager | grep -iE 'rofi|golem-launch|i3' | tail -30")[1])
            print(machine.execute("su - lilgolemwitch -c 'DISPLAY=:0 timeout 5 golem-launch' 2>&1 | tail -20")[1])
            raise Exception("Alt+Space did not open the launcher")
        close_menu()

    with subtest("Step 4: a RED app with a window opens (launched from the desktop)"):
        machine.succeed("su - lilgolemwitch -c 'DISPLAY=:0 i3-msg exec \"zone red xterm\"'")
        if machine.execute("timeout 40 sh -c 'until pgrep -f \"firejail.*xterm\" && [ $(pgrep -u lilgolemwitch -f bin/xterm | wc -l) -ge 2 ]; do sleep 1; done'")[0] != 0:
            print(machine.execute("journalctl -b --no-pager | grep -iE 'firejail|zone|xauth' | tail -20; ps -u lilgolemwitch -o args")[1])
            raise Exception("RED xterm did not open")

    with subtest("Idle: golem-idle starts when untouched and ends on the first touch"):
        machine.sleep(4)                              # untouched for a moment, as when the idle time comes
        machine.succeed("su - lilgolemwitch -c 'DISPLAY=:0 XSS_SLEEP_LOCK_FD=9 golem-idle 9</dev/null' >/dev/null 2>&1 &")
        machine.wait_until_succeeds("journalctl -b -t golem -o cat | grep -qx IDLE", timeout=30)
        machine.sleep(4)
        machine.succeed("pgrep -u lilgolemwitch -f bin/golem-idle")
        machine.send_key("shift")
        machine.wait_until_succeeds("journalctl -b -t golem -o cat | grep -qx AWAKE", timeout=30)
        machine.wait_until_fails("pgrep -u lilgolemwitch -f bin/golem-idle", timeout=30)
        machine.wait_until_succeeds("journalctl -b -t golem -o cat | grep -q 'The idle screen came'", timeout=30)
        machine.succeed(realm_seen)
        machine.sleep(2)
        machine.send_key("esc")
        machine.wait_until_fails(realm_seen, timeout=30)

    with subtest("Step 4: my folders exist"):
        for d in ["documents", "projects", "media", "zones"]:
            machine.succeed(f"test -d /home/lilgolemwitch/{d}")

    with subtest("Step 4: RED sees none of my files and has no internet"):
        assert as_me("zone red bash -c \"ls ~ | wc -l\"") == "0"
        assert as_me("zone red bash -c \"ip -o link | wc -l\"") == "1"   # only the loopback

    with subtest("Step 4: OFFLINE keeps its files in its own folder, no internet"):
        as_me("zone offline bash -c \"touch ~/hello\"")
        machine.succeed("test -f /home/lilgolemwitch/zones/bash/hello")
        assert as_me("zone offline bash -c \"ls ~\"") == "hello"
        assert as_me("zone offline bash -c \"ip -o link | wc -l\"") == "1"

    with subtest("Step 4: GREEN sees my folders, internet only if allowed"):
        assert "documents" in as_me("zone green bash -c \"ls ~\"")
        assert as_me("zone green bash -c \"ip -o link | wc -l\"") == "1"

    with subtest("Step 4: saved zones are used"):
        as_me("zone set bash yellow")  # (zones run without the screen here)
        assert "YELLOW" in as_me("zone show bash")
        assert as_me("zone bash -c \"ls ~ | grep -c documents || true\"") == "0"

    with subtest("Step 7: the truth log tells what happened, in plain words"):
        web.wait_for_unit("nginx.service")
        web.wait_for_open_port(80)
        machine.wait_for_unit("golem-netwatch.service")
        as_me("zone bash /etc/golem-test-fetch.sh")        # bash is YELLOW (internet allowed) by now
        machine.send_monitor_command("device_add usb-tablet,bus=xhci.0,id=t1")
        if machine.execute("timeout 60 sh -c 'until golem-truth --text | grep -q \"bash (YELLOW) talked to\"; do sleep 2; done'")[0] != 0:
            print(machine.execute("journalctl -u golem-netwatch --no-pager | tail -30; golem-truth --text | tail -8; sysctl net.netfilter.nf_conntrack_acct; conntrack -L 2>&1 | tail -5; timeout 8 conntrack -E -o id 2>&1 & sleep 1; zone_dummy=1; su - lilgolemwitch -c 'zone bash /etc/golem-test-fetch.sh'; sleep 7")[1])
            raise Exception("the internet connection was not written down")
        truth = machine.succeed("golem-truth --text")
        print(truth)
        for words in ["Opened xterm in RED", "Untouched for a while (idle)", "Touched again",
                      "The realm woke up", "Settings: bash: zone YELLOW", "USB plugged in",
                      "bash (YELLOW) talked to", "out,"]:
            assert words in truth, f"missing from the truth log: {words}"

    import json

    def ask_guard(req):
        machine.succeed("cat > /tmp/req.json << 'EOF'\n" + json.dumps(req) + "\nEOF")
        return as_me("socat -t 10 - UNIX-CONNECT:/run/golem-helper.sock < /tmp/req.json")

    def current():
        apps = {}
        for f in machine.succeed("ls /var/lib/golem/apps").split():
            text = machine.succeed(f"cat /var/lib/golem/apps/{f}")
            apps[f[:-5]] = dict(line.split("=", 1) for line in text.splitlines() if "=" in line)
        keys = [[p.strip() for p in line.split("|", 2)] for line in
                machine.succeed("grep -v '^#' /var/lib/golem/keys.conf").splitlines()]
        return apps, keys

    with subtest("Step 8: settings can't be changed behind the Control Panel's back"):
        machine.fail("su - lilgolemwitch -c 'touch /var/lib/golem/apps/sneaky.conf'")
        machine.fail("su - lilgolemwitch -c 'echo zone=green >> /var/lib/golem/apps/bash.conf'")
        assert "already has settings" in as_me("zone set bash green 2>&1 || true")

    with subtest("Step 8: a wrong password changes nothing"):
        apps, keys = current()
        apps["bash"]["zone"] = "green"
        assert "wrong password" in ask_guard({"do": "apply", "password": "nope", "apps": apps, "keys": []})
        machine.succeed("grep -q zone=yellow /var/lib/golem/apps/bash.conf")
        machine.wait_until_succeeds("golem-truth --text | grep -q 'Wrong password in the Control Panel'")

    with subtest("Step 8: with the password, an app's zone and a key change, and both are logged"):
        apps, keys = current()
        apps["bash"]["zone"] = "offline"
        apps["bash"]["internet"] = "never"
        for k in keys:
            if k[2].endswith("golem-truth"):
                k[0] = "Super+y"
        answer = ask_guard({"do": "apply", "password": "arise", "apps": apps, "keys": keys})
        if answer != "OK":
            print(machine.execute("journalctl -b --no-pager | grep -iE 'golem-helper|golem-panel|pam' | tail -20")[1])
        assert answer == "OK", answer
        machine.succeed("grep -q zone=offline /var/lib/golem/apps/bash.conf")
        machine.succeed("grep -q 'bindsym Mod4+y .*golem-truth' /var/lib/golem/keys.i3")
        truth = machine.succeed("golem-truth --text")
        assert "Settings: bash: zone offline, internet never" in truth, truth
        assert "Keys: Super+y now does: Truth log" in truth, truth
        assert as_me("zone bash -c \"ip -o link | wc -l\"") == "1"     # OFFLINE now: no internet

    with subtest("Step 8: the Control Panel opens with Super+Z and changes a zone with the keyboard"):
        machine.succeed("su - lilgolemwitch -c 'DISPLAY=:0 i3-msg -q reload'")
        machine.sleep(2)
        machine.send_key("meta_l-z")
        machine.wait_until_succeeds("pgrep -u lilgolemwitch -f panel.py", timeout=60)
        machine.wait_until_succeeds("golem-truth --text | grep -q 'Opened golem-panel in GREEN'", timeout=30)
        machine.sleep(4)
        machine.screenshot("panel_open")
        for key in ["e", "ret", "ret", "down", "ret"]:        # WEAVE > APPS > bash > zone > next zone
            machine.send_key(key)
            machine.sleep(1)
        machine.succeed("test -s /run/user/1000/golem-page-b.png")      # the page changes went through the sand
        machine.send_key("a")
        machine.sleep(1)
        machine.send_chars("arise\n")
        if machine.execute("timeout 30 sh -c 'until grep -q zone=yellow /var/lib/golem/apps/bash.conf; do sleep 1; done'")[0] != 0:
            print("SCREEN:", machine.get_screen_text())
            print(machine.execute("cat /var/lib/golem/apps/bash.conf; golem-truth --text | tail -5")[1])
            raise Exception("the panel did not apply the change")
        for key in ["esc", "esc", "esc"]:
            machine.send_key(key)
            machine.sleep(1)
        machine.wait_until_fails("pgrep -u lilgolemwitch -f panel.py", timeout=30)
        machine.screenshot("panel_done")

    with subtest("Truth log: a connection open for over a minute is written down while still open"):
        as_me("zone set bash yellow 2>/dev/null; true")
        apps, keys = current()
        apps["bash"]["zone"] = "yellow"
        apps["bash"]["internet"] = "allowed"
        assert ask_guard({"do": "apply", "password": "arise", "apps": apps, "keys": []}) == "OK"
        machine.succeed("su - lilgolemwitch -c 'export XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; zone bash /etc/golem-test-long.sh' >/dev/null 2>&1 &")
        machine.wait_until_succeeds("golem-truth --text | grep -q 'has been talking to .* (still open)'", timeout=120)

    with subtest("The Gate: no way out but through it; it asks me; my answer is kept and logged"):
        machine.wait_for_unit("golem-gate.service")
        machine.fail("su - lilgolemwitch -c 'timeout 5 bash -c \"echo > /dev/tcp/web/80\"'")      # straight out: refused
        machine.succeed("su - lilgolemwitch -c 'DISPLAY=:0 curl -s -o /tmp/gate-answer -w %{http_code} http://web/ > /tmp/gate-code' >/dev/null 2>&1 &")
        machine.wait_until_succeeds("pgrep -f 'THE GATE'", timeout=30)              # the question is on the screen
        machine.sleep(1)
        machine.screenshot("gate_asks")
        machine.send_key("esc")                                                     # no, this time
        machine.wait_until_succeeds("grep -q 403 /tmp/gate-code", timeout=30)
        machine.wait_until_succeeds("golem-truth --text | grep -q 'Gate: curl (not in a zone) was stopped from reaching web'", timeout=30)
        assert "web" in machine.succeed("tail -n 3 /var/lib/golem-gate/feed.jsonl")
        assert "bash  YELLOW  web  always" in as_me("golem-gate rules")
        assert as_me("golem-gate off") == "off"
        assert as_me("zone bash -c \"curl -s -o /dev/null -w %{http_code} http://web/\"") == "403"
        assert as_me("golem-gate on") == "normal"

    with subtest("HIDDEN: Tor is off until HIDDEN, then everything goes through it (no Tor network in the test)"):
        machine.wait_for_unit("tor.service")
        tor_net = "printf 'AUTHENTICATE\\r\\nGETCONF DisableNetwork\\r\\nQUIT\\r\\n' | socat - UNIX-CONNECT:/run/tor/control"
        assert "DisableNetwork=1" in machine.succeed(tor_net)
        assert as_me("golem-gate hidden") == "hidden"
        assert "DisableNetwork=0" in machine.succeed(tor_net)
        as_me("zone bash /etc/golem-test-fetch.sh")
        machine.wait_until_succeeds("golem-truth --text | grep -q 'could not reach web through Tor'", timeout=90)
        assert as_me("golem-gate on") == "normal"
        assert "DisableNetwork=1" in machine.succeed(tor_net)

    with subtest("The browser: in YELLOW, through the Gate, a page from the test web server"):
        as_me("DISPLAY=:0 golem-launch golem-browser http://web/ >/dev/null 2>&1 &")
        if machine.execute("timeout 120 sh -c 'until grep -q golem-browser /var/lib/golem-gate/feed.jsonl; do sleep 2; done'")[0] != 0:
            print(machine.execute("journalctl -b -t zone -t golem-gate --no-pager | tail -20; tail -5 /var/lib/golem-gate/feed.jsonl")[1])
            raise Exception("the browser did not reach the page through the Gate")
        machine.sleep(3)
        machine.screenshot("browser")
        assert "YELLOW" in machine.succeed("grep golem-browser /var/lib/golem-gate/feed.jsonl | tail -1")
        machine.execute("pkill -f browser.py")

    with subtest("The clock can be set by hand from the Control Panel, with the password, and it is logged"):
        assert "wrong password" in ask_guard({"do": "clock-set", "time": "2026-12-25 10:00", "password": "nope"})
        assert ask_guard({"do": "clock-set", "time": "2026-12-25 10:00", "password": "arise"}) == "OK"
        assert machine.succeed("date +%Y-%m-%d").strip() == "2026-12-25"
        machine.wait_until_succeeds("golem-truth --text | grep -q 'Clock set by hand'")

    with subtest("Settings: the system side runs at start; trackers are blocked by default"):
        machine.succeed("systemctl show -p Result --value golem-settings | grep -q success")
        machine.succeed("test $(grep -c ^0.0.0.0 /var/lib/golem/blocklist.hosts) -gt 50000")
        machine.succeed("grep -q addn-hosts /etc/NetworkManager/dnsmasq.d/golem-block.conf")

    with subtest("DRIVERS: switching the camera off means its driver can't load at all"):
        machine.succeed("modprobe uvcvideo && modprobe -r uvcvideo")
        assert ask_guard({"do": "apply", "password": "arise", "apps": current()[0], "keys": [],
                          "settings": {"camera": "off"}}) == "OK"
        machine.fail("modprobe uvcvideo")
        machine.wait_until_succeeds("golem-truth --text | grep -q 'Settings: Camera: off'")
        assert ask_guard({"do": "apply", "password": "arise", "apps": current()[0], "keys": [],
                          "settings": {"camera": "on"}}) == "OK"
        machine.succeed("modprobe uvcvideo")

    with subtest("LOOK: Super+I turns the face to Negative everywhere, at once"):
        machine.send_key("meta_l-i")
        machine.wait_until_succeeds("grep -q face=negative /var/lib/golem/settings.conf", timeout=30)
        machine.wait_until_succeeds("grep -q '${(import ./settings.nix).themeNegative.void}' /home/lilgolemwitch/zones/settings/face.i3", timeout=30)
        machine.screenshot("negative")
        machine.send_key("meta_l-i")
        machine.wait_until_succeeds("grep -q face=shadow /var/lib/golem/settings.conf", timeout=30)

    with subtest("The red alert covers the screen and goes away only after 3 presses"):
        machine.succeed("su - lilgolemwitch -c 'DISPLAY=:0 golem-alert Test alert' >/dev/null 2>&1 &")
        machine.wait_until_succeeds("pgrep -u lilgolemwitch -f 'alert.py Test'", timeout=30)
        machine.sleep(3)
        machine.screenshot("red_alert")
        machine.send_key("spc")
        machine.sleep(1)
        machine.succeed("pgrep -u lilgolemwitch -f 'alert.py Test'")
        machine.send_key("spc")
        machine.sleep(1)
        machine.send_key("spc")
        if machine.execute("timeout 20 sh -c 'while pgrep -u lilgolemwitch -f \"alert.py Test\"; do sleep 1; done'")[0] != 0:
            print("FOCUS:", machine.execute("su - lilgolemwitch -c 'DISPLAY=:0 xdotool getwindowfocus getwindowname; DISPLAY=:0 xprop -id $(DISPLAY=:0 xdotool getwindowfocus) WM_CLASS' 2>&1")[1])
            print(machine.execute("journalctl -b --no-pager | grep -iE 'alert|golem\\[' | tail -15")[1])
            print("SCREEN:", machine.get_screen_text())
            raise Exception("the red alert did not go away after 3 presses")
        machine.wait_until_succeeds("golem-truth --text | grep -q 'RED ALERT dismissed'")

    with subtest("Backups and save slots work through the guard"):
        assert ask_guard({"do": "backup-save", "name": "test1", "password": "arise"}) == "OK"
        machine.succeed("test -s /var/lib/golem/backups/test1.tar")
        assert ask_guard({"do": "backup-load", "name": "test1", "password": "arise"}) == "OK"
        assert "newest 3" in ask_guard({"do": "delete-version", "version": "1", "password": "arise"})

    with subtest("Firefox out: none in Golem; the preview window shows this computer only; Word/Excel helper"):
        machine.fail("su - lilgolemwitch -c 'command -v firefox'")
        machine.fail("su - lilgolemwitch -c 'DISPLAY=:0 golem-view https://example.com'")
        machine.succeed("su - lilgolemwitch -c 'echo \"<h1>LOCAL</h1>\" > /tmp/p.html'")
        machine.succeed("su - lilgolemwitch -c 'DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 golem-preview /tmp/p.html >/tmp/preview.log 2>&1 &'")
        if machine.execute("timeout 90 sh -c 'until su - lilgolemwitch -c \"DISPLAY=:0 xdotool search --class golem-preview\"; do sleep 2; done'")[0] != 0:
            print(machine.execute("cat /tmp/preview.log")[1])
            raise Exception("the preview window did not open")
        machine.execute("pkill -f golem-view; pkill -f golem-preview")
        out = machine.execute("su - lilgolemwitch -c 'golem-office open /etc/hostname'")[1]
        assert "WORD" in out, out

    with subtest("Rooms: a RED app gets its own sealed screen; the clipboard is carried only by hand"):
        out = as_me("DISPLAY=:0 zone red bash /etc/golem-test-room.sh")
        print(out)
        assert "BLIND" in out and "ROOM-OK" in out and "room=:2" in out, out
        as_me("DISPLAY=:0 zone red xterm >/dev/null 2>&1 &")
        machine.wait_until_succeeds("su - lilgolemwitch -c 'DISPLAY=:0 xdotool search --name \"ROOM | RED | xterm\"'", timeout=60)
        machine.sleep(2)
        machine.screenshot("room")
        room = machine.succeed("ls /tmp/.X11-unix | sort | tail -1").strip().replace("X", ":")
        machine.succeed("su - lilgolemwitch -c 'DISPLAY=:0 i3-msg -q \"[title=\\\"ROOM . RED . xterm\\\"] focus\"'")
        as_me("echo carried-secret | DISPLAY=:0 xclip -selection clipboard -i >/dev/null 2>&1")
        assert as_me(f"DISPLAY={room} xclip -selection clipboard -o 2>/dev/null || true") == ""     # not shared by itself
        as_me("DISPLAY=:0 golem-carry in")
        machine.sleep(1)
        assert as_me(f"DISPLAY={room} xclip -selection clipboard -o") == "carried-secret"
        machine.wait_until_succeeds("golem-truth --text | grep -q 'Clipboard carried into the room of RED xterm'", timeout=30)
        machine.execute("pkill -f 'bin/xterm'")

    with subtest("The optimiser: compressed memory, the freeze guard, the window I'm in first; reports need a key"):
        machine.succeed("swapon --show | grep -q zram")
        machine.wait_for_unit("earlyoom.service")
        machine.wait_until_succeeds("pgrep -u lilgolemwitch -f bin/golem-tune", timeout=30)
        assert "by charger" in machine.succeed("cat /etc/golem/settings-schema.json")
        out = machine.execute("su - lilgolemwitch -c golem-report")[1]
        assert "golem-report setup" in out, out

    with subtest("Clipboard history keeps the last 10 in memory, and forgets on request"):
        machine.wait_until_succeeds("pgrep -u lilgolemwitch -f 'golem-clip watch'", timeout=30)
        for i in range(12):
            as_me(f"echo copied-{i} | DISPLAY=:0 xclip -selection clipboard -i >/dev/null 2>&1")
            machine.sleep(1)
        d = "/run/user/1000/golem-clip"
        machine.wait_until_succeeds(f"grep -q copied-11 {d}/1", timeout=30)
        machine.succeed(f"grep -q copied-2 {d}/10")
        machine.fail(f"test -e {d}/11")
        as_me("golem-clip forget")
        machine.fail(f"test -e {d}/1")

    with subtest("Echo: Echos are made and listed; without a brain it says so; ECHO opens it OFFLINE; STOP works"):
        as_me("golem-echo new Mitra a calm friend")
        assert "Mitra: a calm friend" in as_me("golem-echo list")
        machine.succeed("test -s /home/lilgolemwitch/zones/golem-echo/echo/echos/mitra/profile.json")
        out = machine.execute("su - lilgolemwitch -c 'golem-echo say Mitra hello' 2>&1")[1]
        assert "no brain yet" in out, out
        machine.succeed("grep -q zone=offline /var/lib/golem/apps/golem-echo.conf")
        f = "/home/lilgolemwitch/zones/golem-echo/feed/chat.txt"
        machine.succeed(f"mkdir -p $(dirname {f}) && printf '%s\\n' "
                        "'12/11/26, 9:41 pm - Riya: kal aa rahi hai na?' '12/11/26, 9:42 pm - Aaru: haan yaar pakka' "
                        "'bas thoda late' '12/11/26, 9:43 pm - Riya: <Media omitted>' > " + f +
                        " && chown -R lilgolemwitch /home/lilgolemwitch/zones/golem-echo")
        assert "Riya" in as_me("golem-echo people " + f)
        assert "1 new messages learned" in as_me(f"golem-echo feed Mitra {f} Aaru")
        machine.succeed("grep -q 'bas thoda late' /home/lilgolemwitch/zones/golem-echo/echo/echos/mitra/samples.jsonl")
        machine.wait_until_succeeds("golem-truth --text | grep -q 'Mitra was fed 1 messages of Aaru'", timeout=30)
        machine.send_key("meta_l-esc")
        machine.wait_until_succeeds(realm_seen, timeout=30)
        machine.sleep(3)
        for k in ["down", "down", "ret"]:
            machine.send_key(k)
            machine.sleep(1)
        machine.wait_until_succeeds("golem-truth --text | grep -q 'Opened golem-echo in OFFLINE'", timeout=60)
        machine.wait_until_succeeds("su - lilgolemwitch -c 'DISPLAY=:0 xdotool search --onlyvisible --name \"OFFLINE . golem-echo\"'", timeout=60)   # in its own room
        machine.screenshot("echo")
        machine.wait_until_succeeds("pgrep -u lilgolemwitch -f echo/hands.py", timeout=30)
        out = as_me("bash /etc/golem-test-echo.sh")
        print(out)
        assert "hi from Mitra, got: abc" in out and "no extension called nothing-here" in out, out
        assert "the trainer isn't set up yet" in out, out
        # Training: no NVIDIA card in this virtual laptop, so it says so plainly; too few messages, so it says so
        machine.succeed("grep -q nvidia=allowed /var/lib/golem/apps/golem-echo-train.conf")
        out = machine.execute("su - lilgolemwitch -c 'golem-echo-trainer' 2>&1")
        assert out[0] == 1 and "no NVIDIA card" in out[1], out
        machine.fail("su - lilgolemwitch -c 'golem-echo-train mitra'")
        machine.succeed("grep -q 'only 1 messages fed' /home/lilgolemwitch/zones/golem-echo/echo/echos/mitra/train.json")
        machine.succeed("grep -q say-hi /home/lilgolemwitch/zones/golem-echo/echo/actions.jsonl")
        machine.wait_until_succeeds("golem-truth --text | grep -q 'Mitra used say-hi'", timeout=30)
        machine.send_key("meta_l-shift-e")
        machine.wait_until_succeeds("golem-truth --text | grep -q 'STOP pressed'", timeout=30)
        machine.execute("pkill -f echo/echo.py")
        machine.sleep(2)

    with subtest("The NVIDIA card is only for apps I mark (this virtual laptop has none: nothing breaks)"):
        assert "nvidia=never" in machine.succeed("zone defaults offline")
        machine.succeed("printf '%s\\n' zone=offline nvidia=allowed > /var/lib/golem/apps/true.conf")
        assert "nvidia:allowed" in as_me("zone show true")
        as_me("zone true")
        machine.succeed("journalctl -t zone | grep 'START OFFLINE true' | grep -q nvidia:allowed")
        machine.succeed("rm /var/lib/golem/apps/true.conf")
        machine.fail("lsmod | grep -q '^nvidia '")

    with subtest("golem-keylight: says plainly there is no keyboard light here; keeps the pattern; makes Echo's extension"):
        assert "No keyboard light found" in as_me("golem-keylight what")
        out = machine.execute("su - lilgolemwitch -c 'golem-keylight key W red' 2>&1")
        assert out[0] == 1 and "no keyboard light" in out[1], out
        machine.succeed("grep -q 'W red' /home/lilgolemwitch/.config/golem-keylight/now.lights")
        as_me("golem-keylight extension")
        machine.succeed("test -x /home/lilgolemwitch/.local/share/golem-echo/extensions/keylight/keylight")

    with subtest("Wires: the code goes after my own function, uses it, and runs"):
        out = as_me("bash /etc/golem-test-wires.sh")
        assert '"ok": true' in out and out.strip().endswith("42"), out
        machine.succeed("grep -q 'def double' /home/lilgolemwitch/wired.py && test -s /home/lilgolemwitch/wired.py.wires.json")

    with subtest("The program map reads a project (never runs it) and knows where I am"):
        as_me("mkdir -p proj && cp wired.py proj/ && echo def broken  > proj/bad.py")
        m = json.loads(as_me("golem-map proj --json --here /home/lilgolemwitch/proj/wired.py:2"))
        names = [t["name"] for t in m["towers"]]
        assert "double" in names and m["here"] == names.index("double"), m
        assert any(d["mistake"] for d in m["districts"]), m

    with subtest("Step E: GADA in the Start panel opens the editor"):
        machine.send_key("meta_l-esc")
        machine.wait_until_succeeds(realm_seen, timeout=30)
        machine.sleep(3)
        machine.send_key("down")
        machine.sleep(1)
        machine.send_key("ret")
        machine.wait_until_succeeds("journalctl -b -t golem -o cat | grep -q 'Start panel: GADA'", timeout=30)
        machine.wait_until_fails(realm_seen, timeout=30)
        machine.wait_until_succeeds("golem-truth --text | grep -q 'Opened golem-edit in GREEN'", timeout=60)

    with subtest("golem-selftest runs and its machine checks pass (the laptop parts can't, here)"):
        out = machine.execute("su - lilgolemwitch -c 'export DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000; golem-selftest' 2>&1")[1]
        print(out)
        assert "command not found" not in out, "a command inside golem-selftest is missing"
        for line in ["✓ Wi-Fi was switched off at start", "✓ no clock over the internet", "✓ the firewall is on",
                     "✓ RED sees none of my files", "✓ RED has no network at all", "✓ OFFLINE has no network at all",
                     "✓ the truth log writes and reads", "✓ the internet watcher is running", "✓ the settings guard is listening",
                     "✓ system settings were applied at start", "✓ the window manager is running", "✓ my key list is valid"]:
            assert line in out, "missing: " + line
        machine.succeed("test -s /home/lilgolemwitch/golem-selftest.txt")

    with subtest("golem-sand draws the sand and writes down how smooth it was"):
        machine.succeed("su - lilgolemwitch -c 'DISPLAY=:0 timeout 120 golem-sand --windowed --seconds 6' >&2")
        machine.succeed("grep -q 'Sand test:' /home/lilgolemwitch/golem-sand.txt")
        machine.wait_until_succeeds("golem-truth --text | grep -q 'Sand test'", timeout=30)
  '';
}
