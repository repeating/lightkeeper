# Changelog

## 1.3.2 — 2026-10-05

- Branded drag-to-Applications installer window with a Retina background and fixed icon positions.
- Fix the mounted DMG volume icon so Finder displays the lighthouse.
- Keep supporting files out of the install view and verify the packaged layout, icon, and app signature.

## 1.3.1 — 2026-10-05

- Fix Claude Code sessions appearing again as gray regular Claude chats.
- Require a confirmed chat view before collecting Claude desktop sidebar rows.
- Remove reclassified Code sidebar entries while preserving separate chat conversations and session states.

## 1.3.0 — 2026-10-05

First public Lightkeeper release.

- Floating native window for Codex and Claude Code sessions.
- Green for running, orange for approvals or questions, red for finished.
- Opens the matching conversation from a session row.
- Reappears on status changes without stealing keyboard focus.
- Optional ChatGPT and Claude desktop monitoring through Accessibility.
- Handles asynchronous Codex question cards while the agent keeps working.
- Preserves uniquely identified desktop rows across sidebar control refreshes.
- Universal macOS 14+ installer for Apple Silicon and Intel.
- MIT license. Ad-hoc signed; not notarized yet.
