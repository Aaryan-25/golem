# Languages the editor can run (F5), from nixpkgs. One name per line, in quotes.
# Add or remove as you go, then run golem-update. Each also brings its tidier (Ctrl+S).
# Part of Golem: GADA, the editor; MAP.md section 5.7.
[
  "python3"   # Python          (tidied by ruff)
  "bash"      # Bash scripts    (tidied by shfmt)
  "lua"       # Lua             (tidied by stylua)
  "nodejs"    # JavaScript      (tidied by prettier, which also tidies HTML, CSS, Markdown, JSON)

  # More you can add (pendrive space in brackets):
  # "gcc"     # C and C++       (~250 MB, tidied by clang-format)
  # "jdk"     # Java            (~200 MB)
  # "go"      # Go              (~250 MB)
  # "rustc"   # Rust            (~600 MB)
  # "ruby"  "php"  "perl"  "R"  "ghc"   # Ruby, PHP, Perl, R, Haskell
]
