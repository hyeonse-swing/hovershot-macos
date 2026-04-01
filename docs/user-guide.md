# HoverShot User Guide

[한국어 버전](user-guide.ko.md)

## What It Is

`HoverShot` is a macOS menu bar app.

It lets you:
- capture a screen area
- capture a window
- keep captured shots floating above other apps
- search and manage saved shots
- record an area or a window
- trim recordings and export GIFs

## Install And First Launch

### If You Received A Team Package

1. Unzip the package you received
2. Move `HoverShot.app` into `/Applications` or another app folder
3. Launch `HoverShot.app`
4. Find the icon in the macOS menu bar

### If macOS Blocks The App

Because the current build is locally signed and not notarized:
1. right-click `HoverShot.app`
2. choose `Open`
3. confirm that you want to open it

If that still fails:
1. open `System Settings > Privacy & Security`
2. allow the blocked app
3. launch it again

### Required Permissions

You may need:
- `Screen Recording`
- `Microphone` if you want microphone audio during recording

Important:
- grant `Screen Recording` to `HoverShot.app`
- after granting `Screen Recording`, quit and reopen the app once
- if you previously used a developer build through `swift run`, make sure you are granting permission to the app bundle you actually use

## Main Menu

Menu bar actions currently include:
- `Settings...`
- `Open Shots Browser`
- `Open Recordings Browser`
- `Import From Clipboard`
- `Capture Area`
- `Capture Window`
- `Re-capture Last Area`
- `Timed Capture`
- `Record Area`
- `Record Window`
- recording controls such as pause, resume, marker, and stop

## Daily Screenshot Workflow

### Capture Area

1. Open the menu bar app
2. Click `Capture Area`
3. Drag over the part of the screen you want
4. Release to create a floating shot

### Capture Window

1. Open the menu bar app
2. Click `Capture Window`
3. Choose a shareable window from the picker
4. Click `Capture`

### Re-capture Last Area

This repeats the last successful area capture rectangle without drawing it again.

### Timed Capture

Use `Timed Capture` if you need a short delay before selecting the target area.

Typical use cases:
- opening a menu before capture
- preparing a hover state
- capturing a transient popover

## Floating Shots

When a shot appears, you can:
- drag it
- resize it from the edges
- scroll on it to change opacity
- right-click for more actions

### Right-Click Actions

- `Copy Image`
- `Export...`
- `Reveal in Finder`
- `Annotate...`
- `Fit to Screen`
- `Reset Size`
- visibility options
- opacity presets
- `Ignore Mouse Clicks`

### Resize Behavior

- Shots can be resized smaller than the original capture
- `Fit to Screen` resizes the shot to fit the current display
- `Reset Size` returns the shot to its default opening size

### Ignore Mouse Clicks

If you enable click-through and cannot interact with a shot:
- open the menu bar app
- use `Floating Shots`
- choose the shot and disable `Ignore Mouse Clicks`

## Shots Browser

Open it from `Open Shots Browser`.

You can:
- search by title, OCR text, tags, or notes
- review OCR results
- rename shots
- edit notes and tags
- mark favorites
- reopen a shot
- annotate
- copy
- export
- reveal in Finder
- delete one or multiple shots

### Multi-Select Delete

You can select multiple items in the left list and delete them together.

You can also right-click the selection and use the delete menu there.

## Annotation

Open a shot, then choose `Annotate...`.

Available tools:
- `Highlight`
- `Redact`
- `Arrow`
- `Step`
- `Text`

Save applies the annotation back to the floating shot, browser preview, copy/export, and library.

## Clipboard Import

Use `Import From Clipboard` to bring in:
- images
- text
- supported video file references copied from Finder

Imported text becomes a shot card.

## Daily Recording Workflow

### Record Area

1. Open the menu
2. Click `Record Area`
3. Drag to choose a region
4. Use menu bar controls while recording

### Record Window

1. Open the menu
2. Click `Record Window`
3. Choose a shareable window
4. Click `Record`

### Recording Controls

Available during recording:
- `Pause Recording`
- `Resume Recording`
- `Add Edit Marker`
- `Stop Recording`

Note:
- pause/resume currently works as segmented recording
- resumed recording continues as a new part file in the same session

## Recordings Browser

Open it from `Open Recordings Browser`.

You can:
- browse recordings
- preview playback
- edit title, notes, and favorite state
- open
- reveal in Finder
- trim
- export GIF
- delete recordings

## Trim Recording

1. Select a recording in `Recordings Browser`
2. Click `Trim...`
3. Adjust start and end
4. Export the trimmed video

## Export GIF

1. Select a recording in `Recordings Browser`
2. Click `Export GIF`
3. Choose a save location

## Settings And Shortcuts

Open `Settings...` from the menu bar app.

Shortcut settings let you:
- assign a global shortcut
- clear a shortcut
- restore default shortcuts

Rules:
- use at least one modifier such as `Command`, `Shift`, `Option`, or `Control`
- press `Esc` to cancel shortcut recording
- assigning an already-used shortcut moves it to the new action

Typical actions you can customize:
- capture area
- capture window
- re-capture last area
- timed capture
- open shots browser
- open recordings browser
- record area
- record window
- marker and stop actions

## Files And Storage

Typical locations:
- shots metadata: `~/Library/Application Support/HoverShot/shots.json`
- recordings: `~/Movies/HoverShot`

Exports from save panels go wherever you choose.

## Troubleshooting

### The App Keeps Asking For Screen Recording Permission

Make sure permission was granted to `HoverShot.app`, not only to `Terminal`.

Then:
1. quit the app
2. reopen it

### Floating Shot Is Too Large

Use:
- edge resize
- right-click `Fit to Screen`
- right-click `Reset Size`

### Click-Through Was Enabled By Accident

Use the menu bar app:
- `Floating Shots`
- choose the shot
- disable `Ignore Mouse Clicks`

### A Browser Window Opens On The Wrong Display Or Size

`Shots Browser` and `Recordings Browser` open using standard macOS window behavior and are clamped to the display that currently has the mouse pointer.

If the window feels misplaced:
1. move the mouse to the display you want
2. reopen the browser from the menu bar app

### A Capture Or Recording Does Not Look Right

Try the simplest reset path first:
1. quit `HoverShot`
2. reopen it
3. retry the action once

If the problem is still reproducible, report:
- which action you used
- which display setup you had
- whether the problem happened on capture, floating shot, browser, or export
