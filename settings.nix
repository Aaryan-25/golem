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
  githubRepo = "Aaryan-25/golem";   # where golem-update gets new versions
}
