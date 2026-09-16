# Swurl Kurl Studios — SMP Landing Page

Staging build of "The Comeback" SMP consultation landing page, built from the client's brand
design guide (v1.0) and the initial mockup/sample HTML.

## Status: staging — not launch-ready

The following still need real client assets/approvals before this goes live to paid traffic:

- **Photography** — Terrence's portrait and the video thumbnail (`assets/terrence-portrait.jpg`,
  `assets/terrence-video-thumbnail.jpg`) are still placeholders. `assets/terrence-hero.jpg` is now
  his real photo (see "Resolved since v1" below for how it's cropped).
- **Before/after results** — `assets/result-*-before.jpg` / `result-*-after.jpg` are placeholders.
  Replace with real client photos once consent and final claims are verified (per brand guide §3, §11).
- **Video** — the "But Will It Look Natural?" section has a play-button placeholder with no
  actual video wired up yet.
- **Consultation form** — has no CRM/lead endpoint connected (`<form action="">`). Submissions
  currently just show an inline "still in staging" notice and log to the browser console instead
  of being lost silently. Wire it to HubSpot, HighLevel, a Zapier/Make webhook, Formspree, or a
  custom backend before launch.
- **Consent/legal copy** — the consent line under the form is a placeholder; replace with the
  client's approved privacy/SMS/email consent language.

## Resolved since v1

- **FAQ answers** — all six entries now have real, client-provided answers (natural-looking
  results, typically two sessions, no pain with numbing options available, permanent results,
  hairline chosen through consultation with an emphasis on age-appropriate looks for clients
  50+, and starting the conversation as soon as thinning begins). Wording can still be refined
  with the client, but the placeholder copy is gone.
- **Logo** — using the client's real official seal (`assets/swurl-kurl-studios-official-logo.png`),
  used as supplied per the brand guide's "locked, use official asset only" rule.
- **Gold** — `--gold: #e8b351` is sampled directly from the official logo file (brand guide §6).
  A second token, `--gold-deep: #a6730f`, is the same hue deepened for gold text that sits on
  light backgrounds (hero and "look natural?" headlines) — the true bright gold reads clearly on
  dark backgrounds and as fills/borders, but is too light for body-size text on white/warm-white.
- **Typography** — whole site now set in Inter instead of default Arial/Helvetica; headlines at
  weight 800 (vs. browser-default bold) and labels/nav/buttons dialed back from 800–900 to
  400–600, for a slimmer, cleaner look closer to the approved mockup, per the brand guide's
  "cleaner premium editorial system" direction (§7).
- **WhatsApp as primary contact channel** — every CTA on the page ("Talk To Terrence Now") now
  opens a WhatsApp chat to +1 (586) 553-5504 with a prefilled greeting, instead of scrolling to
  the form. The consultation form is kept as a secondary "prefer to write it out" option lower
  on the same section. Update the phone number in every `wa.me/158655...` link (7 places) if it
  ever changes.
- **Real hero photo** — swapped in `assets/terrence-hero.jpg` (real photo, off-center composition:
  subject on the right two-thirds, plain background on the left). Plain `background-position:
  center` cropped this badly (mostly blank wall, hairline cut off), so `.hero-image` now uses
  `80% 0%` on desktop and `70% 0%` on the stacked mobile layout to keep his face and hairline in
  frame. **If a new hero photo is dropped in with a different composition, this position may need
  retuning** — tell Claude "the hero photo is cropped wrong" and it'll adjust it, or manually try
  values between `center` (dead center) and `100% 0%` (full right, full top) in that CSS rule
  until the crop looks right at both desktop and mobile widths.

## Structure

- `index.html` — the main landing page (inline CSS/JS, no build step)
- `admin.html` — passcode-protected analytics dashboard (site visits + WhatsApp click-throughs)
- `assets/` — images referenced by the pages

## Scheduler

The consultation section has a "Have A Date In Mind? Request It Directly." card with a date
picker and a Morning/Afternoon/Evening time select. Clicking **Send Request To Terrence**
builds a WhatsApp message that includes whatever date/time was chosen (or a generic "I'd like
to find a time that works" line if left blank) and opens it at the same WhatsApp number used
everywhere else on the site — `wa.me/15865535504`. There is no email step; per the client's
explicit direction this is WhatsApp-only, same as every other CTA on the page.

To change the WhatsApp number, update it in this scheduler's JS block near the bottom of
`index.html` **and** in the 8 `wa.me/158655...` button links (see "WhatsApp as primary
contact channel" above).

## Analytics & admin dashboard

Site visits and WhatsApp click-throughs are logged to a Supabase table (`smp_analytics_events`)
in the agency's shared Supabase project, and `admin.html` shows the aggregated numbers.

**How it works:**

- `index.html` posts one `page_view` event on every page load, and one `whatsapp_click` event
  (tagged with a `source`, e.g. `hero`, `nav`, `consultation`, `scheduler`) whenever a visitor
  clicks any of the 8 "Talk To Terrence Now" / WhatsApp buttons or submits the scheduler. This
  uses a public "publishable" Supabase key that can only *insert* rows — it has no permission
  to read data back, so it's safe to leave in the page source.
- `admin.html` is gated by a passcode prompt. On success, it calls a Supabase Edge Function
  (`smp-admin-stats`) that checks the passcode server-side, then uses a private service-role
  key (never exposed to the browser) to aggregate the raw events into totals, a last-24-hours
  snapshot, a breakdown by button/source, and a 30-day daily trend.
- The passcode is cached in the browser tab's `sessionStorage` only (cleared when the tab is
  closed), so refreshing the dashboard doesn't require re-entering it, but it's never stored
  in a cookie or `localStorage`.

**Current admin passcode:** `TalkToTerrence2026` — change this in the Supabase Edge Function
source (`smp-admin-stats`, the `ADMIN_PASSCODE` constant) if it needs to be rotated; it is not
stored anywhere in this repo.

**Admin dashboard URL (once deployed):** `https://swurl-kurl.onrender.com/admin.html`

## Deploy

Static site, no build step. Deployed on Render as a static site pointed at this repo's `main`
branch, publish path `.` — matching the agency's usual pattern for other client sites.
