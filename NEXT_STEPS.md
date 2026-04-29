# Orion — Next Steps

This document covers the manual work that remains before Orion builds and ships, and the v2 cleanup tasks that are nice-to-have but not blocking.

## What's already done

- ✅ Lenny fork copied to `~/Library/Mobile Documents/com~apple~CloudDocs/claude/Orion` (in iCloud Drive, alongside the source GIF assets in `claude/MiniJustin/Justin/`).
- ✅ Heavy Lenny data deleted: `ExpertAvatars/` (16MB of headshots), `StarterArchive/` (~5MB of newsletter/podcast content), and Lenny demo media.
- ✅ All user-facing "Lil-Lenny" branding strings renamed to "Orion" / "Orion".
- ✅ Justin system prompt rewritten for **Orbit founder framing** in `LilAgents/Session/ClaudeSessionState.swift` — encodes the five Orbit voice pillars (Linus Tech Tips, Marques Brownlee, Ricky Gervais, Lenny's Newsletter, Elena Verna — tone only), nine Orbit writing rules, and the slop-detector anti-patterns. Canonical source: [get-orbit `lib/admin/voice-guidelines.ts`](https://github.com/justinwilliames-sketch/get-orbit/blob/main/lib/admin/voice-guidelines.ts).
- ✅ Welcome copy, popover subtitle, settings About panel, and prompt chips all retuned for Orbit positioning. Prompt chips map to real Orbit guide topics (Apple MPP, Braze naming, win-back flows, list hygiene, send-time optimisation, 72-hour aha-moment, retention economics).
- ✅ The "Lenny source" Settings tab is hidden. The pane file remains in the tree for upstream merge compatibility.
- ✅ Sparkle auto-update keys stripped from `Info.plist`.
- ✅ `CFBundleDisplayName` and `CFBundleName` set to "Orion" in `Info.plist`.
- ✅ **Hand-authored animated Orion sprites installed** — four 36-frame GIFs (front, back, walk-left, walk-right) in `LilAgents/CharacterSprites/`. The runtime loader was updated to load GIFs for all four directions; `NSImageView.animates` was already true upstream.

## ⚠️ Required before first build (in Xcode)

These are easier in the Xcode UI than via hand-editing `project.pbxproj`. Open `~/Library/Mobile Documents/com~apple~CloudDocs/claude/Orion/lil-agents.xcodeproj` and:

1. **Rename the scheme.**
   Product → Scheme → Manage Schemes → select `LilAgents` → rename to `Orion`.

2. **Set the bundle identifier.**
   Click the `LilAgents` target → Signing & Capabilities tab → set Bundle Identifier to something like `team.yourorbit.Orion` or `com.justinwilliames.Orion`. The current value is whatever Ben Shih had — you cannot ship under his identifier.

3. **Set the signing team.**
   Same tab → Team → select your Apple Developer account. Without this, the app will only run unsigned via Xcode (fine for local development).

4. **Replace the app icon.**
   `LilAgents/Assets.xcassets/AppIcon.appiconset/` currently contains the Lenny app icon. Drop your own `.png` files in (or remove the existing slots and add new ones) for sizes 16, 32, 64, 128, 256, 512, 1024 (×1 and ×2). You can generate a full set from a single 1024×1024 PNG using a tool like [appicon.co](https://appicon.co/).

5. **Optional: rename `lil-agents.xcodeproj` → `orion.xcodeproj`.**
   Cosmetic only. If you do, also rename inside Xcode (File → Rename Project) to keep the scheme references consistent. Skip if you don't care — the project filename is invisible to end users.

## Drop in your ChatGPT-generated sprites

When you have the real Orion sprites, replace these files (exact filenames matter):

```
LilAgents/CharacterSprites/main-front.png             304 × 415 PNG, RGBA
LilAgents/CharacterSprites/main-back.png              304 × 415 PNG, RGBA
LilAgents/CharacterSprites/main-left.png              304 × 415 PNG, RGBA
LilAgents/CharacterSprites/main-right.png             304 × 415 PNG, RGBA
LilAgents/CharacterSprites/lil-justin-walk-left.gif   304 × 415 GIF, transparent, looped
LilAgents/CharacterSprites/lil-justin-walk-right.gif  304 × 415 GIF, transparent, looped
```

The placeholder generator script lives at `/tmp/lil_justin_placeholders.py` if you ever want to regenerate them. It uses Python PIL.

**Tip for ChatGPT prompting:** ask for one character in the HubSpot pixel-people aesthetic, generate one pose at a time using the same character reference, and ensure the output is on a transparent background. The walk GIF is the hardest part — you may want to generate two or three slightly different walking-pose PNGs and combine them into a GIF using `ffmpeg` or an online tool, since most image models won't produce animated GIFs natively.

## ⚠️ One-time setup: enable Sparkle auto-update (5 min)

Orion's Info.plist now points Sparkle at GitHub Releases for auto-update. The CI workflow will sign each `.dmg` with an Ed25519 private key and attach an `appcast.xml` to the release — but only if a repo secret is in place. Until you add it, the auto-update flow is dormant (no harm — Sparkle is also disabled at launch via `startingUpdater: false`, so users see no failed-update dialogs).

**Step 1 — add the Sparkle private key as a GitHub Actions secret.**

```
gh secret set SPARKLE_ED_PRIVATE_KEY --repo justinwilliames-sketch/orion-by-orbit
# When prompted, paste this exact value (no trailing newline):
#
# <PASTE_PRIVATE_KEY_HERE — Claude shared the value in chat, not here>
```

Or via the web UI: **Settings → Secrets and variables → Actions → New repository secret** → name `SPARKLE_ED_PRIVATE_KEY`, value `<PASTE_PRIVATE_KEY_HERE — Claude shared the value in chat, not here>`.

The matching public key (`bNQR7ti9TfIVO9mwWWH5hge2A8JzV98AczkncKfitQY=`) is already baked into `LilAgents/Info.plist` as `SUPublicEDKey`. Do NOT change it — Sparkle will refuse to install updates signed with a different key.

> **Note on the rotated key:** an earlier commit briefly committed the original private key directly into this file. That key is now considered compromised and was rotated to the value above before the public pipeline ever signed anything with it. The earlier key value still appears in git history but cannot sign valid updates for the current `SUPublicEDKey`.

**Step 2 — re-enable Sparkle's launch-time check.** Once the secret is set and at least one tagged release has shipped a signed `.dmg` + `appcast.xml`:

In `LilAgents/App/LilAgentsApp.swift`, change:
```swift
updaterController = SPUStandardUpdaterController(
    startingUpdater: false,    // ← change to true
    updaterDelegate: nil,
    userDriverDelegate: self
)
```

And in the same file, unhide the **Check for Updates…** menu item (remove the `updateItem.isHidden = true` line).

**Step 3 — tag and ship.** Push a fresh semver tag (`git tag v0.1.4 && git push origin v0.1.4`). CI will sign the new `.dmg`, generate `appcast.xml` referencing it, and attach both to the release. Older installs will see "Update available" within 24 hours of next launch (or immediately if the user clicks "Check for Updates…" once you've unhidden it).

**Sparkle + unsigned-app caveat:** because Orion is unsigned (no Apple Developer ID), Sparkle still works for *the update mechanism itself* — Sparkle's bundled XPC service is signed by the Sparkle project — but the new `.app` will still be quarantined by Gatekeeper on first relaunch. Users will need to re-run the `xattr -dr com.apple.quarantine` command after each update. That's the cost of unsigned distribution.

**Don't lose the private key.** It's in this `NEXT_STEPS.md` for now, but once you set the GitHub Actions secret you can't read it back. If you ever lose it, you'll need to generate a new keypair, update `SUPublicEDKey` in `Info.plist`, and ship a new release — but existing installs won't be able to verify updates signed with the new key, so they'll silently stop receiving updates. Don't lose it.

---

## Future enhancement: bundle the Orbit guide corpus

The current architecture leaves the upstream `LocalArchive.swift` / `ClaudeSessionTransport+Archive.swift` / `StarterArchive/` plumbing in place. None of it is invoked at runtime today, but it's the natural home for a bundled Orbit guide corpus if you want Orion to ground answers in actual guide content (not just topical knowledge).

The path would be:

1. In `get-orbit`, run the existing markdown export utility (`lib/guides/markdown-export.ts`) over the 95 TSX guides to produce a folder of `.md` files.
2. Drop the resulting markdown into `Orion/LilAgents/StarterArchive/guides/` matching the existing folder structure (one `.md` per guide).
3. Re-show the "Lenny source" Settings tab (rename to "Orbit guides") by removing the `static var allCases` override in `SettingsView.swift`.
4. Update the system prompt to tell the model "you have an Orbit guide archive available — query it via the `read_excerpt` MCP tool when answering specific guide-shaped questions."
5. Update the welcome copy to mention the bundled guides.

This would give Orion true grounding in current guide content without requiring users to install the Orbit MCP separately. Worth doing once v0.1 validates demand. Not before.

## v2 cleanup (optional, not blocking)

The strip strategy was pragmatic: I removed user-facing Lenny presence and hid the archive-mode UI, but left the underlying Lenny archive Swift code in place so the project still compiles. None of it gets invoked at runtime now, but the dead code is still in the tree. When you have time:

- Remove `LilAgents/Session/LennyArchiveClient.swift`
- Remove `LilAgents/Session/LocalArchive.swift`
- Remove `LilAgents/Session/GuestTitles.swift`
- Remove `LilAgents/Session/ClaudeSessionExpertCatalog.swift`
- Remove `LilAgents/Session/ClaudeSessionExpertResolution.swift`
- Remove `LilAgents/Session/ClaudeSessionExpertTextResolution.swift`
- Remove `LilAgents/Session/ClaudeSessionOfficialArchive.swift`
- Remove `LilAgents/Session/ClaudeSessionTransport+Archive.swift`
- Remove `LilAgents/Character/WalkerCharacterExpertTag.swift`
- Remove `LilAgents/Terminal/MCPConnectionCards+OfficialMCP.swift`
- Remove `LilAgents/App/AppSettings+MCPConfig.swift`
- Remove `LilAgents/App/AppSettings+MCPInstaller.swift`
- Remove `LilAgents/App/SettingsView+SourcePane.swift`
- Then fix every compile error by removing the corresponding callers and import lines.

Expect this cleanup to take 2–3 hours of focused Swift refactoring. Don't bother unless you find yourself confused by the dead paths.

## Things to know about the system prompt

The prompt in `ClaudeSessionState.swift` deliberately:

- Tells the model to **never volunteer your CV or name former employers**. Working history is explicitly out of scope — the credibility frame is Orbit's depth (95 guides, structured methodologies), not the founder's resume. Without this guard, models will reach for it confidently.
- Tells the model to **never break character** when asked what model it is.
- **Mirrors the Caldwell working style** from your `CLAUDE.md` — direct, no sycophancy, willing to disagree. Side effect: Orion will tell users when they're wrong, including potentially in ways that feel blunt to people who aren't expecting it.
- **Forces JSON output** with a single message in the `kind: "lenny"` schema. The string `"lenny"` is the internal parser key inherited from upstream and renaming it would break the transcript renderer. If you ever do v2 cleanup, you can rename the parser kind too.

If you want to test the prompt without rebuilding the app, paste the prompt into Claude or ChatGPT directly and chat — the personality will come through.

## Open questions worth deciding

1. **Is this open-source?** If yes, before pushing to GitHub: confirm you're comfortable with the personality file being public (it's mostly your CLAUDE.md profile distilled), and add a short personal note in `README.md`'s Credits section.
2. **App icon.** The dock-bar character is one thing — the macOS app icon (Finder, Launchpad) is another. You'll want a separate, recognisable icon. A simple "LJ" monogram or a Orion headshot would both work.
3. **Eventually, voice grounding via the Orbit corpus.** If Orion starts feeling generic, the natural next step is bundling the Orbit guide markdown export so he can ground answers in actual guide content. See the "Future enhancement: bundle the Orbit guide corpus" section above. The dormant upstream archive plumbing makes this a content-only change rather than a refactor.

## Verify the build

Once you've done the Xcode renames:

```bash
cd ~/Library/Mobile\ Documents/com~apple~CloudDocs/claude/Orion
xcodebuild -project lil-agents.xcodeproj -scheme Orion -configuration Debug build 2>&1 | tail -40
```

> **iCloud caveat:** the project lives in iCloud Drive. If you ever see weird Xcode errors about missing files or `.DS_Store` conflicts, force iCloud to fully download the folder via Finder → right-click → "Download Now", and add `.DS_Store` to your global git ignore if it's polluting commits.

If the build succeeds, run the scheme in Xcode. Orion should appear above your Dock. Click him to open the popover and ask a CRM question to verify the Justin voice is coming through.

If the build fails, the most likely culprits are:

- A scheme rename that didn't propagate (re-open the project after renaming the scheme).
- Missing signing identity (set Team in Signing & Capabilities).
- A reference in `project.pbxproj` to a file path that has changed (none should have changed, since we kept the `LilAgents/` source folder name).
