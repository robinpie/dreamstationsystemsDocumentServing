/* theme.js — the whole theme switcher.
 *
 * To add a theme:
 *   1. Drop a stylesheet at themes/<id>.css
 *   2. Add one line to the THEMES list below.
 * That's it — the switcher and persistence pick it up automatically.
 *
 * This script is loaded synchronously in <head>, *after* the
 * <link id="theme-css"> element, so it can swap to the saved theme
 * before the page paints (avoiding a flash of the default theme).
 */
(function () {
  "use strict";

  var THEMES = [
    { id: "gtk2", label: "GTK2" },
    { id: "motif", label: "Motif" },
    { id: "skeuslop", label: "skeuslop" },
    { id: "plain", label: "Plain" }
  ];
  var DEFAULT = "gtk2";
  var STORAGE_KEY = "theme";

  function saved() {
    try {
      return localStorage.getItem(STORAGE_KEY) || DEFAULT;
    } catch (e) {
      return DEFAULT; // localStorage can be unavailable (e.g. file://, private mode)
    }
  }

  function apply(id) {
    var link = document.getElementById("theme-css");
    if (link) {
      link.href = "themes/" + id + ".css";
    }
  }

  // Run immediately (we're in <head>) so the right theme loads first.
  apply(saved());

  function build() {
    var mount = document.getElementById("theme-switcher");
    if (!mount || mount.dataset.ready) return;
    mount.dataset.ready = "1";

    var select = document.createElement("select");
    select.id = "theme-select";
    select.setAttribute("aria-label", "Theme");

    THEMES.forEach(function (t) {
      var opt = document.createElement("option");
      opt.value = t.id;
      opt.textContent = t.label;
      select.appendChild(opt);
    });
    select.value = saved();

    select.addEventListener("change", function () {
      try {
        localStorage.setItem(STORAGE_KEY, select.value);
      } catch (e) {
        /* ignore — theme just won't persist */
      }
      apply(select.value);
    });

    mount.appendChild(select);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", build);
  } else {
    build();
  }
})();
