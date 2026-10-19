# Third-party notices

## Chrono 2.10.3

Spotlight Han includes the Chinese and English date parsers from [wanasit/chrono](https://github.com/wanasit/chrono), distributed under the MIT License. The exact npm version and integrity hashes are recorded in `tools/date-parser/package-lock.json`.

The generated `Sources/HanSearchCore/Resources/NaturalDates.js` combines Chrono with Han's adapter in `tools/date-parser/entry.js`. The original license is preserved in `Sources/HanSearchCore/Resources/Chrono-LICENSE.txt` and included in the app's resources. The root MIT license does not replace this notice.

The adapter adds Monday-based Chinese week expressions, afternoon range handling, title/duration/notification extraction, and rejection of unsupported recurrence. Swift performs date validation and EventKit writing separately, after confirmation.

esbuild is a development-only bundler. Node.js and esbuild are not included in the running app. See [rebuilding the parser](tools/date-parser/README.md).
