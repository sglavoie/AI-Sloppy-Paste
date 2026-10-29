# Sloppy Paste

A native macOS app for storing, searching and pasting text snippets. It replaces
the [AI Sloppy Paste](https://github.com/sglavoie/dev-helpers/tree/main/typescript/ai-sloppy-paste) Raycast extension and
keeps its data format, tags, `{{…}}` placeholder grammar and keyboard shortcuts.

A global hotkey (⌃⌥⌘V by default) opens a Spotlight-style picker. Choosing a
snippet pastes it into the app that was frontmost. The app lives in the menu bar
and has no Dock icon.

## Install

On macOS 15 or later, install the signed and notarized release with Homebrew:

```bash
brew install --cask sglavoie/tap/sloppy-paste
open -a SloppyPaste
```

The release supports Apple silicon and Intel Macs. Homebrew installs the app
and the `sloppyctl` command; no Swift toolchain or local signing setup is needed.
You can also download `SloppyPaste.zip` from the
[latest release](https://github.com/sglavoie/AI-Sloppy-Paste/releases/latest),
unzip it, and move `SloppyPaste.app` to Applications.

Grant Accessibility permission when prompted to enable pasting into other apps.
Update with `brew upgrade --cask sloppy-paste`. Uninstalling with
`brew uninstall --cask sloppy-paste` keeps snippets, drafts, and settings;
adding `--zap` deletes those too.

When switching from a locally signed build, quit the old app and disable its
launch-at-login setting before installing. Remove the old copy from
`~/Applications` so only the Homebrew copy remains. Your data stays in
`~/Library/Application Support/SloppyPaste`. Grant Accessibility permission to
the new copy and re-enable launch at login if desired; the release uses a
different signing identity from local builds.

## Using the picker

Each open starts clean, with an empty search, no filters and the first row
selected. The search field starts unfocused: j/k (or ↓/↑) move through the list.
⌘F, or k on the first row, focuses the search field. With a typed search, Esc
keeps the query and selection and hands the keys back to the list for j/k
navigation; a second Esc closes the picker. Without a search, Esc closes it
immediately. Use **Clear Search and Filters** in ⌘K to reset the query.

Unfinished snippet edits survive closing the picker. **Resume Draft** appears
above the list and in ⌘K; saving or explicitly discarding clears the draft.
Drafts are saved atomically to `drafts.json` next to the snippet data and restored
after quitting, rebuilding, or restarting the app. Starting the same kind of editor
again (New Snippet, New Snippet from Clipboard, or editing the same snippet)
resumes its unfinished draft. Separate editors keep separate drafts; Resume
Draft offers the most recently created unfinished draft first.

Saving or explicitly discarding a draft removes it from recovery. Draft text,
including incomplete tags and surrounding whitespace, is preserved as typed.
If the recovery file cannot be read, it is left untouched and the picker shows
a warning; new drafts stay in memory until the file is repaired and the app
restarted. A failed draft write also shows a warning to keep the app open. If
another copy of Sloppy Paste changes `drafts.json`, this copy stops saving
drafts and warns you to copy its unsaved edits before restarting. The other
copy's recovery file is left untouched.

If a snippet's title, content, description, or tags changed while its draft was
open or in recovery, saving stops and preserves both versions. Copy your draft
edits before discarding it, then reopen the snippet to review the latest version.
Usage counts and bookmark, archive, or pin changes do not block a draft save.
If a snippet's content changes while its placeholder form is open, submitting
stops and keeps the entered values. Go back and reopen the snippet to use its
latest content.

⇧⌘D duplicates the selected snippet and opens the copy for editing. Snippet
content is saved exactly as entered, including indentation and surrounding
blank lines; titles and descriptions are trimmed. A `{{#if ...}}` block must
have a matching `{{/if}}` before saving, so its template syntax cannot be pasted by accident.
New Snippet from Clipboard suggests a title from the first nonempty line.

⌘G opens a list of tags with their snippet counts. Type to narrow it, then ↵
applies the selected tag as the filter chip, or "All Tags" clears it.

Search suggestions narrow as you type operator values, such as `tag:wo`,
`ctx:re`, or `not:tag:pe`. Completed values leave ↵ ready to use a snippet.
When a search or filter has no results, **Clear Search and Filters** returns
to the unfiltered list without changing your sort preference. The same action
is available from ⌘K whenever a search or filter is active.

Quote tag or context values that contain spaces, for example `ctx:"dead code"`
or `not:tag:"old projects"`. Search suggestions add these quotes automatically.

⌃⌘↵ copies the selected snippet and keeps the picker open. Snippets with
placeholders open the usual form first; submitting it returns to the list.
This is also available as **Copy and Keep Open** in the ⌘K action menu.

Use `{{!name}}` to keep a placeholder value out of history. When a key appears
more than once, a `!` on any occurrence prevents saving that key's value,
including when another occurrence declares its choices.

⌘+ (or ⌘=) and ⌘- zoom the picker in and out, and ⌘0 resets it. The whole panel
grows or shrinks with its contents, and the zoom level is remembered.

Drag any border or corner of the picker to resize it. Opposite borders move
together, so the picker grows or shrinks around its centre. The new size is
remembered in points at 100% zoom and restored on the next open; it can also be
typed in under **Settings › Picker › Width / Height** (600×360 to 3000×2000,
760×480 by default). A size larger than the screen is shrunk to fit.

With the ⌘D detail pane open, drag the divider between it and the list to
change the pane's width; double-click the divider to reset it. The width is
remembered like the picker's size and can be set under **Settings › Picker ›
Detail pane width**. The list always keeps at least 280 points.

## Requirements for building from source

- macOS 15 or later.
- The Xcode Command Line Tools with Swift 6.2 or later. Xcode itself is not
  needed. Tests use Swift Testing, because XCTest ships only with Xcode.
- [`just`](https://github.com/casey/just).

## Build

See the available recipes:

```bash
just
```

| Recipe | What it does |
| --- | --- |
| `build` | Debug build of every target. |
| `test` | Run the core and app-state test suites (`swift test`). |
| `test-paste-target-safety` | Run only the paste-back target safety tests. |
| `bundle` | Assemble an unsigned `SloppyPaste.app` in `.build/bundle`. |
| `sign` | Bundle, then sign it with the local signing identity. |
| `install` | Sign, replace `~/Applications/SloppyPaste.app` and launch it. |
| `run` | Sign and launch the app straight from `.build/bundle`. |
| `uninstall` | Quit the app and remove it from `~/Applications`. |
| `show-dr` | Print the designated requirement of the built app. |
| `setup-signing` | One-off: create the local code-signing identity. |
| `release` | Test, build universal binaries, sign with Developer ID, notarize, and archive. |
| `publish` | Publish the prepared GitHub release and update the Homebrew cask. |
| `clean` | Remove build artifacts. |

The package has three targets:

- `SloppyCore`: Foundation-only models, placeholder engine, search, tags and
  storage. Its logic is covered by the core tests.
- `SloppyPaste`: the AppKit and SwiftUI app.
- `sloppyctl`: a small command-line tool on top of SloppyCore (see
  [Migration](#migration-from-raycast)).

The `.app` bundle is put together by hand from `Resources/Info.plist.in` and
`Resources/icon.png`, since there is no Xcode project. The app target uses no
SwiftPM resources for the same reason.

## Local development signing

Homebrew releases are signed with Developer ID and notarized by Apple. The
following setup applies only to builds you compile and install locally.

Accessibility permission is tied to the app's designated requirement. With
ad-hoc signing that requirement changes on every build, so macOS would forget
the permission after each rebuild. To avoid that, the app is signed with a
stable self-signed identity:

```bash
just setup-signing   # once per machine
just install         # every time you want the latest build
```

`setup-signing` creates the "Sloppy Paste Local Signing" certificate in its own
keychain, `~/Library/Keychains/sloppy-paste-signing.keychain-db`, and trusts it
for code signing. It never replaces an existing keychain, because a new
certificate would change the designated requirement. `just sign` unlocks that
keychain on its own, including after a reboot.

To check that a rebuild kept the same identity, compare `just show-dr` before and
after. The output should be identical, naming `dev.sglavoie.SloppyPaste` and the
same certificate leaf hash.

## Publishing a release

Releases follow the same local Developer ID and notarization workflow as
LaunchGrid. Install `gh`, `just`, and Homebrew, and keep a clean clone of
`sglavoie/homebrew-tap` at `../sglavoie_homebrew-tap` (or set `TAP_DIR`).

1. Bump `SloppyCore.version` in `Sources/SloppyCore/SloppyCore.swift`, commit,
   and push to `origin/main`.
2. Run `just release`. It runs the tests, builds both architectures, signs the
   app and `sloppyctl`, notarizes and staples the app, and prepares
   `.build/release/SloppyPaste.zip`, `SHA256SUMS`, and `sloppy-paste.rb`.
3. Run `just publish`, optionally followed by release notes. It verifies the
   prepared archive, publishes the GitHub release at the recorded build commit,
   and commits and pushes the cask update to the tap. A retry checks that an
   existing release contains the same archive before updating the cask.

`SIGN_IDENTITY` can select a Developer ID Application certificate by hash;
otherwise the release script uses the sole matching identity in the keychain.
`NOTARY_PROFILE` selects a `notarytool` keychain profile. It defaults to the
existing `launchgrid` account profile, which can notarize either app. To set up
a separate profile, use `xcrun notarytool store-credentials sloppy-paste
--apple-id <Apple-ID> --team-id <Team-ID>` and set
`NOTARY_PROFILE=sloppy-paste`. Credentials stay in the keychain.

The cask is generated from `Resources/homebrew-cask.rb.in`; make lasting cask
changes there. Release artifacts record their source commit and checksum, and
publishing refuses an archive that differs from an already published version.

## Permissions

### Accessibility

Pasting posts a ⌘V key press to the frontmost app, and that needs Accessibility
permission. On first launch the app asks for it. You can also grant it later from
the menu bar item, from Settings → Pasting, or directly in System Settings →
Privacy & Security → Accessibility.

Until the permission is granted, the app runs in copy-only mode. Choosing a
snippet copies it to the clipboard, a HUD says so, and the picker footer shows a
warning. The app notices the grant on its own, with no restart needed. It also
falls back to copy-only while Secure Input is on, for example in a password
field.

If macOS stops recognising the app, for example after the signing keychain was
recreated, reset the entry and grant it again:

```bash
tccutil reset Accessibility dev.sglavoie.SloppyPaste
```

### Global hotkey

The hotkey uses Carbon's `RegisterEventHotKey`, which needs no permission. You
can change it in Settings → General. If another app already uses the chord,
Settings says it is not available and the previous hotkey stays active.
If the saved hotkey is unavailable at launch, the app registers and saves the
default shortcut instead, so later launches use the same shortcut.

### Launch at login

Turn it on in Settings → General. It uses `SMAppService`, so it only works from
the signed bundle installed in Applications. If macOS wants approval,
Settings links to System Settings → General → Login Items.

## Data

Snippets are stored in `~/Library/Application Support/SloppyPaste/data.json`.
It uses the same `StorageData` JSON shape as the Raycast extension's export.

- Writes are atomic and pretty-printed.
- A replace-import first copies the current file to `data.json.bak`.
- Editing the file by hand is fine: the app reloads it when it changes. Save
  through an atomic file replacement, or avoid editing it during an app save;
  an editor that keeps the old file open can still write to its displaced inode.
- If a reload fails, the last good data stays visible, but changes, imports,
  and snippet delivery are blocked until the file can be read again. A partial
  external edit is left in place for its writer to finish; fix the file and
  retry. Editor drafts stay intact.
- App and `sloppyctl` writes use `data.json.lock` to serialize edits across
  processes. Changes made by an external editor that does not use this lock
  are checked again during the atomic file swap; when a competing version is
  found, it is restored and the app reports a conflict.
- A data file with a newer storage version is left untouched and blocks changes
  and imports. Imports from newer export versions are also rejected before
  changing existing data. Update Sloppy Paste to a version that supports it.
- Imports using the current export version reject malformed snippet fields;
  older exports retain legacy field conversion.
- Imports reject files containing multiple snippets with the same ID, so no
  snippet is silently dropped. Replace leaves the current file and backup
  untouched when this validation fails.
- A stored file with duplicate snippet IDs is left untouched and blocks edits
  and imports until the IDs are repaired; deleting one ID must not remove
  multiple snippets.
- On startup, an incomplete or undecodable file is never overwritten. It is
  moved aside as `data.corrupt-<timestamp>.json`, the app starts empty, and an
  alert explains how to restore it. A current-version file with a field of the
  wrong type stays in place and blocks changes so it can be repaired. Later
  reloads also leave malformed files in place.

Settings → Data shows the path, with a Reveal button, and the storage size.

## Migration from Raycast

1. In Raycast, open **Manage Snippets** and run **Export All Snippets** (⇧⌘E).
   This writes a JSON file.
2. Optionally, check the export before importing it:

   ```bash
   jq '{version, snippets: (.snippets | length), titles: [.snippets[].title]}' ~/Downloads/<export>.json
   ```

   `sloppyctl stats --data <export.json>` and `search --data <export.json>`
   also inspect exports safely: any migrations happen in memory and the
   original file is left untouched.

3. Import it, with either:
   - the app: menu bar item → **Import…**, or ⇧⌘I in the picker. Merge adds
     snippets that aren't there yet; Replace overwrites everything after writing
     `data.json.bak`.
   - the command line, with the app not running:

     ```bash
     swift run sloppyctl import ~/Downloads/<export>.json            # merge
     swift run sloppyctl import ~/Downloads/<export>.json --replace  # replace
     ```

4. Compare the counts with the export:

   ```bash
   swift run sloppyctl stats
   jq '.snippets | length' ~/Downloads/<export>.json
   ```

5. Turn off the Raycast hotkey: Raycast Settings → Extensions → AI Sloppy Paste
   → Manage Snippets → clear the hotkey. Then disable or uninstall the extension.
   If you want the new app on the same chord, set it in Sloppy Paste's Settings
   after clearing it in Raycast.

Legacy exports that use a single `category` instead of tags are migrated on
import, and the category becomes a tag. Importing the same file twice with Merge
adds no duplicates, because snippet IDs keep the extension's
`snippet-<ms>-<base36>` format.

## sloppyctl

```bash
swift run sloppyctl --help
```

- `import`: merge or replace from an export.
- `stats`: counts that match simple `jq` queries; `--json` is available.
- `search`: the picker's query syntax (`tag:`, `not:tag:`, `ctx:`, `not:ctx:`,
  `is:`, `not:`, quoted phrases, fuzzy words). Plain output has one tab-separated
  row per snippet; control characters and backslashes in fields are escaped.
- `render`: expand a snippet's placeholders with `key=value` pairs.

For omitted choice values, `render` uses the authored default or the first
choice, matching the form. Optional choice wrappers stay disabled without a
nonempty default; an explicit `key=value` overrides that initial state.
Blank values for required placeholders in the selected conditional branch
produce a warning on stderr, even when supplied explicitly as `key=`.

Every command takes `--data <path>` to work on a file other than the live one.
`stats`, `search`, and `render --id` only read that file. They never rewrite,
create, or quarantine it; malformed input reports an error. `import` retains
the store's migration, backup, and quarantine behavior.

## Troubleshooting

- **Paste lands nowhere, or only copies.** Check Accessibility in Settings →
  Pasting. If the target app is slow to take focus, raise the paste delay (60 ms
  by default) in the same section. The app also only copies when the app you
  opened the picker from quit or lost focus before ⌘V, so it never pastes into
  a different app. If another copy changes the clipboard during the delay,
  the paste is cancelled; select the snippet again to retry. If macOS cannot
  create the synthetic ⌘V key events, the snippet stays on the clipboard and
  the HUD prompts you to paste manually.
- **Accessibility is granted but ignored after a rebuild.** Compare
  `just show-dr` with an earlier build. Then run the `tccutil reset` command
  above and grant the permission again.
- **`swift test` can't find `TestingMacros`.** `Package.swift` defaults to the
  Command Line Tools plugin path. If Xcode and Command Line Tools have
  different Swift versions, set `SWIFT_TESTING_PLUGIN_PATH` to the active
  toolchain's `usr/lib/swift/host/plugins/testing` directory.

## Live verification (incomplete)

Partial results and the procedure for each check are recorded in
[`Docs/live-verification.json`](Docs/live-verification.json). The signed rebuild
and reinstall retained Accessibility access. The remaining UI checks need an
idle desktop, and the display checks need a second display. Automated tests
do not count as live verification.

Update the report with `tested_build`, `tested_at`, `tester`, and one
`cases.<key>` entry per check, each with its actual `status` and a concrete
`observed` result. Keep `overall: "incomplete"` while any checks are pending or
blocked; use `overall: "pass"` only after every check passes. Keys:

- Paste targets: `textedit`, `notes`, `vscode`, `terminal-iterm`,
  `browser-field`, `slack`, `full-screen`, `second-display`, `another-space`.
- Permissions and input: `secure-input-copy-only`,
  `accessibility-revoked-copy-only-banner`, `dvorak`,
  `rebuild-reinstall-keeps-accessibility`.
- Focus and panel: `target-stays-frontmost`, `click-outside-hides`,
  `escape-every-depth`, `form-menus-stay-open`, `filter-menus-stay-open`,
  `placeholder-tab-order`, `display-disconnect-repositions`,
  `import-export-focus-return`, `zoom-resizes-panel`, `zoomed-clicks-hit-controls`,
  `resume-draft-after-dismissal`, `duplicate-opens-editor`.
- Settings: `settings-hotkey-recorder`, `launch-at-login`.
