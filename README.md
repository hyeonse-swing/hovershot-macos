# HoverShot

`HoverShot` is a macOS menu bar utility for floating screenshots and lightweight screen recording workflows.

[한국어 문서](README.ko.md)

It is being built as an internal alternative to ScreenFloat-style workflows:
- capture an area or a window
- keep shots floating above other apps
- annotate, search, copy, export, and organize shots
- record an area or a window
- trim recordings and export GIFs

## Current State

The project is usable on macOS today and is set up for team sharing.

Implemented highlights:
- area capture
- window capture
- timed capture
- floating shots with opacity, visibility mode, click-through, resize, fit-to-screen, and reset-size
- shots browser with OCR, metadata editing, batch delete, and export actions
- annotation tools: highlight, redaction, arrow, step, text
- area and window recording
- recording browser with trim and GIF export
- configurable global shortcuts from `Settings...`

## Features

- Area capture
- Window capture
- Timed capture
- Floating shots with opacity, visibility mode, click-through, resize, fit-to-screen, and reset-size
- Shots browser with OCR, metadata editing, batch delete, and export actions
- Annotation tools: highlight, redaction, arrow, step, text
- Area and window recording
- Recordings browser with trim and GIF export
- Configurable global shortcuts from `Settings...`

## Quick Start

Run directly during development:

```bash
swift run HoverShotMac
```

Build a local app bundle:

```bash
./scripts/build-app-bundle.sh debug
open dist/HoverShot.app
```

Create a shareable team package:

```bash
./scripts/package-team-build.sh
```

Outputs:
- `dist/HoverShot.app`
- `dist/HoverShot-macOS.zip`
- `dist/HoverShot-macOS.sha256`
- `dist/HoverShot Team Guide.md`

## Recommended Sharing

The simplest working setup is:
1. keep the full source in GitHub
2. build a tested package with `./scripts/package-team-build.sh`
3. attach `dist/HoverShot-macOS.zip` to a GitHub Release or share it in Slack/Drive
4. ask non-developers to use the packaged app instead of building from source

This keeps one source of truth for code, one tested binary for the team, and one bundled guide for first-run setup.

## Docs

- English team sharing and release guidance: [docs/team-distribution.md](docs/team-distribution.md)
- Korean team sharing and release guidance: [docs/team-distribution.ko.md](docs/team-distribution.ko.md)
- English end-user usage guide: [docs/user-guide.md](docs/user-guide.md)
- Korean end-user usage guide: [docs/user-guide.ko.md](docs/user-guide.ko.md)

## Notes

- This build is locally signed for internal testing.
- For broader distribution, the next step is `Developer ID signing + notarization`.
