# Automated tests: GitHub starts Golem in a virtual laptop and checks it, on every change.
# (The real laptop still has the last word: see TESTS.md.)
{ pkgs, modules, golemRev }:
pkgs.testers.runNixOSTest {
  name = "golem";
  node.specialArgs = { inherit golemRev; };
  nodes.machine = { lib, ... }: {
    imports = modules;
    virtualisation.memorySize = 2048;
    boot.loader.grub.enable = lib.mkForce false;     # the test machine starts the kernel directly
    boot.growPartition = lib.mkForce false;
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    with subtest("Step 3: Wi-Fi off at start, no internet clock, nothing comes in"):
        machine.succeed("grep -q WirelessEnabled=false /var/lib/NetworkManager/NetworkManager.state")
        machine.fail("systemctl is-active systemd-timesyncd")
        machine.succeed("nft list ruleset | grep -q drop || iptables -S | grep -q DROP")

    with subtest("Step 5: the key and window settings are valid"):
        machine.succeed("i3 -C -c /etc/i3/config")

    with subtest("Login on the text screen starts the windows"):
        machine.wait_until_tty_matches("1", "login: ")
        machine.send_chars("lilgolemwitch\n")
        machine.wait_until_tty_matches("1", "Password: ")
        machine.send_chars("golem\n")
        machine.wait_for_x()
        machine.wait_until_succeeds("pgrep -x i3")

    def as_me(cmd):
        return machine.succeed(
            "su - lilgolemwitch -c 'export XDG_RUNTIME_DIR=/run/user/1000 "
            "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; " + cmd + "'"
        ).strip()

    with subtest("Step 5: Alt+Enter opens a terminal"):
        machine.send_key("alt-ret")
        machine.wait_until_succeeds("pgrep -u lilgolemwitch -x xterm")

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
        as_me("zone set bash yellow")
        assert "YELLOW" in as_me("zone show bash")
        assert as_me("zone bash -c \"ls ~ | grep -c documents || true\"") == "0"
  '';
}
