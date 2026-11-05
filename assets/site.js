/*
  Swurl Kurl Studios: site settings, optional ad tracking, trust details, reviews.

  EDIT ONLY THE SETTINGS BLOCK BELOW. Anything left empty simply does not appear
  and nothing is loaded. Nothing here is ever sent to Meta or Google except the
  fact that a page was viewed and that a request form was submitted (no names,
  phone numbers, emails or form answers).
*/
(function () {
  "use strict";

  /* ---------------- SETTINGS ---------------- */
  var SITE = {
    // Meta Pixel ID: digits only, from Meta Events Manager. Empty = Meta tracking off.
    metaPixelId: "280932646845010",
    // Google tag ID, like G-XXXXXXXXXX (or AW-XXXXXXXXX). Empty = Google tracking off.
    googleTagId: "G-208RP2P0FK",

    // Trust details shown in the footer. Fill in only what is real and public.
    phone: "313-399-2532",   // becomes a tap-to-call link
    area: "277 Jos Campau, Detroit, MI 48207",
    hours: "",          // e.g. "By appointment, Tue-Sat"

    // Reviews. Add ONLY real quotes you have permission to publish. Empty = section stays hidden.
    // Example: { quote: "…", name: "First name + initial", detail: "After session 2" }
    reviews: []
  };
  /* ------------- END SETTINGS --------------- */

  var w = window, d = document;

  function onlyDigits(s) { return String(s || "").replace(/\D/g, ""); }
  function el(tag, cls, text) {
    var e = d.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }

  /* ---- Meta Pixel (standard base code, only when an ID is set) ---- */
  var pixelId = /^\d{8,20}$/.test(SITE.metaPixelId) ? SITE.metaPixelId : "";
  if (pixelId) {
    (function (f, b, e, v, n, t, s) {
      if (f.fbq) return;
      n = f.fbq = function () { n.callMethod ? n.callMethod.apply(n, arguments) : n.queue.push(arguments); };
      if (!f._fbq) f._fbq = n;
      n.push = n; n.loaded = true; n.version = "2.0"; n.queue = [];
      t = b.createElement(e); t.async = true; t.src = v;
      s = b.getElementsByTagName(e)[0]; s.parentNode.insertBefore(t, s);
    })(w, d, "script", "https://connect.facebook.net/en_US/fbevents.js");
    w.fbq("init", pixelId);
    w.fbq("track", "PageView");
  }

  /* ---- Google tag (only when an ID is set) ---- */
  var gId = /^(G|AW|GT)-[A-Z0-9]{4,20}$/.test(SITE.googleTagId) ? SITE.googleTagId : "";
  if (gId) {
    var gs = d.createElement("script");
    gs.async = true;
    gs.src = "https://www.googletagmanager.com/gtag/js?id=" + encodeURIComponent(gId);
    d.head.appendChild(gs);
    w.dataLayer = w.dataLayer || [];
    w.gtag = function () { w.dataLayer.push(arguments); };
    w.gtag("js", new Date());
    w.gtag("config", gId);
  }

  /* ---- conversion events: called after a request is saved ---- */
  function track(kind) {
    try {
      var training = kind === "training";
      if (w.fbq && pixelId) {
        if (training) w.fbq("trackCustom", "TrainingInquiry");
        else w.fbq("track", "Lead");
      }
      if (w.gtag && gId) {
        w.gtag("event", training ? "training_inquiry" : "generate_lead", { lead_type: kind });
      }
    } catch (e) { /* tracking must never break the form */ }
  }

  /* ---- trust details + reviews ---- */
  function render() {
    var box = d.getElementById("siteContact");
    if (box) {
      var bits = [];
      var digits = onlyDigits(SITE.phone);
      if (digits.length >= 10) {
        var a = el("a", null, SITE.phone);
        a.href = "tel:+1" + digits.slice(-10);
        bits.push(a);
      }
      if (SITE.area) bits.push(el("span", null, SITE.area));
      if (SITE.hours) bits.push(el("span", null, SITE.hours));
      if (bits.length) {
        box.textContent = "";
        bits.forEach(function (b, i) {
          if (i) box.appendChild(d.createTextNode(" · "));
          box.appendChild(b);
        });
        box.hidden = false;
      }
    }

    var sec = d.getElementById("reviews");
    var list = d.getElementById("reviewsList");
    if (sec && list && SITE.reviews && SITE.reviews.length) {
      SITE.reviews.slice(0, 6).forEach(function (r) {
        if (!r || !r.quote || !r.name) return;
        var card = el("figure", "review-card");
        card.appendChild(el("blockquote", null, "“" + r.quote + "”"));
        var cap = el("figcaption", null, r.name + (r.detail ? " · " + r.detail : ""));
        card.appendChild(cap);
        list.appendChild(card);
      });
      if (list.children.length) sec.hidden = false;
    }
  }

  w.SK = { track: track, site: SITE, render: render };
  if (d.readyState === "loading") d.addEventListener("DOMContentLoaded", render);
  else render();
})();
