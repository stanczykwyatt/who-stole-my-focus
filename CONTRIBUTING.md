# Contributing

Thanks for helping out! Bug reports, ideas and pull requests are all welcome.

## Reporting a switch it got wrong

The most useful report is a switch that was judged wrong: a steal that was really you, or a steal it missed. Open the log, switch to **Everything**, right-click the row and choose **Copy Details**, then paste that into a [bug report](https://github.com/stanczykwyatt/who-stole-my-focus/issues/new?template=bug.yml) with what you were doing at the time. The details include the app's name and path, so leave out anything you'd rather not share.

## Getting started

You need macOS 14 or later and Swift 6 (Xcode 16 or the Command Line Tools).

```bash
swift test                # run the tests
scripts/build-app.sh      # build "Who Stole My Focus.app" into ./build
open "build/Who Stole My Focus.app"
```

The logic that decides why each app came to the front, the log, and the wording all live in `Sources/FocusCore`, with tests in `Tests/FocusCoreTests`. Most changes to how switches are judged belong in `FocusTracker.swift` and `Input.swift`, and come with a test in `FocusTrackerTests.swift` that describes the situation.

The menu bar app, the system monitor, the menu and the log window are in `Sources/WhoStoleMyFocus`, tested in `Tests/WhoStoleMyFocusTests` with a private notification center and windows that are never shown. No test activates, hides or changes a real app, or puts anything on screen.

To redraw the art: `swift scripts/make-icon.swift`, `swift scripts/make-art.swift`, and `SCREENSHOT_DIR=docs swift test --filter LogViewTests` for the screenshots.

## Ground rules

- **No network access, ever.** Pull requests that add a network entitlement or third-party analytics won't be merged.
- **No permissions.** Features shouldn't need Accessibility, Input Monitoring, Screen Recording, file access or Apple Events. If one truly needs a permission, it has to be optional and off by default.
- **Never record what people type or see.** Input times only, never keys, text, window titles or screenshots.
- **No new dependencies** without a very good reason. The app has none today, which keeps it easy to audit.
- **When in doubt, don't blame the app.** A missed steal is better than a wrong one.
- Run `swift test` before opening a pull request, and add tests for changes to `FocusCore`.
- Keep commits small, with a short message saying what changed and why.

## Security issues

Please don't open public issues for vulnerabilities. See [SECURITY.md](SECURITY.md).
