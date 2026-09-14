#!/usr/bin/env bash
#
# install.sh — put the Camoufox stack on this machine and wire it into agents.
#
#   install.sh            print what would happen, change nothing
#   install.sh --yes      do it
#   install.sh --help     usage
#
# Installs, in this order, because each step needs the one before it:
#
#   gomoufox   Go CLI and MCP server that drives a browser
#   Camoufox   the browser itself, downloaded by `gomoufox install`
#   gum        Go CLI and MCP server for Google APIs (ehmo/gum, NOT Charm's gum)
#
# then registers both MCP servers and their skills with Claude Code and Codex.
#
# Every step checks whether the work is already done, so running this twice is
# harmless. Nothing here installs Homebrew, writes a credential, or runs a
# login: `gum login` opens a browser against your own Google account and is
# yours to run.
set -uo pipefail

APPLY=0
for arg in "$@"; do
  case "$arg" in
    --yes|-y) APPLY=1 ;;
    --help|-h)
      sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "unknown argument: $arg (try --help)" >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------- output ----
# Colour only when a terminal is watching, so piping to a file stays readable.
if [ -t 1 ]; then
  B=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; R=$'\033[0m'
else
  B=''; DIM=''; GREEN=''; YELLOW=''; RED=''; R=''
fi
step()  { printf '\n%s==>%s %s%s%s\n' "$B" "$R" "$B" "$1" "$R"; }
ok()    { printf '    %s✓%s %s\n' "$GREEN" "$R" "$1"; }
warn()  { printf '    %s!%s %s\n' "$YELLOW" "$R" "$1"; }
fail()  { printf '    %s✗%s %s\n' "$RED" "$R" "$1"; }
note()  { printf '    %s%s%s\n' "$DIM" "$1" "$R"; }
would() { printf '    %swould run:%s %s\n' "$DIM" "$R" "$1"; }

# Run a command, or describe it, depending on the mode. Everything that
# changes the machine goes through here — that is what makes the dry run
# trustworthy rather than a promise.
run() {
  if [ "$APPLY" -eq 1 ]; then
    printf '    %s$ %s%s\n' "$DIM" "$*" "$R"
    "$@"
  else
    would "$*"
    return 0
  fi
}

die() { fail "$1"; printf '\n%sstopped.%s %s\n' "$RED" "$R" "${2:-}"; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# ehmo/gum and Charmbracelet's gum answer to the same name. Telling them apart
# matters: one talks to Google APIs, the other draws prompts in shell scripts,
# and `brew install gum` gives you the second one. The Google catalogue shows
# up in the help text of the one we want.
is_our_gum() {
  have gum || return 1
  gum --help 2>&1 | grep -qiE 'google|gum mcp' && return 0
  return 1
}

FAILED=0

# ---------------------------------------------------------- 1. the machine ---
step "Checking this machine"

[ "$(uname -s)" = "Darwin" ] || die "this installer is for macOS; found $(uname -s)"
ARCH="$(uname -m)"
ok "macOS $(sw_vers -productVersion 2>/dev/null || echo '?') on $ARCH"

if have brew; then
  ok "Homebrew $(brew --version 2>/dev/null | head -1 | awk '{print $2}')"
else
  die "Homebrew is not installed" \
      "Install it from https://brew.sh and run this again. This script will not install it for you."
fi

if have go; then
  ok "Go $(go version 2>/dev/null | awk '{print $3}') (fallback path available)"
else
  warn "Go is not installed — the Homebrew path will be used, with no fallback"
fi

# ~/.local/bin is where gum's own installer writes. If it is not on PATH the
# binary lands somewhere the shell will never look, which reads later as "gum
# is not installed" and wastes an afternoon.
case ":${PATH}:" in
  *":${HOME}/.local/bin:"*) ok "~/.local/bin is on PATH" ;;
  *) warn "~/.local/bin is not on PATH — add it to your shell profile if the fallback installer is used" ;;
esac

# -------------------------------------------------------------- 2. gomoufox --
step "gomoufox — browser automation CLI and MCP server"

if have gomoufox; then
  ok "already installed: $(gomoufox --version 2>/dev/null | head -1 || echo 'version unknown')"
else
  note "https://github.com/ehmo/gomoufox"
  if [ "$APPLY" -eq 1 ]; then
    brew tap ehmo/gomoufox https://github.com/ehmo/gomoufox 2>/dev/null || true
    # Some taps ship unsigned formulae; brew refuses those until trusted, and
    # only newer brews know the subcommand at all.
    if brew commands 2>/dev/null | grep -qx trust; then
      brew trust --formula ehmo/gomoufox/gomoufox 2>/dev/null || true
    fi
    if brew install gomoufox 2>&1 | tail -3; then :; fi
    if ! have gomoufox && have go; then
      warn "Homebrew did not produce a gomoufox binary, falling back to go install"
      go install github.com/ehmo/gomoufox/cmd/gomoufox@latest
      # go install writes to GOBIN or GOPATH/bin, which the current shell may
      # not have on PATH yet.
      GOBIN="$(go env GOBIN)"; [ -n "$GOBIN" ] || GOBIN="$(go env GOPATH)/bin"
      case ":${PATH}:" in *":${GOBIN}:"*) : ;; *) export PATH="$GOBIN:$PATH"; warn "added $GOBIN to PATH for this run; add it to your shell profile" ;; esac
    fi
    if have gomoufox; then ok "installed: $(gomoufox --version 2>/dev/null | head -1)"; else fail "gomoufox still not on PATH"; FAILED=1; fi
  else
    would "brew tap ehmo/gomoufox https://github.com/ehmo/gomoufox"
    would "brew install gomoufox"
    note "fallback if the tap fails: go install github.com/ehmo/gomoufox/cmd/gomoufox@latest"
  fi
fi

# -------------------------------------------------------------- 3. Camoufox --
step "Camoufox — the browser gomoufox drives"

if have gomoufox && gomoufox doctor >/dev/null 2>&1; then
  ok "already present (gomoufox doctor passes)"
else
  note "gomoufox downloads and pins its own Camoufox build; do not also pip install camoufox"
  if have gomoufox || [ "$APPLY" -eq 0 ]; then
    run gomoufox install
  else
    fail "skipped: gomoufox is not installed"
    FAILED=1
  fi
fi

# ------------------------------------------------------------------- 4. gum --
step "gum — Google APIs from the terminal and over MCP"

if is_our_gum; then
  ok "already installed: $(gum --version 2>/dev/null | head -1 || echo 'version unknown')"
elif have gum; then
  fail "a different tool named 'gum' is on PATH: $(command -v gum)"
  note "That is Charmbracelet's gum, a shell-prompt toolkit. It is not this one and is not a problem in itself."
  note "Install ours alongside it and call it by its full path, or remove theirs first:"
  note "  brew tap ehmo/tap https://github.com/ehmo/homebrew-tap && brew install ehmo/tap/gum"
  FAILED=1
else
  note "https://github.com/ehmo/gum — 228 operations across 33 Google services"
  if [ "$APPLY" -eq 1 ]; then
    brew tap ehmo/tap https://github.com/ehmo/homebrew-tap 2>/dev/null || true
    brew install ehmo/tap/gum 2>&1 | tail -3 || true
    if ! is_our_gum; then
      warn "Homebrew path did not work, falling back to the official installer"
      # Its installer verifies a SHA-256 checksum against the published
      # checksums.txt before it writes anything.
      curl -fsSL https://raw.githubusercontent.com/ehmo/gum/main/install.sh | bash
      export PATH="$HOME/.local/bin:$PATH"
    fi
    if is_our_gum; then ok "installed: $(gum --version 2>/dev/null | head -1)"; else fail "gum still not on PATH"; FAILED=1; fi
  else
    would "brew tap ehmo/tap https://github.com/ehmo/homebrew-tap"
    would "brew install ehmo/tap/gum"
    note "note: plain 'brew install gum' installs Charmbracelet's gum, a different tool"
    note "fallback: curl -fsSL https://raw.githubusercontent.com/ehmo/gum/main/install.sh | bash"
  fi
fi

# -------------------------------------------------------- 5. wire the agents --
step "Wiring Claude Code and Codex"

note "writes skill files and a stdio MCP entry for each tool; existing config is merged, not replaced"

if have gomoufox; then
  if [ "$APPLY" -eq 1 ]; then
    gomoufox setup --target all --features skills,mcp --dry-run 2>&1 | sed 's/^/      /' | tail -15
    run gomoufox setup --target all --features skills,mcp --yes
  else
    would "gomoufox setup --target all --features skills,mcp --yes"
    note "preview of what it would write:"
    gomoufox setup --target all --features skills,mcp --dry-run 2>&1 | sed 's/^/      /' | tail -15
  fi
else
  warn "gomoufox not available, skipping its setup"
fi

if is_our_gum; then
  if [ "$APPLY" -eq 1 ]; then
    gum setup --target all --features skills,mcp --dry-run 2>&1 | sed 's/^/      /' | tail -15
    run gum setup --target all --features skills,mcp --yes
  else
    would "gum setup --target all --features skills,mcp --yes"
    note "preview of what it would write:"
    gum setup --target all --features skills,mcp --dry-run 2>&1 | sed 's/^/      /' | tail -15
  fi
else
  warn "gum not available, skipping its setup"
fi

# ------------------------------------------------------------- 6. the check --
step "Verifying"

if [ "$APPLY" -eq 1 ]; then
  if have gomoufox; then
    if gomoufox doctor 2>&1 | sed 's/^/      /'; then ok "gomoufox doctor finished"; else fail "gomoufox doctor reported a problem"; FAILED=1; fi
  fi
  if is_our_gum; then
    if gum doctor 2>&1 | sed 's/^/      /'; then ok "gum doctor finished"; else fail "gum doctor reported a problem"; FAILED=1; fi
  fi
else
  would "gomoufox doctor"
  would "gum doctor"
fi

# ------------------------------------------------------------------ the end --
if [ "$APPLY" -eq 0 ]; then
  printf '\n%sThis was a dry run. Nothing changed.%s\n' "$B" "$R"
  printf 'Run it again with %s--yes%s to apply.\n' "$B" "$R"
  exit 0
fi

printf '\n'
if [ "$FAILED" -eq 0 ]; then
  printf '%sDone.%s Restart Claude Code and Codex so they pick up the new MCP servers.\n' "$GREEN$B" "$R"
  printf 'Google access needs one more step, and it is yours to take: %sgum login --service <name>%s\n' "$B" "$R"
  exit 0
fi
printf '%sFinished with problems.%s Read the lines marked ✗ above; %sdoctor.sh%s will re-check without changing anything.\n' "$YELLOW$B" "$R" "$B" "$R"
exit 1
