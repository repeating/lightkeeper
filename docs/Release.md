# Lightkeeper 1.3.2

A small native macOS window that tells you when your Codex or Claude Code session needs you.

## Install

1. Download **Lightkeeper.dmg** below.
2. Open it and drag **Lightkeeper.app** into **Applications**.
3. Open Lightkeeper and start a Codex or Claude Code session.

**Requires macOS 14+**, on Apple Silicon or Intel. No developer tools are needed to run the app.

The release is ad-hoc signed and **not notarized**. If macOS blocks the first launch, attempt to open the app, then choose **System Settings → Privacy & Security → Open Anyway**. [Apple's instructions](https://support.apple.com/102445).

## Improved installer in 1.3.2

Opening the DMG now shows a compact branded installer window with Lightkeeper and Applications side by side. Drag the app along the arrow into Applications. Finder now shows the lighthouse on the mounted disk as well as the app.

## Also included: the 1.3.1 fix

Claude Code sessions no longer appear again as gray Claude desktop chats. Sidebar tracking now requires a confirmed chat view, and entries identified as Code sessions are removed instead of kept as unavailable. Separate regular chats keep their own identities and status.

## Included

- Green running, orange needs you, red finished.
- Click a session to open its conversation.
- Hide keeps monitoring active in the Dock; status changes reopen and expand the window.
- Optional ChatGPT and Claude desktop chat monitoring through Accessibility.
- MIT-licensed source code.

Codex and Claude Code monitoring need no Accessibility access. For optional desktop chats, use Setup to enable monitoring and authorize Lightkeeper. An updated ad-hoc build can require removing the old Accessibility entry and adding the new app again. Gray means status unavailable; hidden or unsupported controls are never treated as completion.

Browser tabs and cloud-only Codex sessions are not monitored. The internal app formats can change after upstream updates.

Download **SHA256SUMS.txt** alongside the assets and run `shasum -a 256 -c SHA256SUMS.txt` in that directory to verify the DMG and app ZIP.

[Source and contribution guide](https://github.com/repeating/lightkeeper)
