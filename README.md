# Stashbar

A menu-bar vault for every link you copy. Copy a link anywhere, press **⌥S**, and it's stashed with trackers stripped. Use it as a guest (links stay on this Mac), or sign in with Apple or Google to sync across Macs.

This repo has three parts:

| Folder | What it is |
|---|---|
| `app/` | The native macOS app (SwiftUI + SwiftData, macOS 14+, universal binary) |
| `web/` | The landing page, plus the help, feedback and privacy pages. Static and deployed on Vercel |
| `supabase/` | The database schema for sign-in, sync, profiles, devices and feedback |

`.github/workflows/release.yml` builds and tests the app on every push. Pushing a `v*` tag also builds **Stashbar.dmg** and attaches it to a GitHub Release. The website's **Download** button goes to `/download`, which redirects to the newest release's DMG.

---

## Go live: one-time setup

### 1. Publish the first DMG
1. **Make the repo public.** Visitors download the DMG from GitHub Releases, which only works without a login on a public repo.
2. Tag a release:
   ```bash
   git tag v2.0.0 && git push origin v2.0.0
   ```
3. Wait for **Actions → Build & release** to finish (about 5 minutes). A release with `Stashbar.dmg` appears under **Releases**.

### 2. Deploy the website on Vercel
1. Go to [vercel.com/new](https://vercel.com/new) and import `sajidur7/stash-bar`.
2. Keep the defaults. `vercel.json` already sets the build command and the output folder (`web`).
3. Click **Deploy**. Your site is at `https://<project>.vercel.app`, and `/download` serves the latest DMG.
4. Optional: add `SUPABASE_URL` and `SUPABASE_ANON_KEY` under Project → Settings → Environment Variables, then redeploy. The feedback form then saves to your database. Without them, it opens a prefilled GitHub issue.

### 3. Turn on sign-in and sync (Supabase)
Without this step, the app runs in guest mode only. The sign-in buttons explain that sign-in isn't set up.

1. Create a free project at [supabase.com](https://supabase.com).
2. In **SQL Editor**, paste and run `supabase/migrations/0001_init.sql`.
3. **Authentication → URL Configuration → Redirect URLs:** add `stashbar://auth-callback`.
4. **Authentication → Providers:**
   - **Google:** create an OAuth client in Google Cloud Console (type "Web application"). Add `https://<project>.supabase.co/auth/v1/callback` as an authorised redirect URI, then paste the client ID and secret into Supabase.
   - **Apple:** needs a paid Apple Developer account (Services ID + key). Until it's enabled, "Continue with Apple" shows Supabase's "provider not enabled" message. Google sign-in works without it.
5. In GitHub, open **Settings → Secrets and variables → Actions** and add these secrets:
   - `SUPABASE_URL`: `https://<project>.supabase.co`
   - `SUPABASE_ANON_KEY`: Project Settings → API → `anon` `public` key
   - Optional variable `WEBSITE_URL`: your Vercel URL, used by the Help / Feedback / Privacy links in the app.
6. Tag a new release (`v2.0.1`). DMGs built from then on include sign-in.

---

## Installing on a Mac

1. Download from the website and open `Stashbar.dmg`.
2. Drag **Stashbar** into **Applications**.
3. The app is ad-hoc signed, not notarised, so the first launch shows "Apple could not verify…". Click **Done**, then go to **System Settings → Privacy & Security → Open Anyway**. Or run:
   ```bash
   xattr -cr /Applications/Stashbar.app
   ```
To remove that step, get an Apple Developer ID and set `CODESIGN_IDENTITY` for `app/scripts/build_app.sh`, then add notarisation. That isn't wired up yet.

## Building locally (on a Mac)
```bash
cd app
swift test
./scripts/build_app.sh --dmg      # → app/build/Stashbar.app and app/build/Stashbar.dmg
SINGLE_ARCH=1 ./scripts/build_app.sh   # faster, current architecture only
```
Set `SUPABASE_URL` / `SUPABASE_ANON_KEY` in the environment to build with sign-in.

## What's in the app

The app implements every screen from the Stashbar Redesign v13 handoff:
- **Menu-bar popover (⌥S):** clipboard card with tracker count, Stash it, search, the + button, recent links (pinned first) and the account footer.
- **Canvas (⌘E):** sidebar with All links, Pinned, Unopened, Archive and tags. Card grid with archive and delete, and an Archive view with Restore. Link detail shows the clean URL, removed trackers, tags and notes. Also includes the Add-link sheet, export (JSON, Markdown, bookmarks HTML) and bookmark import.
- **Onboarding:** welcome, sign in or guest, the guest trade-off, shortcut and permissions, "You're set", and "Welcome back" restore.
- **Settings (⌘,):** Account, General, Onboarding & tips, Shortcuts (recordable), Link cleaning (editable parameter list), Appearance (theme, density, menu-bar icon, previews), Data & privacy, and About (update check).
- **Account dialogs:** sign-out confirmation (keep or remove local links), signed out, delete account (with an "I understand" check), account deleted, and profile photo (upload or one of four monograms).

Some parts of the design need things this version doesn't have, so they were left out: the weekly email digest, analytics and crash reporting (Settings says nothing is collected), and the "Sync link previews" toggle.

## Tech notes
- **Sync:** last-write-wins on `updated_at`. Pulls use a server-side `server_updated_at` cursor, deletes travel as tombstones, and row-level security limits every row to its owner.
- **Auth:** Supabase OAuth with PKCE through `ASWebAuthenticationSession`. Tokens are kept in the Keychain.
- **Global shortcuts:** Carbon `RegisterEventHotKey`, so no Accessibility permission is needed.
- **Type and icons:** Geist Mono (SIL OFL, bundled). Site logos come from [Simple Icons](https://simpleicons.org) (CC0), with SF Symbols in the app and Lucide on the website.
