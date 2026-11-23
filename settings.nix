# My settings. Change these, and the next build uses them.
{
  user = "lilgolemwitch";       # account name (first password: arise, change it with `passwd`)
  timeZone = "Asia/Kolkata";
  keyboardLayout = "us";
  # Hard limits per zone (RAM, CPU). 100% CPU = one full core; the Dell has 2.
  # On a computer with 6 GB of memory or more (the Asus), every limit is doubled: see `bigger` below.
  # bigger 1500M -> 3000M on a big computer (6 GB or more), unchanged on the Dell. Also works on 50%.
  bigger = ''
    bigger() {
      local k v _ gb=0
      while read -r k v _; do [ "$k" = MemTotal: ] && gb=$(( (v + 524288) / 1048576 )); done < /proc/meminfo
      if [ "$gb" -lt 6 ]; then echo "$1"; return; fi
      case "$1" in *M) echo "$(( ''${1%M} * 2 ))M" ;; *G) echo "$(( ''${1%G} * 2 ))G" ;; *%) echo "$(( ''${1%\%} * 2 ))%" ;; *) echo "$1" ;; esac
    }
  '';
  limits = {
    red     = { memory = "1G";    cpu = "50%";  };
    offline = { memory = "1500M"; cpu = "100%"; };
    yellow  = { memory = "2G";    cpu = "150%"; };
    green   = { memory = "2500M"; cpu = "180%"; };
  };
  # The look: the shadow realm. Black ground, everything else white (22 Nov 2026).
  theme = {
    void  = "#000000";   # background everywhere
    shade = "#1c1c1c";   # selected item, quiet surfaces
    mist  = "#8c8c8c";   # dim text, inactive things
    text  = "#dcdcdc";   # normal text
    pale  = "#ffffff";   # bright text, focus line
  };
  # Negative, the yin-yang turned over: ink on white paper (Super+I, B in the Start panel, MIMIC > FACE).
  themeNegative = {
    void  = "#f4f4f1";
    shade = "#dadad6";
    mist  = "#707070";
    text  = "#202020";
    pale  = "#000000";
  };
  githubRepo = "Aaryan-25/golem";   # where golem-update gets new versions
}
