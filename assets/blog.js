/* The Heart of the Matter: menu, subscribe forms and share button (shared by the blog pages). */
(function () {
  /* ---------- hamburger menu ---------- */
  var toggle = document.getElementById("navToggle"), menu = document.getElementById("mobileMenu");
  if (toggle && menu) {
    var root = document.documentElement, isOpen = false;
    var setMenu = function (open, restoreFocus) {
      isOpen = open;
      menu.classList.toggle("open", open); root.classList.toggle("menu-open", open);
      toggle.setAttribute("aria-expanded", open ? "true" : "false");
      toggle.setAttribute("aria-label", open ? "Close menu" : "Open menu");
      if (open) { var f = menu.querySelector("a.ml"); if (f) setTimeout(function () { f.focus({ preventScroll: true }); }, 60); }
      else if (restoreFocus) toggle.focus({ preventScroll: true });
    };
    toggle.addEventListener("click", function () { setMenu(!isOpen, isOpen); });
    document.addEventListener("keydown", function (e) {
      if (!isOpen) return;
      if (e.key === "Escape") { setMenu(false, true); return; }
      if (e.key === "Tab") {
        var f = [toggle].concat([].slice.call(menu.querySelectorAll("a[href]")));
        var i = f.indexOf(document.activeElement);
        if (e.shiftKey && i <= 0) { e.preventDefault(); f[f.length - 1].focus(); }
        else if (!e.shiftKey && i === f.length - 1) { e.preventDefault(); f[0].focus(); }
      }
    });
  }

  /* ---------- subscribe forms ---------- */
  /* Saves to the same store database as the main site (public anon key only; the database function validates,
     de-duplicates and rate-limits). The owner sees the list in the store app under Subscribers. */
  var STORE_URL = "https://eyzhywxehxoqtrjzooab.supabase.co";
  var STORE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImV5emh5d3hlaHhvcXRyanpvb2FiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTExMjc1MTksImV4cCI6MjEwNjcwMzUxOX0.bhlbwLEPFIkfhnGbYY5y8jffRHDZz6DQpclWLFiGNoU";
  async function rpc(fn, args) {
    var res = await fetch(STORE_URL + "/rest/v1/rpc/" + fn, {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: STORE_KEY, Authorization: "Bearer " + STORE_KEY },
      body: JSON.stringify(args)
    });
    var body = null; try { body = await res.json(); } catch (e) {}
    if (!res.ok) throw new Error((body && body.message) || "Something went wrong. Please try again.");
    return body;
  }
  [].slice.call(document.querySelectorAll("form.subform")).forEach(function (form) {
    var box = form.closest(".sub-box") || form.parentNode;
    var msg = box.querySelector(".sub-msg");
    var btn = form.querySelector("button[type=submit]");
    form.addEventListener("submit", async function (e) {
      e.preventDefault();
      if (msg) { msg.textContent = ""; msg.className = "sub-msg"; }
      var email = form.elements.email.value.trim(), name = (form.elements.name && form.elements.name.value.trim()) || "";
      var trap = form.elements.website && form.elements.website.value;
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
        if (msg) { msg.textContent = "Please enter a valid email address."; msg.className = "sub-msg err"; }
        form.elements.email.focus(); return;
      }
      var label = btn.textContent; btn.disabled = true; btn.textContent = "Joining…";
      try {
        if (!trap) await rpc("subscribe_blog", { p_email: email, p_name: name || null, p_source: form.getAttribute("data-source") || "blog" });
        var done = box.querySelector(".sub-done");
        if (done) {
          var who = name ? name.split(/\s+/)[0] : "friend";
          done.querySelector("[data-who]").textContent = "You're in, " + who + ".";
          box.classList.add("is-done");
        } else if (msg) { msg.textContent = "You're in. Watch your inbox for the next story."; msg.className = "sub-msg ok"; form.reset(); }
      } catch (err) {
        if (msg) { msg.textContent = err.message; msg.className = "sub-msg err"; }
      } finally { btn.disabled = false; btn.textContent = label; }
    });
  });

  /* ---------- share ---------- */
  [].slice.call(document.querySelectorAll("[data-share]")).forEach(function (b) {
    b.addEventListener("click", async function () {
      var data = { title: document.title, url: location.href };
      try {
        if (navigator.share) { await navigator.share(data); return; }
        await navigator.clipboard.writeText(location.href);
        var t = b.textContent; b.textContent = "Link copied"; setTimeout(function () { b.textContent = t; }, 2200);
      } catch (e) {}
    });
  });
})();
