# Playbook — Orion → Orbit transformation (walking sprite → menubar chat)

App repo: `/Users/justin/code/orion-by-orbit` (Xcode/SwiftPM, sources under `LilAgents/`).
Web repo: `/Users/justin/code/get-orbit`.
Build: the project is an Xcode project (`lil-agents.xcodeproj`) — build with `xcodebuild -project lil-agents.xcodeproj -scheme <scheme> -configuration Debug build` OR the repo's build script under `Scripts/` if present (check `Scripts/` first). Must end with a successful build (BUILD SUCCEEDED). Each agent must confirm the build.

## Decisions (Justin, 2026-06-30)
- **Sprite → menubar.** Remove the walking-sprite UI entirely; summon the SAME chat (TerminalView + ClaudeSession) from the menubar icon, like Comet/Pulsar. Pure AppKit (the app already has an NSStatusItem + is LSUIElement/.accessory). NOT SwiftUI MenuBarExtra.
- **Same functionality.** Keep all of Session / Terminal / Memory / QuickTools / Speech. Only the sprite presentation goes.
- **Rebrand Orion → Orbit** (product). KEEP internal codenames `LilAgents`/`LilJustin` + folder structure + `lil-agents.xcodeproj` (like Pulsar keeps `CaldwellDashboard`). Fork-from-LilLenny credit stays.
- **Full rebrand reach:** repo + get-orbit listing too (autonomous loop).
- **Execution:** autonomous loop, commit each phase, build green throughout.

## Architecture facts (from exploration a0acda8)
- Chat is FULLY DECOUPLED from sprite. `Terminal/TerminalView.swift` (chat UI) + `Session/ClaudeSession.swift` (engine) have ZERO sprite deps.
- The sprite (`Character/WalkerCharacter*`) only PARENTS the popover window. `WalkerCharacterPopoverWindow.swift:438-770` creates the popover NSWindow + hosts TerminalView. `WalkerCharacterSessionWiring.swift` wires ClaudeSession↔TerminalView (reusable).
- Entry: `App/LilAgentsApp.swift` (@main, AppDelegate, `.accessory`, `Settings` scene). `App/LilAgentsApp+MenuBar.swift` already builds an NSStatusItem with a menu (currently toggles the sprite via `toggleChar1`). `App/LilAgentsController.swift` owns the 60fps display-link tick + the WalkerCharacter.
- Product name "Orion by Orbit" in Info.plist; bundle id `team.yourorbit.Orion`; ~40 "Orion", ~25 "LilJustin", ~190 "LilAgents" refs.

## Approval gates (STOP, never auto-fire)
- `git push` on the app repo — COMMIT ONLY (Justin reviews + pushes).
- Deploying / pushing get-orbit — listing edits stay on a branch, NO deploy.
- The GitHub **repo rename** (orion-by-orbit → ?) — GATED on Justin's NAME pick (the convention `orbit-by-orbit` is recursive/awkward; offer `orbit-app` / `orbit-macos` / `orbit`). Do the rename only after he picks.

## Phases (idempotency = ledger-has)
1. `menubar-chat` — Extract the popover-window creation (`WalkerCharacterPopoverWindow.swift:438-770`) into a standalone factory (e.g. `App/ChatPopoverController.swift`) that owns the popover NSWindow + a `TerminalView` + calls the session wiring. Wire the existing menubar status-item button (`LilAgentsApp+MenuBar.swift`) to TOGGLE this popover, anchored to the status-item button frame (close on Escape / click-outside). ADDITIVE — do NOT delete the sprite yet (both can coexist for verification). Build green. Commit "Menubar summons the chat popover".
2. `delete-sprite` — Delete the `Character/` walker system (WalkerCharacter, Core, Movement, Visuals, ExpertTag, Bubble, FollowUps, BubbleClickView, Types — but KEEP the extracted factory + session wiring), `Integrations/CalendarTooltipProvider.swift`, the display-link/tick loop + WalkerCharacter creation in `LilAgentsController.swift`, and the sprite GIF assets (CharacterSprites). Build green. Now menubar-only. Commit "Remove walking-sprite system".
3. `rebrand` — Orion → Orbit PRODUCT: Info.plist CFBundleName/CFBundleDisplayName → "Orbit"; bundle id → `team.yourorbit.Orbit`; menu items ("Show Orion"→"Show Orbit", "Back to Orion"→…), window titles, Sparkle update dialogs, the expert/persona display name "Orion"; the built `.app` name → Orbit.app; new Orbit menubar + app icon (indigo-squircle approach like Pulsar — pick an orbit/planet/sparkles glyph). KEEP `LilAgents`/`LilJustin` codenames, folder structure, `lil-agents.xcodeproj`. Build green. Commit "Rebrand Orion to Orbit".
4. `listing` — get-orbit: rebrand the Orion listing page → Orbit (page content, headings, nav `components/nav.tsx`, `app/sitemap.ts`, CTA, the icon → an orbit-mark png). Keep "Forked from LilLenny". On the existing `pulsar-listing` branch (or a new branch), COMMIT only, NO deploy. Commit "List Orbit (ex-Orion) free download".
5. `repo-rename` (GATED) — once Justin picks the name: `gh repo rename <name> -R justinwilliames/orion-by-orbit`; update the listing CTA + homepage (`get.yourorbit.team/<name>`) + Info.plist SUFeedURL + README links + `git remote set-url`. Flag the name options first.

## Per-unit loop
implement → build (BUILD SUCCEEDED) → commit (subject above) → ledger-add → advance. Never push app repo. get-orbit stays on a branch, undeployed. Repo rename gated on name pick.

## Done
All code phases committed → status blocked "needs approval: app-repo push + get-orbit deploy + repo-name pick". Surface full wrap-up to Justin.

## Runtime-verification caveat
The build passing does NOT prove the menubar chat works at runtime (GUI, clicking the icon, typing). Phase order is additive-first (menubar-chat BEFORE delete-sprite) so the working sprite survives until the menubar path is in; everything is commit-only/reversible. FLAG to Justin that he must runtime-test the menubar chat.
