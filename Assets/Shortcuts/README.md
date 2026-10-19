# Apple Clock companion

`Spotlight-Han-System-Clock.shortcut` is a single, prebuilt companion. Users inspect it and add it once. The app supplies local JSON (`time`: 24-hour `HH:mm`, `title`: text) through `shortcuts run --input-path`, and requires the exact completion text `SPOTLIGHT_HAN_CLOCK_CREATED_V1` before reporting success. The Clock action uses the two dictionary outputs; no prompt or clipboard variable is used.

`SystemClock.plist` is the reviewable source. It contains dictionary conversion, two key lookups, Apple's Add Alarm action, and a completion text action. No scripts, network actions, or custom alarm engine are included. Apple Clock alarms have minute precision and fire at the next matching time; the app validates the intended date before invoking the companion.

Regenerate after changing source, on a Mac with Shortcuts signing available:

```sh
mkdir -p work
plutil -convert binary1 -o work/SystemClock.shortcut Assets/Shortcuts/SystemClock.plist
shortcuts sign --mode anyone --input work/SystemClock.shortcut --output Assets/Shortcuts/Spotlight-Han-System-Clock.shortcut
python3 script/verify_clock_shortcut.py
```

Apple's signing command contacts Apple to sign the distributable template. Do not put personal data into the source. Keep the filename stable: Shortcuts uses the filename as the imported display name. The verification script checks the signature container and equality with the reviewable source without creating an alarm. CI runs this along with the core checks. Full integration was manually exercised on macOS 26.6.1 using a clearly named test alarm, then the test alarm was removed.
