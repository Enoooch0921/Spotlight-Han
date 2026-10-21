# Date parser bundle

Runtime: a local JavaScriptCore context with the vendored Chrono 2.10.3 Chinese and English parsers. No Node.js, network calls, model download or API key is needed by users. Only the fixed script is evaluated; query text is passed as a function argument.

To rebuild from the exact locked development dependencies (Node.js 22):

```sh
npm ci --prefix tools/date-parser --ignore-scripts --no-audit --no-fund
npm run --prefix tools/date-parser build
```

Commit both the adapter source and generated `Sources/HanSearchCore/Resources/NaturalDates.js` plus `Chrono-LICENSE.txt`. CI rebuilds and checks the generated files match. Normal Swift builds use the checked-in bundle and do not run npm.

`entry.js` extracts dates through Chrono, preserves original text for titles, and adds Han-specific week/range/duration rules. `NaturalTaskParser.swift` converts wall-clock components using the user's calendar/time zone, rejects invalid/past dates and emits a reviewable draft. `TaskComposerView` and `SearchStore+TaskComposer` own the explicit confirmation flow. `TaskService` maps approved values to EventKit objects and commits once.

The bundled parser is not a general language model. The local 1.0.1-dev build adds bounded Chinese daily/weekly/monthly recurrence and ROC-era dates through `RecurringTaskInput` / `TaiwanYearConverter` before Chrono. `TaskRecurrence` selects the next occurrence, skips missing month-days, and is preserved through the reviewed draft into one EventKit recurrence rule. The preview can change frequency/interval or remove recurrence. There is no end condition; yearly/lunar/multi-weekday patterns, multiple independent time clauses and vague times need rewriting or editing in the system app. Reminder recurrence follows the system behavior: the next occurrence becomes available after the current one is completed. The legacy quick-command parser rejects recurrence/ROC input to avoid silently producing a one-time item or losing the era. Do not infer unsupported rules silently.

Verification:

```sh
swift run HanSearchChecks
./script/check_task_composer.sh
```

The second command exercises the real app store with isolated preferences and a suspended fake writer, including cancellation, stale previews, duplicate submission, saved calendar defaults and per-event overrides. It constructs unsaved EventKit objects to check fields, without reading or writing personal events/reminders.
