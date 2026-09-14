#!/usr/bin/env bash
#
# doctor.sh — say what is installed and what is missing. Changes nothing.
#
# Safe to run at any time, including on a machine where nothing has been set up
# yet. Every line is a question with a yes or a no, and a no says what to do.
#
# Exit 0 when the stack is usable, 1 when something needed is missing.
set -uo pipefail

if [ -t 1 ]; then
  B=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; R=$'\033[0m'
else
  B=''; DIM=''; GREEN=''; YELLOW=''; RED=''; R=''
fi

MISSING=0
row() {  # row <status> <label> <detail>
  case "$1" in
    ok)   printf '  %s✓%s  %-26s %s\n' "$GREEN" "$R" "$2" "$3" ;;
    no)   printf '  %s✗%s  %-26s %s\n' "$RED" "$R" "$2" "$3"; MISSING=1 ;;
    warn) printf '  %s!%s  %-26s %s\n' "$YELLOW" "$R" "$2" "$3" ;;
  esac
}
hint() { printf '     %s%s%s\n' "$DIM" "$1" "$R"; }
have() { command -v "$1" >/dev/null 2>&1; }
is_our_gum() { have gum && gum --help 2>&1 | grep -qiE 'google|gum mcp'; }

printf '\n%sCamouflage%s\n\n' "$B" "$R"

# ------------------------------------------------------------------ machine --
printf '%sMachine%s\n' "$B" "$R"
if [ "$(uname -s)" = "Darwin" ]; then
  row ok "macOS" "$(sw_vers -productVersion 2>/dev/null || echo '?') on $(uname -m)"
else
  row warn "operating system" "$(uname -s) — this stack is set up for macOS"
fi
have brew && row ok "Homebrew" "$(brew --version 2>/dev/null | head -1 | awk '{print $2}')" \
           || { row no "Homebrew" "not installed"; hint "install.sh --yes installs it (official installer, asks for your password)"; }
have go   && row ok "Go" "$(go version 2>/dev/null | awk '{print $3}')" \
           || { row no "Go" "not installed"; hint "install.sh --yes installs it; it is the fallback when a tap fails"; }

# ----------------------------------------------------------------- gomoufox --
printf '\n%sBrowser automation%s\n' "$B" "$R"
if have gomoufox; then
  row ok "gomoufox" "$(gomoufox --version 2>/dev/null | head -1 || echo 'installed')"
  if gomoufox doctor >/dev/null 2>&1; then
    row ok "Camoufox browser" "gomoufox doctor passes"
  else
    row no "Camoufox browser" "gomoufox doctor fails"
    hint "run: gomoufox install"
  fi
else
  row no "gomoufox" "not on PATH"
  hint "run install.sh --yes, or: brew tap ehmo/gomoufox https://github.com/ehmo/gomoufox && brew install gomoufox"
  row no "Camoufox browser" "cannot check without gomoufox"
fi

# ---------------------------------------------------------------------- gum --
printf '\n%sGoogle APIs%s\n' "$B" "$R"
if is_our_gum; then
  row ok "gum (ehmo/gum)" "$(gum --version 2>/dev/null | head -1 || echo 'installed')"
  # Whether a Google account is actually connected is a separate question from
  # whether the binary is there, and only the owner of the account can answer it.
  if gum doctor >/dev/null 2>&1; then
    row ok "gum doctor" "passes"
  else
    row warn "gum doctor" "reports something — run: gum doctor"
    hint "usually means no Google account is connected yet: gum login --service <name>"
  fi
elif have gum; then
  row no "gum (ehmo/gum)" "a different 'gum' is on PATH: $(command -v gum)"
  hint "that is Charmbracelet's gum, a shell-prompt toolkit, not this one"
  hint "install ours: brew tap ehmo/tap https://github.com/ehmo/homebrew-tap && brew install ehmo/tap/gum"
else
  row no "gum (ehmo/gum)" "not on PATH"
  hint "run install.sh --yes"
fi

# --------------------------------------------------------------- the agents --
# Both tools write a stdio MCP entry into the agent's own config. Which file
# that is depends on the agent, so each is checked where it actually lives.
printf '\n%sWired into agents%s\n' "$B" "$R"
check_cfg() {  # check_cfg <label> <file> <needle>
  if [ -f "$2" ] && grep -q "$3" "$2" 2>/dev/null; then
    row ok "$1" "${2/#$HOME/\~}"
  elif [ -f "$2" ]; then
    row no "$1" "config exists but no $3 entry"
    hint "run install.sh --yes, or: $3 setup --target all --features skills,mcp --yes"
  else
    row no "$1" "no config at ${2/#$HOME/\~}"
  fi
}
check_cfg "Claude Code · gomoufox" "$HOME/.claude.json" "gomoufox"
check_cfg "Claude Code · gum"      "$HOME/.claude.json" "gum"
check_cfg "Codex · gomoufox"       "$HOME/.codex/config.toml" "gomoufox"
check_cfg "Codex · gum"            "$HOME/.codex/config.toml" "gum"

for d in "$HOME/.claude/skills" "$HOME/.codex/skills"; do
  for s in gomoufox gum; do
    [ -d "$d/$s" ] && row ok "skill $s" "${d/#$HOME/\~}/$s"
  done
done

# ------------------------------------------------------------------- result --
printf '\n'
if [ "$MISSING" -eq 0 ]; then
  printf '%sEverything needed is in place.%s\n' "$GREEN$B" "$R"
  printf 'A live check, if you want one: %sgomoufox get https://example.com --text%s\n\n' "$B" "$R"
  exit 0
fi
printf '%sSomething is missing.%s The lines marked ✗ say what; %sinstall.sh --yes%s fixes most of them.\n\n' "$YELLOW$B" "$R" "$B" "$R"
exit 1
