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
# Anything missing underneath gets installed too: Homebrew if it is not there,
# and Go for the fallback path. The goal is a machine that works afterwards,
# not a list of homework.
#
# Every step checks whether the work is already done, so running this twice is
# harmless, and nothing happens at all without --yes. The one thing left to you
# is `gum login`: it opens a browser against your own Google account and writes
# a token to your keychain, and that is yours to run.
set -uo pipefail

APPLY=0
for arg in "$@"; do
  case "$arg" in
    --yes|-y) APPLY=1 ;;
    --help|-h)
      sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'
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

# Where this script lives, and therefore where the rest of the skill lives.
# Resolved once, from the script itself, so it holds no matter which directory
# it was called from.
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SELF_DIR/.." && pwd)"

# Every place either agent looks for user-wide skills. ~/.agents/skills is
# real and shared: gomoufox and gum install there, and Codex reads it. It is
# not a synonym for ~/.codex/skills — both exist and both are used.
SKILL_ROOTS=("$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.agents/skills")

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

# Homebrew installs into /opt/homebrew on Apple Silicon and /usr/local on
# Intel, and neither is on PATH until its shellenv runs. A fresh install in one
# shell is therefore invisible to the next command unless we load it here.
brew_shellenv() {
  for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$p" ] && { eval "$("$p" shellenv)"; return 0; }
  done
  return 1
}

if have brew || brew_shellenv; then
  ok "Homebrew $(brew --version 2>/dev/null | head -1 | awk '{print $2}')"
else
  warn "Homebrew is not installed — it is needed for everything below"
  note "This is the biggest change this script makes. Homebrew writes to"
  note "/opt/homebrew (Apple Silicon) or /usr/local (Intel) and asks for your"
  note "password, because those directories belong to root. The command is the"
  note "official one from https://brew.sh, unchanged."
  if [ "$APPLY" -eq 1 ]; then
    # NONINTERACTIVE skips the "press RETURN to continue" prompt; the sudo
    # password prompt stays, and should — nobody should be handing out root
    # quietly.
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || true
    if brew_shellenv || have brew; then
      ok "Homebrew installed: $(brew --version 2>/dev/null | head -1 | awk '{print $2}')"
      note "add this to your shell profile so future sessions find it:"
      note "  eval \"\$($(command -v brew) shellenv)\""
    else
      die "Homebrew install did not finish" \
          "Install it by hand from https://brew.sh and run this again."
    fi
  else
    would 'NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  fi
fi

if have go; then
  ok "Go $(go version 2>/dev/null | awk '{print $3}')"
else
  warn "Go is not installed — it is the fallback when a Homebrew tap fails"
  if [ "$APPLY" -eq 1 ] && have brew; then
    brew install go 2>&1 | tail -2
    have go && ok "Go installed: $(go version 2>/dev/null | awk '{print $3}')" || warn "Go install did not finish; continuing without the fallback path"
  else
    would "brew install go"
  fi
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

# Claude Code reads user-wide MCP servers from ~/.claude.json. It does not
# read ~/.claude/mcp.json, and a setup that writes only there leaves you with
# a config file that looks right and does nothing. Say which one actually has
# the entry, rather than trusting that "setup finished" meant it landed.
if [ "$APPLY" -eq 1 ]; then
  if [ -f "$HOME/.claude.json" ] && grep -q '"gomoufox"' "$HOME/.claude.json" 2>/dev/null; then
    ok "Claude Code reads it: ~/.claude.json has the entries"
  else
    warn "~/.claude.json has no gomoufox entry — Claude Code will not see the server"
    note "that file, not ~/.claude/mcp.json, is the one Claude Code reads for user-wide servers"
    FAILED=1
  fi
  if [ -f "$HOME/.claude/mcp.json" ]; then
    note "~/.claude/mcp.json also exists; Claude Code ignores it, and it is harmless"
  fi
fi

# ------------------------------------------------- 6. repair our own install --
# A skill installed from a catalogue arrives as SKILL.md and nothing else:
# the directory listing, the search index and the install command all deal in
# the markdown file. Ours needs the two scripts beside it, and without them
# the agent reads "run scripts/install.sh", finds no such file, and goes
# hunting through the filesystem. So wherever a camouflage SKILL.md is
# installed, the scripts are put back next to it.
step "Completing installed copies of this skill"

copies=0
for root in "${SKILL_ROOTS[@]}"; do
  dir="$root/camouflage"
  [ -f "$dir/SKILL.md" ] || continue
  copies=$((copies + 1))
  if [ -x "$dir/scripts/install.sh" ] && [ -x "$dir/scripts/doctor.sh" ]; then
    ok "${dir/#$HOME/\~} already complete"
    continue
  fi
  if [ "$dir" = "$SKILL_DIR" ]; then continue; fi
  if [ "$APPLY" -eq 1 ]; then
    mkdir -p "$dir/scripts"
    cp "$SELF_DIR/install.sh" "$SELF_DIR/doctor.sh" "$dir/scripts/" && chmod +x "$dir/scripts/"*.sh
    ok "scripts copied to ${dir/#$HOME/\~}/scripts/"
  else
    would "cp $SELF_DIR/{install,doctor}.sh ${dir/#$HOME/\~}/scripts/"
    note "that copy has SKILL.md but no scripts — the agent would not find them"
  fi
done
[ "$copies" -eq 0 ] && note "no installed copy found; running from ${SKILL_DIR/#$HOME/\~}"

# ------------------------------------------------------------- 7. the check --
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
