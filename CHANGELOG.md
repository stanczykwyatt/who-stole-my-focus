# Changelog

## 0.1.0 (2026-10-29)

First release.

- **Names the app that stole focus,** what it took focus from, when, and how long it stayed in front, right in the menu bar. Helpers show the app they belong to.
- **Catches steals while you type:** an app that comes forward between your keystrokes is a steal, even though you were pressing keys a moment before.
- **Recognizes your own switches:** clicks, ⌘Tab and other shortcuts, launchers like Spotlight, swipes between Spaces, Mission Control and Notification Center from hot corners, apps you just opened, and apps relaunching after an update.
- **Recognizes focus coming back** to the app you were using after a password prompt, the lock screen, or an app quitting or hiding.
- **Explains system prompts** like SecurityAgent and Touch ID in plain words.
- **Top offenders,** in the menu and across the top of the log window.
- **Log window** with steals or every switch, a reason for each, Copy Details, Show in Finder and Ignore.
- **Copy as CSV** for spreadsheets and bug reports, with your home folder shown as `~`.
- **Quiet at login:** apps sorting themselves out before your first click or keypress aren't counted.
- **Optional notifications** for each steal, off until you turn them on.
- **Adjustable threshold** for how soon after a click or keypress a switch counts as yours, from 0.5 to 3 seconds.
- **Ignore apps** you don't want counted. The lock screen and screen saver are ignored by default.
- **Open at login**, on by default and easy to turn off.
- Runs in the App Sandbox with no network or file access, and needs no permissions at all.
