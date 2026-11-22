# golem-selftest: checks everything a machine can check by itself on the real laptop.
# Prints ✓ (works), ✗ (broken) or – (just so you know). Saved to ~/golem-selftest.txt.
# What needs eyes and hands (the lid, how it feels) stays in TESTS.md.
pass=0; fail=0; report=""
say() { report+="$1"$'\n'; echo "$1"; }
ok()   { pass=$((pass + 1)); say "  ✓ $1"; }
bad()  { fail=$((fail + 1)); say "  ✗ $1"; }
info() { say "  – $1"; }
check() {   # check "what it means" command...
  local what=$1; shift
  if "$@" >/dev/null 2>&1; then ok "$what"; else bad "$what"; fi
}
is() { local want=$1; shift; [ "$("$@" 2>/dev/null)" = "$want" ]; }   # is "answer" command...
has() { compgen -G "$1" >/dev/null; }
ran() { [ "$(systemctl show -p ExecMainExitTimestampMonotonic --value "$1")" != 0 ] && [ "$(systemctl show -p Result --value "$1")" = success ] && [ "$(systemctl show -p ExecMainStatus --value "$1")" = 0 ]; }   # a one-time start job finished well

say "GOLEM SELF-TEST  $(date '+%d %b %Y %H:%M')  version $(cat /etc/golem/version 2>/dev/null || echo unknown)"

say ""; say "TRUTHFUL BASE"
check "Wi-Fi was switched off at start" ran golem-wifi-off
check "no clock over the internet" bash -c '! systemctl is-active systemd-timesyncd'
check "the firewall is on" systemctl is-active firewall
info "Wi-Fi right now: $(nmcli radio wifi 2>/dev/null || echo unknown)"

say ""; say "ZONES"
check "RED sees none of my files" is 0 zone red bash -c 'ls ~ | wc -l'
check "RED has no network at all" is 1 zone red bash -c 'ip -o link | wc -l'
check "OFFLINE has no network at all" is 1 zone offline bash -c 'ip -o link | wc -l'
if [ "$(golem-net-test)" = ONLINE ]; then
  check "YELLOW can reach the internet" is ONLINE zone yellow golem-net-test
  check "RED can't reach the internet" is OFFLINE zone red golem-net-test
else
  info "internet checks skipped: turn Wi-Fi on (Super+N), join a network, and run this again"
fi

say ""; say "TRUTH LOG AND GUARD"
logger -t golem "Self-test ran"
check "the truth log writes and reads" bash -c 'sleep 1; golem-truth --text | grep -q "Self-test ran"'
check "the internet watcher is running" systemctl is-active golem-netwatch
check "the settings guard is listening" systemctl is-active golem-helper.socket
check "system settings were applied at start" ran golem-settings

say ""; say "THIS LAPTOP"
check "Wi-Fi card found" has '/sys/class/net/wl*'
check "graphics driver (Intel) loaded" test -d /sys/module/i915
check "sound card found" bash -c 'aplay -l | grep -q card'
check "battery found" has '/sys/class/power_supply/BAT*'
check "lid switch found" has '/proc/acpi/button/lid/*/state'
check "sleep is possible" grep -qw mem /sys/power/state
if has '/dev/video*'; then info "camera: on"; else info "camera: off or not found (DRIVERS page)"; fi
if arecord -l 2>/dev/null | grep -q card; then info "microphone: found"; else info "microphone: off or not found"; fi
if has '/sys/class/bluetooth/hci*'; then info "Bluetooth: found"; else info "Bluetooth: off or not found"; fi
used=$(df --output=pcent / | tail -1 | tr -dc 0-9)
if [ "$used" -lt 90 ]; then ok "drive has room (${used}% used)"; else bad "drive almost full (${used}% used)"; fi

if [ -n "${DISPLAY:-}" ]; then
  say ""; say "DESKTOP"
  check "the window manager is running" pgrep -x i3
  check "idle lock is watching" pgrep -x xss-lock
  check "the red alert watcher is running" pgrep -f 'alert.py --watch'
  check "my key list is valid" i3 -C -c /etc/i3/config
else
  say ""; info "desktop checks skipped: run this from the desktop's terminal (Alt+Enter)"
fi

say ""; say "RESULT: $pass working, $fail broken"
printf '%s' "$report" > "$HOME/golem-selftest.txt"
logger -t golem "Self-test: $pass working, $fail broken"
echo "(saved to ~/golem-selftest.txt)"
[ "$fail" -eq 0 ]
