# RSVPPhone

RSVPPhone is a native iPhone translation of RSVP Nano. It keeps the same 640 x 172 landscape reading surface, ORP anchor alignment, smart pacing, phantom words, context preview, chapter navigation, and compact menu structure.

## Build

```sh
xcodebuild test -project rsvpphone.xcodeproj -scheme rsvpphone -destination 'platform=iOS Simulator,name=iPhone 16'
```

If the simulator service is unavailable, build the app target without a destination first:

```sh
xcodebuild build -project rsvpphone.xcodeproj -scheme rsvpphone -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO
```

## Controls

- Long press while paused: play until release.
- Horizontal drag while paused: scrub words with context preview.
- Vertical swipe while paused: adjust WPM in 25 WPM steps.
- Tap the top-left invisible corner zone: open menu.
- In menus, vertical swipe moves selection and tap activates it.

## Imports

Use the import button in the library. Supported inputs are `.rsvp`, `.txt`, `.md`, `.markdown`, `.html`, `.htm`, `.xhtml`, and `.epub`.

