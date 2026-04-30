# Release runbook — Orion by Orbit

How to ship Orion, and what to do if the Sparkle signing key is ever lost or compromised.

---

## Normal release flow

```bash
# from repo root
git tag v0.1.X
git push origin v0.1.X
```

CI (`.github/workflows/build.yml`):
1. Runs `swift test` (pure-logic regression suite at `Tests/LilJustinCoreTests/`).
2. Builds an unsigned `Orion.app`, packages it as `Orion-v0.1.X.dmg`.
3. Signs the `.dmg` with the Ed25519 Sparkle key (secret `SPARKLE_ED_PRIVATE_KEY`).
4. Generates `appcast.xml` referencing the new `.dmg` and signature.
5. Creates a tagged GitHub Release (non-prerelease) with both files attached.

Pushing to `main` without a tag publishes a rolling `latest` prerelease — useful for dev iteration, ignored by Sparkle.

**Per memory standing rule:** every regression class gets a test in `Tests/LilJustinCoreTests/` *before* re-shipping. Don't skip.

---

## Sparkle keys — what's where

| Item | Location | Purpose |
|---|---|---|
| Public key | `LilAgents/Info.plist` → `SUPublicEDKey` (`bNQR7ti9TfIVO9mwWWH5hge2A8JzV98AczkncKfitQY=`) | Baked into every shipped `.app`. Sparkle uses it to verify update signatures. **Do not change** unless you're rotating (see below). |
| Private key | GitHub Actions secret `SPARKLE_ED_PRIVATE_KEY` on `justinwilliames-sketch/orion-by-orbit` | Signs the `.dmg` in CI. Cannot be read back once set. |
| Offline backup | **Required** — see DR section below. | If the GH secret is wiped or the repo is lost, this is the only path back to update continuity. |

The matching key pair was generated at fork time. The original private key was briefly committed in `NEXT_STEPS.md`; that key was rotated to the value above before the public pipeline ever signed anything with it. The compromised key still appears in git history but cannot sign valid updates for the current `SUPublicEDKey`.

---

## ⚠️ Sparkle private-key disaster recovery

**If the Sparkle private key is lost, every existing install loses its update chain forever** unless you recover the key or migrate users to a new key.

### 1. Back the key up offline (do this NOW if you haven't)

The private key only lives in the GH Actions secret. GitHub does not allow reading a secret back. If the repo is deleted or the secret is rotated, the key is gone.

**Recommended belt-and-braces backup:**

1. **1Password vault entry** — store the private key as a secure note in a vault you control. Label: `Orion Sparkle Ed25519 private key`. Include the matching public key for cross-check.
2. **Encrypted local archive** — keep a copy in an encrypted disk image (e.g. an APFS sparse bundle protected by a strong passphrase) on your primary machine. Filename: `orion-sparkle-private.txt`.
3. **Off-site copy** — same encrypted archive on a second machine or external drive.

Verify the backup by re-deriving the public key from the private key (Sparkle's `generate_appcast` or `sign_update` will show the public key it would sign with) and confirming it matches `SUPublicEDKey` in `Info.plist`.

### 2. If the key is lost — choose a path

You have two options. Both are bad. The first is less bad.

**Option A: Recover from offline backup.**
Restore the key into the GH Actions secret. Update flow resumes. No user impact.

**Option B: Generate a new keypair (only if A is impossible).**

1. Generate a new Ed25519 keypair using Sparkle's `generate_keys` tool.
2. Update `SUPublicEDKey` in `LilAgents/Info.plist` to the new public key.
3. Set the new private key as `SPARKLE_ED_PRIVATE_KEY` in GH Actions secrets.
4. Ship a new tagged release.

**The cost:** every existing install still has the *old* `SUPublicEDKey` baked in. Sparkle will refuse to install the new release because the signature won't verify against the old public key. Existing users are stuck on whatever version they had — they will never receive another update from this app until they manually re-download and re-install. There is no automated migration path.

This is why offline backup matters.

### 3. If the key is leaked (publicly disclosed)

A leaked private key means an attacker can sign their own `.dmg` and trick Sparkle into installing it as an "update."

1. **Immediate:** rotate to a new keypair (Option B above), accepting the user-impact cost.
2. **Notify:** post in the repo and on the website that users should manually re-download from `get.yourorbit.team` rather than trusting any auto-update.
3. **Audit:** check the GitHub Releases history for any `.dmg` you didn't sign. If one exists, delete it and the matching tag.

---

## Other ops notes

- **Notarization is not configured.** The app ships unsigned (no Apple Developer ID). Users must run `xattr -dr com.apple.quarantine /Applications/Orion.app` after each install and each Sparkle update. Once the Developer ID is provisioned, replace the ad-hoc-signing path with Developer ID + `xcrun notarytool` + `xcrun stapler staple`.
- **Local origin remote** is `origin = https://github.com/justinwilliames-sketch/orion-by-orbit`. The `liljustin-archive` remote points to a tombstone repo and should not receive pushes.
- **Internal Swift symbols** stay as `Whispur*` for upstream merge compatibility (per memory rule). Don't rename them when refactoring fork-local code.
