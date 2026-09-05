# Swurl Kurl Studios — SMP Landing Page

Staging build of "The Comeback" SMP consultation landing page, built from the client's brand
design guide (v1.0) and the initial mockup/sample HTML.

## Status: staging — not launch-ready

The following still need real client assets/approvals before this goes live to paid traffic:

- **Photography** — hero image, Terrence's portrait, and the video thumbnail
  (`assets/terrence-*.jpg`) are placeholders. Replace with approved photography.
- **Before/after results** — `assets/result-*-before.jpg` / `result-*-after.jpg` are placeholders.
  Replace with real client photos once consent and final claims are verified (per brand guide §3, §11).
- **Video** — the "But Will It Look Natural?" section has a play-button placeholder with no
  actual video wired up yet.
- **FAQ answers** — all six FAQ entries are still "Add Terrence-approved answer here."
- **Consultation form** — has no CRM/lead endpoint connected (`<form action="">`). Submissions
  currently just show an inline "still in staging" notice and log to the browser console instead
  of being lost silently. Wire it to HubSpot, HighLevel, a Zapier/Make webhook, Formspree, or a
  custom backend before launch.
- **Consent/legal copy** — the consent line under the form is a placeholder; replace with the
  client's approved privacy/SMS/email consent language.

## Resolved since v1

- **Logo** — using the client's real official seal (`assets/swurl-kurl-studios-official-logo.png`),
  used as supplied per the brand guide's "locked, use official asset only" rule.
- **Gold** — `--gold: #e8b351` is sampled directly from the official logo file (brand guide §6).
  A second token, `--gold-deep: #a6730f`, is the same hue deepened for gold text that sits on
  light backgrounds (hero and "look natural?" headlines) — the true bright gold reads clearly on
  dark backgrounds and as fills/borders, but is too light for body-size text on white/warm-white.
- **Typography** — headlines now set in Playfair Display (an editorial serif, echoing the logo's
  script/serif treatment) instead of bold uppercase Arial; body and labels set in Inter at lighter
  weights (400–600 instead of 800–900) for a slimmer, more premium feel, per the brand guide's
  "cleaner premium editorial system" direction (§7).

## Structure

- `index.html` — the whole page (inline CSS/JS, no build step)
- `assets/` — images referenced by the page

## Deploy

Static site, no build step. Deployed on Render as a static site pointed at this repo's `main`
branch, publish path `.` — matching the agency's usual pattern for other client sites.
