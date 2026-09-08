# robin's page

A small static personal site. No build step.

Most pages open fine straight from disk. The **themed** pages (see below) are
the exception: they pick their stylesheet server-side via nginx SSI, so over
`file://` the stylesheet link resolves to `themes/.css` and the page renders
unstyled. Serve them through nginx to see them properly — the config lives in
`nginx/snippets/theme.conf` at the repo root.

## Pages

| File          | What it is                          |
|---------------|-------------------------------------|
| `index.html`  | home                                |
| `blog.html`   | blog index                          |
| `gzipt.html`  | a blog post                         |

## Theming

The themed pages carry a switcher pinned to the top-right. Themes are plain
stylesheets; **nginx** picks which one the page links to and remembers the
choice in a cookie. There is no JavaScript involved — the switcher is a GET
form that submits to `?theme=<id>`, and the correct stylesheet is in the first
byte of the response, so there is no flash of the wrong theme to work around.

Themed pages (the list is also spelled out in `nginx/snippets/theme.conf`, and
both have to agree): `index`, `blog`, `hypnospace`, `lanfalsehoods`, `ntppool`,
`ntppost`, `ntpuserinfo`, `slowqotd`, `gzipt`. The other pages under `personal/` are one-off things with
their own styling and are not themed.

- `base.css` — always loaded. Only structural things that hold for *every*
  theme (e.g. where the switcher sits). No aesthetics.
- `themes/plain.css` — deliberately (almost) empty: browser defaults.
- `themes/gtk2.css` — makes the page look like a GTK2 app.
- `themes/motif.css` — makes the page look like an OSF/Motif (Xm) X11 app:
  battleship-grey face, chunky 2px highlight/shadow bevels, square corners,
  etched separators, an XmOptionMenu switcher.
- `themes/skeuslop.css` — Windows Vista / Aero (frosted-glass header, glossy
  buttons, blue Segoe UI headings).
- `themes/ubuntu804.css` — an Ubuntu 8.04 "Hardy Heron" desktop running
  Firefox 3, drawn around the page: GNOME panel with a live clock, metacity
  window frame, a menu bar whose menus really open, location bar, status bar,
  and the badge shelf on the exposed wallpaper. **Default.** The only theme
  that is more than a stylesheet — see **A theme that needs markup**, below.

Each theme styles both `#theme-switcher select` and `#theme-switcher button`
as a matching widget pair of its era. `plain.css` styles neither on purpose —
it gets the browser's native controls, which is the whole idea.

### A theme that needs markup

`ubuntu804` draws a whole desktop around the page, and none of that markup is
in the pages. It lives in three fragments under `chrome/`, which each themed
page pulls in with SSI, guarded on the theme:

    if $theme is ubuntu804 -> include chrome/top.html     (before <header>)
                              include chrome/mid.html     (after  </header>)
                              include chrome/bottom.html  (before </body>)

Under the other four themes nginx expands those to nothing, so they cost 0
bytes. The fragments are deliberately unbalanced HTML — `top` opens what
`bottom` closes — and are served from an `internal` location, so fetching one
directly gives a 404.

Three of the pages' own elements are re-cast rather than restyled:
`header.site-header` becomes the bookmarks toolbar, `main` becomes the
document in the browser viewport, and `footer ul.badges` becomes the badge
shelf on the wallpaper. That is why this theme needed almost no new markup —
only `id="content"` on `<main>`, for the skip link.

`ubuntu804theme.txt` in the repo root is the design document, and it lists the
traps. Two are worth repeating here because they are silent: **nginx variables
do not survive an SSI include** (they re-evaluate against the subrequest, so
the page hands the title and path in with `set`), and **SSI does not
understand HTML comment nesting**, so an SSI directive written inside a
comment as documentation gets executed.

### Adding a theme

1. Create `themes/<id>.css` (including switcher chrome, or it inherits
   nothing and shows native controls). A theme that needs markup of its own
   adds fragments under `chrome/` and include lines on each page — see above.
2. Add `<id>` to **both** maps at the top of
   `nginx/sites-available/dreamstation.systems`. Anything not in the maps is
   rejected and falls back to the default.
3. Add an `<option>` to the switcher `<form>` in each themed page.

Step 2 is what makes it live; a stylesheet that exists but is not in the maps
is unreachable.

### Changing the default

Change the `default` in the `$theme_cookie` map — that value is what a visitor
with no cookie and no `?theme=` gets. Nothing is hard-coded in the pages any
more, so that is the only place it lives.

### Precedence

`?theme=<id>` beats the cookie, which beats the default. A visitor with
cookies disabled still gets the theme they picked on that page; it just does
not follow them to the next one, and the `?theme=` URL can be bookmarked to
pin a theme without cookies at all.
