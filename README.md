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
- **Consent/legal copy** — the consent line under the form is a placeholder; replace with the
  client's approved privacy/SMS/email consent language.

## Resolved since v1

- **Consultation form** — now saves to the store database and buzzes the owner's phone (see
  "Store app" below). No third-party CRM is connected; add a webhook later if one is wanted.
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
- **Phone-alert requests (replaced WhatsApp)** — every "Talk To Terrence Now" button opens a short
  request form (name, mobile, best time, referring barbershop, note). Submitting it saves the
  request to the store database and instantly buzzes the owner's phone through the store app. The
  site no longer links to WhatsApp anywhere. (The store app still has an optional WhatsApp reply
  button next to Text and Call for the owner's convenience.)
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
- `admin.html` — passcode-protected analytics dashboard (site visits + contact-button clicks)
- `store.html` — the owner's store app (login, appointments, purchases, services). Installable on a phone
- `sw.js` + `manifest.webmanifest` — make the store app installable and receive phone push alerts
- `img/` — app icons (generated from the official logo)
- `supabase/` — database migrations and the `notify-request` push function (already applied to the live
  project; kept here for reference)
- `assets/` — images referenced by the pages

## Scheduler, services and bookings

Every request is saved to the store database so it appears in the store app and buzzes the
owner's phone. There is no WhatsApp hand-off on the site.

- **Scheduler card** (consultation section): name, mobile, optional date and time. Saves a
  consultation request (with the optional referring barbershop).
- **Services section** (`#services`): loaded live from the `offers` table, so price edits made in
  the store app show up on the site with no redeploy. A snapshot of the same list is baked into
  `index.html` (`FALLBACK_SERVICES`) and is used only if the database can't be reached.
  - *Bookable* services (microblading, haircut, massage, couples massage) take a date, time and
    (where it applies) a duration, and show the price. Prices are enforced on the server.
  - *Consultation-only* services (facials, TRT, hormone therapy, weight loss, IV therapy) take a
    preferred date/time and no price.
  - *Package* (The Comeback, $2,000 limited-time, regularly $2,500) is a reservation: it lands under **Purchases**.
- **No online payment.** Payment is arranged by the owner (in person, Zelle, etc.). Adding card
  payments (Stripe) is a possible later phase.
- **Barbershop referral program.** The scheduler, consultation form, "Talk To Terrence" form and
  the Comeback reservation ask "Which barbershop referred you?" (optional). It is stored in
  `referred_by`, shown on each card in the store app, included in the phone alert, and totaled per
  barbershop under the store app's **Referrals** tab.
- **Learn how to SMP.** The "Want To Learn How To SMP?" section (and "Learn SMP" in the nav) opens
  a training inquiry form. It lands in the store app as a "Training" request (filter chip on the
  Appointments tab) and sends its own phone alert.
- **Pricing.** The Comeback is $2,000 (limited-time) against a regular $2,500. The price shown in
  the page copy is typed in `index.html`; the reservation price comes from the `offers` table in
  the store database (editable in the store app's Services tab), so change both together.

## Store app (owner login + phone alerts)

`store.html` is the owner's app, built the same way as the Cargo+420 dashboard. Backend: a dedicated
Supabase project named `SwurlKurl` (separate from the agency's shared project, so the owner's login
never mixes with other clients' users).

- **Appointments** — consultation requests and service bookings. Confirm, complete, no-show or
  cancel; private notes; one-tap Text, Call and WhatsApp reply. Training inquiries have a filter chip,
  and the **Referrals** tab totals requests and paid purchases per referring barbershop.
- **Purchases** — package reservations: new → confirmed → paid → completed, with totals.
- **Services** — edit names, descriptions, prices, duration options, visibility, or add services.
- **Phone alerts** — web push. Install the app to the phone's home screen (iPhone: Safari → Share →
  Add to Home Screen; Android: browser menu → Install app), open it, tap **Turn on phone alerts**.
  Every new request then buzzes the phone even when the app is closed.

How a request flows: the visitor submits → a database function validates it (and fixes the price)
→ a database trigger calls the `notify-request` function → web push to every registered device →
the app updates live.

**Owner login setup:** the first time, open `/store.html`, choose *First-time setup*, enter an email,
a password and a one-time setup code. Setup codes are single-use and are kept in the database
(`claim_codes` table), never in this repo. If email confirmation is on, confirm the email, sign in,
and enter the setup code once.

**One manual Supabase setting:** in the Supabase dashboard → Authentication → URL Configuration, set
*Site URL* to `https://swurl-kurl.onrender.com` and add it under *Redirect URLs*, so confirmation
and password-reset emails send people to the right place.

**Secrets:** the push private key and the function's hook secret live only in the database
(`private_config`, readable by the service role only). The keys in `store.html` / `index.html` are
publishable and protected by row-level security.

## Analytics & admin dashboard

Site visits and contact-button clicks are logged to a Supabase table (`smp_analytics_events`)
in the agency's shared Supabase project, and `admin.html` shows the aggregated numbers.

**How it works:**

- `index.html` posts one `page_view` event on every page load, and one `whatsapp_click` event
  (tagged with a `source`, e.g. `hero`, `nav`, `consultation`, `scheduler`) whenever a visitor
  clicks any "Talk To Terrence Now" / "Learn how to SMP" button or submits the scheduler. (The event keeps its original `whatsapp_click` name so history stays intact; `admin.html` labels it "Contact Button Clicks".) This
  uses a public "publishable" Supabase key that can only *insert* rows — it has no permission
  to read data back, so it's safe to leave in the page source.
- `admin.html` is gated by a passcode prompt. On success, it calls a Supabase Edge Function
  (`smp-admin-stats`) that checks the passcode server-side, then uses a private service-role
  key (never exposed to the browser) to aggregate the raw events into totals, a last-24-hours
  snapshot, a breakdown by button/source, and a 30-day daily trend.
- The passcode is cached in the browser tab's `sessionStorage` only (cleared when the tab is
  closed), so refreshing the dashboard doesn't require re-entering it, but it's never stored
  in a cookie or `localStorage`.

**Admin passcode:** set in the Supabase Edge Function source (`smp-admin-stats`, the
`ADMIN_PASSCODE` constant) and shared with the owner directly. It is deliberately not written in
this repo. To rotate it, redeploy that function with a new value.

**Admin dashboard URL (once deployed):** `https://swurl-kurl.onrender.com/admin.html`

## Deploy

Static site, no build step. Deployed on Render as a static site pointed at this repo's `main`
branch, publish path `.` — matching the agency's usual pattern for other client sites.
