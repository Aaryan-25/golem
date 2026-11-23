# My settings. Change these, and the next build uses them.
{
  user = "lilgolemwitch";       # account name (first password: arise, change it with `passwd`)
  timeZone = "Asia/Kolkata";
  keyboardLayout = "us";
  # Hard limits per zone (RAM, CPU). 100% CPU = one full core; the Dell has 2.
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
