# App Store listing — WhoWorks

Paste-ready copy for App Store Connect. Character limits noted; all within.

## Identity

| Field | Value |
|---|---|
| Name (30) | `WhoWorks` |
| Subtitle (30) | `Contacts, with companies` |
| Bundle ID | `com.whoworks.ios` |
| SKU | `whoworks-ios-001` |
| Primary category | Productivity |
| Secondary category | Utilities |
| Age rating | 4+ |
| Price | Free |

## Promotional text (170)

Pinch to zoom your contact list. See who someone works for without opening
their card, and group everyone by company.

## Description

The built-in Contacts app gives you one line per person: their name. If you deal with
people through their work, that's the wrong line — you end up scrolling a
thousand names looking for the one who does your plumbing.

WhoWorks adds a zoom gesture to your contact list. Pinch out and each row shows
more.

• Names — the standard list
• Names and companies — the company in smaller type under each name
• With email — add the email address underneath
• By company — the list regroups under company headings instead of letters

Contacts missing a field simply don't show that line. Nothing is padded out
with blanks.

Most people never fill in the Company field, so WhoWorks works it out from a work
email address when one is there — someone@acme-tools.com becomes Acme Tools. Inferred
companies are shown in lighter type so you can always tell a guess from
something you typed. Personal addresses like gmail and icloud are ignored.

WhoWorks reads the same address book as Contacts and the Phone app. There's no
import, no separate copy, and no syncing — edit a contact anywhere and it's
current here. Tap anyone to open the standard iOS contact card with all the
usual call, message and FaceTime options.

Also included:
• Search by company or job title, not just name
• Swipe a row to call or message, or to add a favourite
• Favourites pinned to the top of the list
• Your contacts in Spotlight, searchable by company from the home screen

WhoWorks works entirely on your device. It makes no network requests of any kind,
has no account, and no analytics. Your address book never leaves your iPhone.

## Keywords (100, comma separated, no spaces)

contacts,company,address,book,zoom,directory,rolodex,business,card,phone,
organize,search,work,colleagues

## Support / marketing URL

Needed before submission. A single GitHub Pages or similar page is enough.

## App Privacy answers

**Data collection: None.** Answer "No" to "Do you or your third-party partners
collect data from this app?"

Justification if asked: the app has no networking code, no SDKs, and no
analytics. Contacts are read from the local store via the Contacts framework
and never transmitted. Favourites and zoom level are stored in UserDefaults on
device. Spotlight indexing is local to iOS.

## Review notes

Paste into "Notes" on the submission — this pre-empts a Guideline 4.2 rejection.

> WhoWorks is a contacts browser built around a zoom gesture. The core feature is
> not available in the built-in Contacts app: pinching the list changes how
> much detail each row shows, and at the deepest level the list regroups under
> company headings rather than alphabetically.
>
> This exists because Apple's Contacts shows only a person's name in the list.
> The company field is visible only if a contact has no name at all. Users who
> deal with people through their employer commonly work around this by typing
> the company into the last-name field, which corrupts sorting and sharing.
> WhoWorks makes the company visible without that workaround.
>
> To reproduce: open the app, grant contacts access, then pinch outward on the
> list with two fingers. The row detail changes through four levels. The same
> control is in the "AA" menu in the navigation bar for accessibility.
>
> The app is entirely offline. It makes no network requests and collects no
> data. Tapping a contact presents the system CNContactViewController.

## Screenshot order

From `AppStore/screenshots-6.9/`. Lead with the differentiator, not a plain
list — a reviewer skimming should see the feature in the first frame.

1. `03-level2.png` — name, company and email together
2. `04-level3.png` — grouped by company
3. `02-level1.png` — name and company
4. `01-level0.png` — plain names, for contrast

Suggested caption overlays (optional, added in a design tool):
1. "Pinch to see more"
2. "Group by company"
3. "The company, right under the name"
4. "Or keep it simple"

## Pre-submission checklist

- [x] Privacy manifest (`PrivacyInfo.xcprivacy`) declaring UserDefaults `CA92.1`
- [x] `ITSAppUsesNonExemptEncryption = NO`
- [x] App icon, 1024px, no alpha
- [x] Screenshots at 6.9" (1320×2868)
- [ ] Reserve the name in App Store Connect — confirms availability
- [ ] Privacy policy URL live (draft in `AppStore/privacy-policy.md`)
- [ ] Support URL live
- [ ] Bump `CURRENT_PROJECT_VERSION` on every upload
- [ ] Archive with the Release configuration
- [ ] TestFlight internal test before submitting
