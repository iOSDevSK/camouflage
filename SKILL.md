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

macOS only, and it installs everything underneath too: Homebrew if the machine
has none, and Go for the fallback path. What you get afterwards is a working
machine, not a list of homework.

It installs and verifies. It collects nothing, schedules nothing, and holds no
credentials.

## Finding the scripts

**`scripts/` is next to THIS FILE, never in the workspace.** Resolve it once,
from the path of this SKILL.md, and use the absolute path from then on. A bare
`scripts/install.sh` run from a project directory fails with a confusing "no
such file", because the skill lives wherever the host installed it:

```
~/.claude/skills/camouflage/       Claude Code, user-wide
~/.codex/skills/camouflage/        Codex
~/.agents/skills/camouflage/       shared ground, also read by Codex
.claude/skills/camouflage/         inside one project
```

### When there is no scripts/ beside it

This happens, and it is not a broken machine. A skill installed from a
catalogue arrives as SKILL.md and nothing else: the listing, the search index
and the install command all deal in the one markdown file, so the scripts this
skill needs never travel with it.

Do not go searching the disk for a copy. Clone the repository over the
incomplete install, which is the same directory, and carry on:

```bash
git clone https://github.com/iOSDevSK/camouflage.git /tmp/camouflage
cp -R /tmp/camouflage/scripts <skill-dir>/scripts
chmod +x <skill-dir>/scripts/*.sh
```

Running `install.sh --yes` afterwards repairs every other installed copy too:
it looks in all three directories above and puts the scripts back beside any
SKILL.md that is missing them.

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
servers are registered with both agents, whether this skill's own scripts are
in place, and what to run for anything missing. Exit code 0 means the stack is
usable.

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

**Homebrew is missing.** The script installs it, using the official installer
from brew.sh unchanged. This is the largest change it makes: Homebrew writes to
`/opt/homebrew` on Apple Silicon or `/usr/local` on Intel and asks for your
password, because those directories belong to root. The dry run shows the exact
command first, and nothing runs without `--yes`.

Afterwards, add its shellenv line to your shell profile or new terminals will
not find `brew`. The script prints the line to copy.

**The tap will not install.** Some taps ship unsigned formulae and newer
Homebrew refuses them until trusted; the script tries `brew trust` when that
subcommand exists. If it still fails, gomoufox has a Go fallback
(`go install github.com/ehmo/gomoufox/cmd/gomoufox@latest`) and gum has an
official installer that verifies a SHA-256 checksum before writing.

**The binary installs but is "not found".** gum's installer writes to
`~/.local/bin` and Go writes to `$(go env GOPATH)/bin`. If either is not on
`PATH`, add it to your shell profile. `doctor.sh` warns about this before it
bites.

**The MCP servers do not appear after a restart.** Check `~/.claude.json`,
which is where Claude Code reads user-wide servers from. A `~/.claude/mcp.json`
holding the same entries is a different file that nothing reads; some setup
tools write it anyway. `install.sh` says which of the two actually got them and
`doctor.sh` flags the decoy.

**`gum doctor` complains after a clean install.** Usually it only means no
Google account is connected yet. That step is yours:

```bash
gum login --service <name>
```

It opens a browser against your own Google account and stores a refresh token
in the OS keychain. Nothing here runs it for you and nothing here reads it.

## What it will not do

It writes no credentials or tokens, does not run `gum login`, and does not
fetch a single page of anyone's data. Nothing happens at all without `--yes`.

What you do with the browser afterwards is a separate decision, and the usual
rules apply: read `robots.txt`, keep a civil rate, and do not use an
anti-fingerprint browser to get around a site that has told you no.
