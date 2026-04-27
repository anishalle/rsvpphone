# RSVPPhone
reading using the RSVP method, now on your iPhone!

<img width="1278" height="590" alt="Screenshot 2026-04-27 at 12 41 22 PM" src="https://github.com/user-attachments/assets/f59cde4f-85a2-4637-bf33-a4961fb08ab6" />

yes, im reading the Alchemist, and I'm maybe on the third sentence. cool book.

coming to an app store near you! (soon, once i fund the $100 for an apple developer's license)
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

