# Contributing to Lightkeeper

Lightkeeper is a Swift package targeting macOS 14+. Use Swift 6 Command Line Tools or Xcode with Swift 6+, plus Python 3 for DMG packaging. Packaging dependencies are installed into a project-local virtual environment.

1. Fork and clone the repository.
2. Make a focused change with a clear problem and resulting behavior.
3. Run `scripts/test.sh` and `scripts/test-monitors.sh`.
4. Run `scripts/test-window.sh` for changes to Hide, focus, Dock or window behavior. It opens an isolated demo.
5. Run `scripts/dmg.sh` for packaging changes.

New adapters should distinguish running, needs-input, finished and unavailable. Losing a connection must never look like completion. Do not infer completion from inactivity, silently grant approvals, or collect conversation contents.

Explain what changed and how you verified it in your pull request. Use synthetic fixtures; omit private transcripts, session IDs and credentials. Diagnostic output contains session titles, so review and redact it before sharing.

GitHub Actions runs the core and isolated monitor checks and builds a universal DMG. The window tests require an interactive Mac and are run locally.

Maintainers can publish future releases through the manually dispatched Release workflow after updating the version in `scripts/build.sh`, adding release notes and pushing the matching tag. Releases remain ad-hoc signed until a Developer ID identity and notarization are configured.
