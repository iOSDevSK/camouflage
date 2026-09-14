---
name: camouflage
description: Use when setting up, checking or repairing the Camoufox browser stack on macOS — installing gomoufox, the Camoufox browser and ehmo/gum, and wiring their MCP servers into Claude Code and Codex.
---

# Camouflage

Installs three things that depend on each other, in the only order that works,
and tells you plainly when one of them is missing.

| | what it is |
|---|---|
| **gomoufox** | Go CLI and MCP server that drives a browser ([repo](https://github.com/ehmo/gomoufox)) |
| **Camoufox** | the browser itself, a Firefox build; `gomoufox install` downloads and pins it |
| **gum** | Go CLI and MCP server for Google APIs ([repo](https://github.com/ehmo/gum)) |

macOS only. This skill installs and verifies: it collects nothing, schedules
nothing, and holds no credentials.

## Finding the scripts

**`scripts/` is next to THIS FILE, never in the workspace.** Resolve it once,
from the path of this SKILL.md, and use the absolute path from then on. A bare
`scripts/install.sh` run from a project directory fails with a confusing "no
such file", because the skill lives wherever the host installed it:

```
~/.claude/skills/camouflage/       Claude Code, user-wide
~/.codex/skills/camouflage/        Codex
.claude/skills/camouflage/         inside one project
```

Every one of them has `SKILL.md` with `scripts/` beside it. Resolve from this
file; never guess which host installed it.

## Install

Always look before you leap. Without `--yes` the script prints every command it
would run and exits without touching the machine.

```bash
bash <skill-dir>/scripts/install.sh          # shows the plan
bash <skill-dir>/scripts/install.sh --yes    # does it
```

Running it a second time is safe. Each step checks whether its work is already
done and says so instead of redoing it.

Afterwards, restart Claude Code and Codex so they read the new MCP config.

## Check

Read-only, safe on any machine, including one where nothing is set up:

```bash
bash <skill-dir>/scripts/doctor.sh
```

It reports each binary, whether the browser is downloaded, whether both MCP
servers are registered with both agents, and what to run for anything missing.
Exit code 0 means the stack is usable.

## The one trap: two tools called gum

`brew install gum` installs **Charmbracelet's gum**, a toolkit for drawing
prompts in shell scripts. It is a fine tool and it is not this one. The Google
API gum must be installed by its full name:

```bash
brew tap ehmo/tap https://github.com/ehmo/homebrew-tap
brew install ehmo/tap/gum
```

Both scripts here tell the two apart by looking for the Google catalogue in the
help output, so they will never mistake one for the other, and `install.sh`
refuses to overwrite a gum it did not install.

## When something fails

**Homebrew is missing.** The script stops and points at brew.sh rather than
installing a package manager behind your back. Install it and run again.

**The tap will not install.** Some taps ship unsigned formulae and newer
Homebrew refuses them until trusted; the script tries `brew trust` when that
subcommand exists. If it still fails, gomoufox has a Go fallback
(`go install github.com/ehmo/gomoufox/cmd/gomoufox@latest`) and gum has an
official installer that verifies a SHA-256 checksum before writing.

**The binary installs but is "not found".** gum's installer writes to
`~/.local/bin` and Go writes to `$(go env GOPATH)/bin`. If either is not on
`PATH`, add it to your shell profile. `doctor.sh` warns about this before it
bites.

**`gum doctor` complains after a clean install.** Usually it only means no
Google account is connected yet. That step is yours:

```bash
gum login --service <name>
```

It opens a browser against your own Google account and stores a refresh token
in the OS keychain. Nothing here runs it for you and nothing here reads it.

## What it will not do

It does not install Homebrew or Go, does not write credentials or tokens, does
not run `gum login`, and does not fetch a single page of anyone's data. What
you do with the browser afterwards is a separate decision, and the usual rules
apply: read `robots.txt`, keep a civil rate, and do not use an anti-fingerprint
browser to get around a site that has told you no.
