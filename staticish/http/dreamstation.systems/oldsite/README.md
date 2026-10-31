# robin's page

A small static personal site. No build step — just open `index.html` (or
serve the folder) in a browser.

## Pages

| File          | What it is                          |
|---------------|-------------------------------------|
| `index.html`  | home                                |
| `blog.html`   | blog index                          |
| `gzipt.html`  | a blog post                         |

## Theming

The site has a theme switcher pinned to the top-right of every page. Themes
are plain stylesheets that get swapped in at runtime; the chosen theme is
remembered in `localStorage`.

- `base.css` — always loaded. Only structural things that hold for *every*
  theme (e.g. where the switcher sits). No aesthetics.
- `themes/plain.css` — deliberately (almost) empty: browser defaults.
- `themes/gtk2.css` — makes the page look like a GTK2 app. **Default.**
- `themes/motif.css` — makes the page look like an OSF/Motif (Xm) X11 app:
  battleship-grey face, chunky 2px highlight/shadow bevels, square corners,
  etched separators, an XmOptionMenu switcher.
- `themes/skeuslop.css` — Windows Vista / Aero (frosted-glass header, glossy
  buttons, blue Segoe UI headings).
- `theme.js` — the switcher + persistence.

### Adding a theme

1. Create `themes/<id>.css`.
2. Add one line to the `THEMES` list at the top of `theme.js`:

   ```js
   { id: "<id>", label: "<Name shown in the dropdown>" }
   ```

That's all. The switcher, persistence, and no-flash loading pick it up.

### Changing the default

Edit `DEFAULT` in `theme.js`, and update the `href` of the
`<link id="theme-css">` in each page's `<head>` to match (that hard-coded
default is what shows before JavaScript runs / if JS is off).
