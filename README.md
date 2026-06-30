<div align="center">

# Orion

### [Orbit](https://yourorbit.team)'s menu-bar lifecycle assistant.

A free macOS menu-bar app built by Orbit. Click Orion in your menu bar, ask anything about lifecycle marketing, deliverability, Braze, or retention. Direct, no-fluff answers in the Orbit voice, with real Orbit guides cited as sources.

[![Latest release](https://img.shields.io/github/v/release/justinwilliames/orion-by-orbit?include_prereleases&label=latest&color=6366F1)](https://github.com/justinwilliames/orion-by-orbit/releases/latest)
[![License](https://img.shields.io/badge/license-MIT-6366F1)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-14%2B-6366F1)](https://www.apple.com/macos/)

[**↓ Download Orion**](https://github.com/justinwilliames/orion-by-orbit/releases/latest)

<sub>Forked from [LilLenny](https://github.com/hbshih/lenny-lil-agents).</sub>

</div>

---

## Install in 3 steps

### 1. Download the `.dmg`

Grab the **latest** `.dmg` from [the Releases page](https://github.com/justinwilliames/orion-by-orbit/releases/latest) and open it.

### 2. Drag **Orion** into Applications

Drag the Orion icon into the **Applications** shortcut inside the mounted DMG window.

### 3. ⚠️ Run this in Terminal once

Orion is unsigned (free side-project, no Apple Developer ID), so macOS Gatekeeper will block it on first launch. Open **Terminal** and paste:

```bash
xattr -dr com.apple.quarantine /Applications/Orion.app
```

Then double-click Orion in Applications. Orion appears in your menu bar (top-right).

> **Don't want to use Terminal?** Right-click `Orion` in Applications → **Open** → confirm. Or System Settings → Privacy & Security → "Open Anyway". Either works.

---

## What you can ask

Click Orion. The popover shows 4 random prompt chips drawn from Orbit's full guide library — try one, or type your own. Orion answers in the Orbit voice, grounded in actual Orbit guide content with sources cited.

Some examples of what he'll handle well:

- **Lifecycle programs** — onboarding flows, win-back, abandoned cart, replenishment, post-purchase, sunset
- **Deliverability** — Apple MPP, Gmail clipping, SPF/DKIM/DMARC, BIMI, reputation recovery, list hygiene
- **Channel craft** — subject lines, preheaders, dark mode, mobile design, accessibility, Liquid templating
- **Strategy & economics** — retention ROI, LTV, CRM vs CDP, building a lifecycle team, cadence
- **Measurement** — A/B test sample sizes, holdouts, incrementality, false positives, churn cohorts
- **Tools** — Braze, Iterable, Customer.io, HubSpot — what each gets right and wrong

For deeper, structured Orbit tooling (88 guides, 50+ skills, native Braze API), install the full **[Orbit MCP for Claude Desktop](https://yourorbit.team/download)**. Orion will use those tools when they're available.

## What's in the box

- **88 Orbit guides bundled offline** — the full live corpus is shipped inside the app. On every question, the top 3 most relevant guides get spliced into the prompt so answers are grounded in the actual published content, not just slug-citations.
- **Auto-updates** — Sparkle keeps you on the latest. After each update, a one-click Gatekeeper helper handles the unsigned-app dance for you.
- **Launch at login** — on by default. Toggle in Settings.
- **MCP sync from Claude Desktop** — Orion can mirror the MCP servers you've already configured in Claude Desktop, so any tools you use there work here too.

## Connect a model provider

Orion needs a model. Open **Settings → Models** and pick one:

| Provider | What you need |
|---|---|
| **Claude Code** | The CLI installed and logged in. Auto-detected. Free with your Claude.ai subscription. |
| **Codex / ChatGPT** | The Codex CLI installed and logged in. Auto-detected. Free with your ChatGPT Plus subscription. |
| **OpenAI API** | An API key. Pay-as-you-go via OpenAI. |

Automatic mode prefers Claude Code → Codex → OpenAI in that order, depending on what you have available.

## Privacy

- **No analytics, no telemetry, no backend** — Orion runs entirely on your Mac.
- **Settings stay local** — provider choice, API keys, onboarding state all live in macOS `UserDefaults`.
- **Conversation traffic** goes only to the provider you connected (Claude / Codex / OpenAI). Not to me.
- **MIT licensed** — fork it, audit it, change it.

---

<details>
<summary><b>Developer notes — building from source, customising the personality, releasing</b></summary>

### Build from source

Clone, open in Xcode 16+ on macOS 14+, run the `LilAgents` scheme. Or from the command line:

```bash
git clone https://github.com/justinwilliames/orion-by-orbit.git
cd orion-by-orbit
xcodebuild -project lil-agents.xcodeproj -scheme LilAgents -configuration Debug build
```

See [NEXT_STEPS.md](NEXT_STEPS.md) for the one-time Xcode setup (scheme rename, bundle identifier, signing team, app icon).

### Customise the personality

The system prompt lives in [`LilAgents/Session/ClaudeSessionState.swift`](LilAgents/Session/ClaudeSessionState.swift) (`func buildInstructions`). It encodes the Orbit founder framing, five voice pillars, nine writing rules, the slop-detector anti-patterns, and the full slug→title manifest of the bundled Orbit guides for source citation. The canonical voice document this is distilled from lives in [`get-orbit/lib/admin/voice-guidelines.ts`](https://github.com/justinwilliames/get-orbit/blob/main/lib/admin/voice-guidelines.ts).

### Refresh the bundled guides corpus

Orion ships with the full Orbit guides export at [`LilAgents/orbit-guides.json`](LilAgents/orbit-guides.json). When new guides go live or existing ones change, regenerate the bundle:

```bash
./Scripts/refresh-orbit-guides.sh
git commit -am "Refresh Orbit guides corpus"
```

The script pulls from `https://yourorbit.team/api/guides/export`, validates the payload, and writes the new JSON in place. The retrieval is keyword-overlap scoring inside [`LilAgents/Session/OrbitGuidesCorpus.swift`](LilAgents/Session/OrbitGuidesCorpus.swift) — no embeddings, no network calls at runtime.

To fork this for your own menu-bar assistant:

1. Swap the system prompt for your voice and domain.
2. Swap the bundled corpus JSON for your own knowledge base in the same export shape.
3. Update bundle display name in `LilAgents/Info.plist`, welcome copy in `LilAgents/Terminal/TerminalView+TranscriptBehavior.swift`, and Settings → About in `LilAgents/App/SettingsView+ModelsPane.swift`.

### Releasing

Releases are built and published automatically by [`.github/workflows/build.yml`](.github/workflows/build.yml):

- **Every push to `main`** → CI builds a fresh `.dmg` and refreshes the rolling `latest` release.
- **Every `v*.*.*` tag push** → CI publishes a new tagged release that becomes the canonical "Latest" on the homepage.

```bash
# From a clean main branch:
git tag v0.1.2
git push origin v0.1.2
```

The CI run takes ~3 minutes. The `.dmg` ships unsigned with the install instructions baked into each release body.

### Credits

Orion builds on two open-source predecessors, both MIT-licensed and credited in [LICENSE](LICENSE):

- **[lil-agents](https://github.com/ryanstephen/lil-agents)** by Ryan Stephen — original macOS dock companion concept.
- **[lenny-lil-agents](https://github.com/hbshih/lenny-lil-agents)** by Ben Shih — pixel-art sprite layer + terminal-style popover.

</details>

---

<div align="center">

**Made by [Justin Williames](https://get.yourorbit.team) · MIT licensed · macOS 14+**

</div>
