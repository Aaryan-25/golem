# My settings. Change these, and the next build uses them.
{
  user = "lilgolemwitch";       # account name (first password: golem, change it with `passwd`)
  timeZone = "Asia/Kolkata";
  keyboardLayout = "us";
  # Hard limits per zone (RAM, CPU). 100% CPU = one full core; the Dell has 2.
  limits = {
    red     = { memory = "1G";    cpu = "50%";  };
    offline = { memory = "1500M"; cpu = "100%"; };
    yellow  = { memory = "2G";    cpu = "150%"; };
    green   = { memory = "2500M"; cpu = "180%"; };
  };
  # The look: a dark void with pale, cold light.
  theme = {
    void  = "#050506";   # background everywhere
    shade = "#14161c";   # selected item, quiet surfaces
    mist  = "#6f7484";   # dim text, inactive things
    text  = "#c8ccd8";   # normal text
    pale  = "#e6e9f2";   # bright text, focus line
  };
  # Negative: ink on pale paper (Super+I, or Control Panel > LOOK > FACE).
  themeNegative = {
    void  = "#eceae4";
    shade = "#d6d3ca";
    mist  = "#7a776f";
    text  = "#26252a";
    pale  = "#0b0b0d";
  };
  githubRepo = "Aaryan-25/golem";   # where golem-update gets new versions
}
