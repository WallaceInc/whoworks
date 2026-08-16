# Review demo video — WhoWorks

Apple rejected 1.0 asking to see how the app works. That is almost always
Guideline 4.2 (Minimum Functionality): the reviewer opened the app, saw a list
of names, and never discovered that pinching changes it. **The video has one
job: show the pinch working, in the first five seconds.**

Record on your iPhone, not the simulator — a real finger doing a real pinch is
exactly what they're asking to see.

## How to record

1. Settings › Control Centre › add **Screen Recording** if it isn't there
2. Open **WhoWorks**, scroll to somewhere with recognisable contacts
3. Swipe down for Control Centre, tap **Screen Recording**, wait for the
   countdown, then return to WhoWorks
4. Perform the shots below
5. Stop via the red pill in the status bar. It saves to Photos.

Keep it under 45 seconds. No narration needed — nobody watches with sound on.

## Shot list

| Time | What to do | What it proves |
|------|-----------|----------------|
| 0:00–0:03 | Sit on the plain list, names only. Don't touch anything. | The starting state — what the reviewer saw |
| 0:03–0:08 | **Pinch out slowly.** Let the badge read *Names & Companies*. Pause. | The core feature. Do it slowly; a fast pinch is unreadable on video |
| 0:08–0:13 | **Pinch out again** → *With Email*. Pause so the rows are legible. | Progressive detail |
| 0:13–0:19 | **Pinch out again** → *Grouped by Company*. Scroll a little so several company headings pass. | The list restructures — clearly not a stock contacts list |
| 0:19–0:24 | **Pinch in** twice, back to names. | It's a two-way gesture, not a one-off |
| 0:24–0:30 | Tap the **AA** button, pick a level from the menu. | The gesture isn't the only way in — matters for accessibility |
| 0:30–0:36 | Swipe a row right → tap the star. Show it pinned under **Favourites**. | Secondary feature |
| 0:36–0:42 | Swipe a row left → show Call and Message. Tap a contact to open the card, then close. | Rounds it out |

If you're short on time, **0:00–0:19 alone is enough.** Everything after is
supporting material.

## Where it goes

Two places, depending on how they asked:

- **Resolution Center** — reply to the rejection and attach the video there.
  This is the right place if they messaged you.
- **App Review Information** — on the version page there's an **App Review
  Attachment** field. Attach it there too so it travels with the submission.

## Text to send with it

> WhoWorks is a contacts browser built around a pinch gesture. The attached
> video shows it in use.
>
> Pinching the list changes how much detail each row shows, across four levels:
> names only; names with the company beneath; adding the email address; and
> finally the list regrouped under company headings instead of alphabetically.
> The same four levels are available from the "AA" button in the navigation bar
> for anyone who does not use the gesture.
>
> This is not available in the built-in Contacts app, which shows only a
> person's name in the list and reveals the company field only when a contact
> has no name at all. People who deal with contacts through their employer
> commonly work around this by typing the company into the last-name field,
> which corrupts sorting and sharing. WhoWorks makes the company visible
> without that workaround, and can infer it from a work email domain when the
> field is empty.
>
> The app is entirely offline: no network requests, no account, no analytics.

## Before resubmitting

- Attach build **1.0 (3)** — it has the company-variant grouping, contact
  creation and deletion that earlier builds lacked
- Keep the review notes in `app-store-connect-fields.txt` section 8; the video
  supplements them rather than replacing them
- Lead the screenshots with `03-level2.png`, not the plain list — the reviewer
  should see the feature before opening the app
