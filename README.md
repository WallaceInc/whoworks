# WhoWorks

An iPhone contacts app you can pinch to zoom.

The built-in Contacts app shows one line per person: their name. The Company
field is only ever visible if a contact has no name at all. If you deal with
people through their work, that's the wrong line — which is why people end up
typing the company into the last-name field, wrecking sorting and sharing.

WhoWorks adds a zoom gesture. Pinch out and each row shows more.

| Level | Row shows |
|-------|-----------|
| 0 | Name |
| 1 | Name + company |
| 2 | Name + company + email |
| 3 | Regrouped under **company** headings instead of letters |

Missing fields are omitted rather than left blank. The same four levels are in
the `AA` toolbar menu, since a hidden gesture needs a visible fallback.

## Other behaviour

- **Company inference** — when the Company field is empty, it's derived from a
  work email domain (`someone@acme-tools.com` → Acme Tools). Guesses render
  dimmer than entered values, and ~55 consumer domains are excluded.
- **Search** covers name, company (entered or inferred), job title and email.
- **Swipe** a row left to call or message, right to favourite. Long-press does
  the same for anyone who won't find the swipe.
- **Favourites** pin to the top at every zoom level.
- **Spotlight** — contacts are indexed so they're findable by company from the
  home screen.
- Tapping a row opens the system `CNContactViewController`, so calling,
  messaging, FaceTime and editing behave exactly as they do everywhere else.

Entirely on-device. No network code, no account, no analytics.

## Building

Requires Xcode 26+, iOS 18+ deployment target.

```sh
open ContactsPlus.xcodeproj
```

Set `DEVELOPMENT_TEAM` in the target's build settings to your own, then ⌘R.

The simulator's stock address book has six contacts and almost no company or
email data, which isn't enough to see what the zoom does. A `DEBUG`-only seeder
fills in fixtures:

```sh
xcrun simctl launch booted com.whoworks.ios --seed-test-contacts
xcrun simctl launch booted com.whoworks.ios --density 2   # jump to a zoom level
```

## Layout

```
ContactsPlus/
  Models/       Person, DensityLevel
  Services/     ContactRepository, SpotlightIndexer, FavoritesStore, DebugSeed
  Views/        ContactListView, ContactRowView, SwipeableRow,
                SectionIndexBar, ContactCardView
AppStore/       Listing copy, privacy policy, 6.9" screenshots
site/           whoworks.app — landing, privacy, support
```

## Notes for anyone changing the list

Three things here are load-bearing and look arbitrary:

**The list is a `ScrollView`/`LazyVStack`, not a `List`.** `List` won't hold its
scroll position when row heights change, so a pinch would teleport you. That
choice is why the A–Z scrubber and swipe actions are hand-rolled.

**In `SwipeableRow`, the drag gesture is on the outer container and `.offset` is
applied only to the content.** Put the gesture inside the offset and the drag is
measured in a frame the drag itself is moving — the feedback makes tracking
jitter. Equally, `.contentShape` must come *before* `.offset`: applied after, hit
testing re-anchors to the original rectangle and the row swallows taps meant for
the revealed buttons. Both bugs look unrelated to the line that causes them.

**Swipe direction is judged once per gesture, then locked.** Re-judging on every
update let a vertical scroll re-qualify as a swipe partway down and yank a row
sideways.

Also: contact photos are cached in `ThumbnailCache` because `UIImage(data:)`
decodes on every call, and a row's body re-runs on every frame of a drag.

## Licence

Not currently licensed for reuse.
