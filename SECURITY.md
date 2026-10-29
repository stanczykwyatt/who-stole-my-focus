# Security

Who Stole My Focus watches which apps come to the front of your Mac, so it is built to do that with as little access as possible.

## Reporting a vulnerability

Please report security problems privately through **Security → Report a vulnerability** on this repository, not in a public issue. You'll get a reply within a few days.

## What Who Stole My Focus can access

| | |
|---|---|
| **Which app is in front** | macOS tells every app when another app comes to the front, launches, hides or quits, and which Space is showing. It records each app's name, bundle ID and location on disk. It never activates, hides, quits or changes another app. |
| **When you last clicked or typed** | It asks macOS how many seconds ago the last click, keypress, modifier key and trackpad touch happened, and whether ⌘, ⌥ or ⌃ is held right now. macOS answers without any permission. The answer is only a time: never which key, what you typed or where you clicked. |
| **App icons** | It asks macOS for each app's icon to show in the menu and log. |
| **Its own log and settings** | The log (the last 5,000 switches) and your settings, stored in the app's sandbox container. |
| **Notifications** | Optional, off until you turn them on, and macOS asks you first. |

## What it can't access

- **The internet.** The app runs in the App Sandbox without a network entitlement, so macOS blocks every connection. CI checks every build for this.
- **Your files.** It has no file entitlements, so the sandbox blocks every document, download and folder. Copy as CSV puts text on the clipboard rather than writing a file.
- **Other apps.** It has no Apple Events entitlement and no Accessibility permission, so it can't read or control other apps.
- **Your keystrokes.** It never installs an event tap or asks for Input Monitoring. It can't see keys, only how long ago one was pressed.
- **Your screen and windows.** It never requests Screen Recording permission, never captures the screen, and never reads window titles or contents.

Check it yourself on any copy of the app:

```bash
codesign -d --entitlements - "/Applications/Who Stole My Focus.app"
```

The only entitlement is `com.apple.security.app-sandbox`.

## How it handles things

- App names in the log come from other apps, so they are treated as untrusted text. Copy as CSV prefixes anything that looks like a spreadsheet formula, so a name like `=HYPERLINK(...)` opens as plain text.
- A log file that can't be read, whether damaged or written by a newer version, is moved aside rather than overwritten.
- It has no dependencies. Every line that runs is in this repository.
