# Spotlight Han

[繁體中文](README.md) · English

**Find the Mac app or file you remember, even when its Chinese script is different.**

An open-source macOS Spotlight alternative with Traditional/Simplified Chinese matching and an independent local filename index.

[Download Apple Silicon DMG](https://github.com/Enoooch0921/Spotlight-Han/releases/download/v0.8.3/Spotlight-Han-0.8.3-macOS-arm64.dmg) · [Releases / ZIP](https://github.com/Enoooch0921/Spotlight-Han/releases) · [Report an issue](https://github.com/Enoooch0921/Spotlight-Han/issues)

## The problem

An app is named `红果短剧`, but you type `紅果短劇`. A Word document contains `教会活动`, but you search for `教會活動`. Or you need a video urgently and want to search the folders you actually use.

Han matches both Chinese scripts while keeping original filenames and text. Filename and video search uses its own index of folders you select. Document text is indexed locally in selected folders and persisted across launches. Spotlight is an optional supplement, disabled by default.

This is script matching, not synonym search: `影片` and `視頻` are not automatically treated as the same word.

New users get an optional in-app guide. Published v0.8.3 has three steps; the unreleased local revision expands it to six, covering search examples, shortcuts and resume behavior, file scopes, personal sources, everyday tools and a real setup summary. Replay it from the menu or Updates & About.

## What it does

- Launch apps and search filenames, videos, Word/PDF/PowerPoint/Excel/text content, with visible cross-script keyword highlights and hit-centred excerpts.
- Search authorised Notes, Contacts, Calendar, Reminders and a limited Mail scope. Source status distinguishes fresh data, stale/partial copies and failed reads, with timestamps.
- Refresh already-authorised sources in the background without requesting new permissions. Calendar and Reminders refresh every 5 minutes and after change notifications; other connected sources and document indexes every 15 minutes. Refresh can be disabled.
- Create an event with `cal` + Tab, then `tomorrow at 3pm meeting for 30 minutes`. Use `rem` + Tab for a reminder. Chinese works too: `明天下午三點到四點開會`, `30分鐘後喝水`.
- Return opens an editable review. Only **Confirm creation** or ⌘Return writes the item. Choose a saved default calendar or change the calendar for one event.
- Sort event search results by upcoming first, newest date first or oldest date first.
- Calculate expressions, convert units/currencies, open system settings panes and optionally translate queries with Apple's local Translation framework.

Date parsing uses a bundled, pinned [Chrono](https://github.com/wanasit/chrono) parser plus Han-specific Chinese rules in JavaScriptCore. No API key, Node.js runtime or model download is needed for event parsing. This preview supports one-time items; recurrence and ambiguous time clauses require editing. See [third-party notices](THIRD_PARTY_NOTICES.md).

## Install and try

**v0.8.3 is a development preview for Apple Silicon, verified on macOS 26.6.1.** Open the DMG and drag Spotlight Han to Applications, or use the ZIP. The current build is ad hoc signed and **not Developer ID signed or Apple-notarised**; Gatekeeper may prevent a downloaded copy from opening. Packaging as a DMG does not change this. Users who need a trusted, notarised installer should wait for that distribution, or developers can build the source themselves.

With an SDK for macOS 26 and Swift 5.9 or later:

```sh
git clone https://github.com/Enoooch0921/Spotlight-Han.git
cd Spotlight-Han
./script/build_and_run.sh
```

The app targets macOS 14+, but macOS 14/15 and Intel hardware still need real-device validation. Press Control + Option + Space to toggle the launcher, then select the folders to index. You can customise the shortcut or use ⌘Space after turning off the original Spotlight binding. Interface languages: system, Traditional Chinese, Simplified Chinese and English.

Private sources require macOS permissions. Valid grants are reused; revoked access pauses background refresh and shows a reconnect state. Local development signing changes can require reauthorisation.

## Privacy and current limits

Search data stays on the Mac. Personal-source copies stay in memory; selected document text is persisted in the local Han index. Filename metadata is cached locally. There is no analytics service or automatic query upload. Currency conversion downloads a public daily USD rate table; amounts and query text are not sent. Optional web search only runs when selected. Apple translation requires its language resources and macOS 15+.

Han is an early independent launcher and does not yet match all Spotlight features. There is no OCR, no fuzzy synonym search, no realtime exchange-rate feed and no Siri/Apple Intelligence integration. Calendar/Reminders confirmation and EventKit object mapping are tested with a fake writer; real-account writes are not performed by automated tests.

[Full guide (Traditional Chinese)](docs/guide.zh-Hant.md) · [Install details](docs/install.zh-Hant.md) · [MIT License](LICENSE)

If Chinese script differences have made a file hard to find, please share a reproducible example using test data. A report with the macOS/Han version, query and expected result is more useful than a broad feature request.

Spotlight Han is an independent project and is not affiliated with Apple.

### Browse apps without typing

Press **⌘1** for a grid or list of local apps. All Apps uses a stable name order; fixed purpose categories, pinning and manual category overrides keep navigation predictable. Recents include only successful launches through Han.

Create your own sidebar categories and drag app icons or list rows into them. Drag any category to reorder. Custom categories offer 22 system icons and can be renamed or deleted. Local suggestions cover Waves, iZotope, audio/video production, Office and common workflows, while preserving manual assignments. Organization stays on this Mac and never moves or deletes installed apps.

Han checks public GitHub releases at most once daily and offers a DMG download when a compatible newer version is available. Manual checks, preview-release preferences and an auto-check switch are included. Installation remains under your control.

App searches such as `logicpro` now match **Logic Pro**; `fcp` / `fcpx` match **Final Cut Pro**. Curated aliases also include `ps`, `ai`, `ae`, `pr`, `vscode` and `ppt`. Local learning prioritizes repeated choices for the same query and gently adapts to preferred result types across apps, Notes and files. Raw queries and contents are not saved or uploaded; learning can be disabled or cleared.

Chinese names support full Pinyin and Zhuyin; only apps automatically match initials (`hgdj` / `ㄏㄍㄉㄐ`). Search `zdj` for Terminal even with English system app names. Right-click a result to set local custom aliases. Initials are App-only; filenames and personal titles require full phonetic input or an explicit custom alias. Model queries such as dl32 keep their digits.

All searches Han's independent persistent full-text index for selected Word, PDF, PowerPoint, Excel and text files. Background reconciliation reuses unchanged content and removes deleted entries after complete scans. Storage controls, scope removal and per-file failures are visible. Spotlight supplementation is optional and disabled by default. This feature is currently local development work and has not been released.

File results show filesystem creation dates and times, read in the background. Choose relevance, newest first or oldest first; the preference is remembered. Unavailable dates are labelled explicitly and sorted last.
