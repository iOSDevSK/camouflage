# Camouflage

**macOS only.** An agent skill that installs the Camoufox browser stack and wires
it into Claude Code and Codex. It installs everything underneath as well, down
to Homebrew itself, so one command leaves you with a working machine.

It sets things up and checks them. It does not collect data, schedule anything,
or hold credentials.

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
| Homebrew, if missing | `/opt/homebrew` on Apple Silicon, `/usr/local` on Intel — needs your password |
| Go, if missing | via Homebrew |
| `gomoufox` binary | Homebrew prefix, or `$(go env GOPATH)/bin` on the fallback path |
| `gum` binary | Homebrew prefix, or `~/.local/bin` on the fallback path |
| Camoufox browser | managed by gomoufox in its own directory |
| MCP entry + skills, Claude Code | `~/.claude.json`, `~/.claude/skills/` |
| MCP entry + skills, Codex | `~/.codex/config.toml`, `~/.codex/skills/`, `~/.agents/skills/` |

`~/.claude.json` is the file Claude Code reads for user-wide MCP servers.
Some setup tools also write `~/.claude/mcp.json`, which nothing reads; the
installer says which of the two got the entries and the doctor flags the
other.

Both MCP configs are **merged**, not replaced, and existing skill files are
left alone. Nothing outside these paths is touched.

## Requirements

- macOS, Apple Silicon or Intel
- An administrator password, once, if Homebrew is not installed yet
- A Google account, if you want the `gum` half. You connect it yourself; see below.

Homebrew and Go are installed for you when they are missing. Nothing else is
assumed.

## Install the skill

**Clone it. Do not copy `SKILL.md` on its own** — the two scripts are the
working parts, and a skill directory holding only the markdown sends your
agent looking for a `scripts/install.sh` that is not there. Skill catalogues
generally carry the markdown alone, so an install from one needs the clone
below over the top of it.

```bash
# Claude Code, available in every project
git clone https://github.com/iOSDevSK/camouflage.git ~/.claude/skills/camouflage

# Codex
git clone https://github.com/iOSDevSK/camouflage.git ~/.codex/skills/camouflage

# or just this one project
git clone https://github.com/iOSDevSK/camouflage.git .claude/skills/camouflage
```

Start a new session afterwards so the agent picks the skill up.

If you already have an incomplete copy, running the installer from a complete
one repairs it: it checks `~/.claude/skills`, `~/.codex/skills` and
`~/.agents/skills`, and puts the scripts back beside any `SKILL.md` missing
them. `doctor.sh` reports the same thing without changing anything.

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

**Homebrew is missing.** The script installs it with the official installer
from [brew.sh](https://brew.sh), unchanged. It is the largest change the script
makes and it asks for your password, because `/opt/homebrew` and `/usr/local`
belong to root. The dry run shows the command before anything happens.

Afterwards, add the printed `shellenv` line to your shell profile, or a new
terminal will not find `brew`.

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

It writes no credentials, does not run `gum login`, and does not fetch a single
page of anyone's data. Nothing happens at all without `--yes`.

What you do with the browser afterwards is a separate decision. The usual rules
apply: read `robots.txt`, keep a civil rate, and do not use an anti-fingerprint
browser to get around a site that has already told you no.

## Licence

MIT.
