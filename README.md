# Camouflage

**macOS only.** An agent skill that installs the Camoufox browser stack and wires
it into Claude Code and Codex. It sets things up and checks them. It does not
collect data, schedule anything, or hold credentials.

## What it installs

Three pieces that depend on each other, in the only order that works:

| | what it is |
|---|---|
| [**gomoufox**](https://github.com/ehmo/gomoufox) | Go CLI and MCP server that drives a browser |
| **Camoufox** | the browser itself, a Firefox build; `gomoufox install` downloads and pins a matching version |
| [**gum**](https://github.com/ehmo/gum) | Go CLI and MCP server for Google APIs — 228 operations across 33 services, including Search Console, Sheets, Drive and Gmail |

> **`gum` here means [ehmo/gum](https://github.com/ehmo/gum), not
> [Charmbracelet's gum](https://github.com/charmbracelet/gum).** Both answer to
> the same command name and `brew install gum` gives you the other one. This
> skill installs ours by its full name and refuses to overwrite theirs.

## What it changes on your machine

| | where |
|---|---|
| `gomoufox` binary | Homebrew prefix, or `$(go env GOPATH)/bin` on the fallback path |
| `gum` binary | Homebrew prefix, or `~/.local/bin` on the fallback path |
| Camoufox browser | managed by gomoufox in its own directory |
| MCP entry + skills, Claude Code | `~/.claude.json`, `~/.claude/skills/` |
| MCP entry + skills, Codex | `~/.codex/config.toml`, `~/.codex/skills/` |

Both MCP configs are **merged**, not replaced, and existing skill files are
left alone. Nothing outside these paths is touched.

## Requirements

- macOS, Apple Silicon or Intel
- [Homebrew](https://brew.sh) — this skill will not install it for you
- Go, optional, only for the fallback install path
- A Google account, if you want the `gum` half. You connect it yourself; see below.

## Install the skill

Clone it wherever your agent looks for skills:

```bash
# Claude Code, available in every project
git clone https://github.com/iOSDevSK/camouflage.git ~/.claude/skills/camouflage

# Codex
git clone https://github.com/iOSDevSK/camouflage.git ~/.codex/skills/camouflage

# or just this one project
git clone https://github.com/iOSDevSK/camouflage.git .claude/skills/camouflage
```

Start a new session afterwards so the agent picks the skill up.

## Use it

Look before you leap. Without `--yes` the script prints every command it would
run and exits without touching anything:

```bash
cd ~/.claude/skills/camouflage
bash scripts/install.sh          # shows the plan
bash scripts/install.sh --yes    # does it
```

Asking the agent works too, and it resolves the path itself: *"run the
camouflage installer as a dry run"*.

Restart Claude Code and Codex afterwards so they read the new MCP config.

Check the result at any time. This one is read-only and safe even on a machine
where nothing is set up:

```bash
bash scripts/doctor.sh
```

It reports every binary, whether the browser is downloaded, whether both MCP
servers are registered with both agents, and what to run for anything missing.
Exit code 0 means the stack is usable.

Running the installer twice is harmless. Each step checks whether its work is
already done and says so instead of repeating it.

### One step is yours

Google access needs a login, and that is not something a script should do on
your behalf:

```bash
gum login --service searchconsole
```

It opens a browser against your own Google account and stores a refresh token
in the OS keychain. Nothing here runs it, reads it, or copies it anywhere.

## When it fails

**"Homebrew is not installed."** The script stops rather than installing a
package manager behind your back. Get it from [brew.sh](https://brew.sh) and
run again.

**The tap will not install.** Some taps ship unsigned formulae and newer
Homebrew refuses them until trusted; the script tries `brew trust` where that
subcommand exists. If it still fails, gomoufox has a Go fallback and gum has an
official installer that verifies a SHA-256 checksum before it writes anything.
The script takes those routes on its own.

**"a different tool named gum is on PATH."** Charmbracelet's gum got there
first. That is not a fault and the script will not remove it. Either uninstall
theirs, or install ours alongside and call it by its full path:

```bash
brew tap ehmo/tap https://github.com/ehmo/homebrew-tap
brew install ehmo/tap/gum
```

**It installed, but the command is not found.** The fallback paths write to
`~/.local/bin` and `$(go env GOPATH)/bin`. If either is missing from your
`PATH`, add it to your shell profile. `doctor.sh` warns about this before it
bites.

**`gum doctor` complains right after a clean install.** Usually it only means
no Google account is connected yet. See *One step is yours* above.

## What it will not do

It does not install Homebrew or Go, write credentials, run `gum login`, or
fetch a single page of anyone's data.

What you do with the browser afterwards is a separate decision. The usual rules
apply: read `robots.txt`, keep a civil rate, and do not use an anti-fingerprint
browser to get around a site that has already told you no.

## Licence

MIT.
