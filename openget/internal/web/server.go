// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 robinpie
//
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; version 2 of the License.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// Package web serves the HTTP frontend.
//
// Handlers are thin: each one parses parameters, asks internal/views for a render.Doc, and hands it to render.HTMLBody inside the page layout. The numbers, the caveats and the column choices all live in views, so the web site and the Gopher/Gemini/Spartan/finger frontends cannot disagree.
package web

import (
	"context"
	"embed"
	"errors"
	"fmt"
	"html/template"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"dreamstation.systems/openget/internal/config"
	"dreamstation.systems/openget/internal/ingest"
	"dreamstation.systems/openget/internal/render"
	"dreamstation.systems/openget/internal/store"
	"dreamstation.systems/openget/internal/views"
)

//go:embed static/*
var staticFS embed.FS

// Server is the HTTP handler.
type Server struct {
	db      *store.DB
	cfg     config.Config
	log     *slog.Logger
	ing     *ingest.Ingester
	views   *views.Builder
	version string
	mux     *http.ServeMux
	tmpl    *template.Template
	started time.Time
	mint    *mintLimiter
}

// New builds the server and registers every route.
func New(db *store.DB, cfg config.Config, log *slog.Logger, ing *ingest.Ingester, version string) *Server {
	s := &Server{
		db: db, cfg: cfg, log: log, ing: ing,
		views:   views.New(db, cfg),
		version: version,
		mux:     http.NewServeMux(),
		tmpl:    template.Must(template.New("layout").Parse(layoutHTML)),
		started: time.Now(),
		mint:    newMintLimiter(cfg.Limits.MintPerHour),
	}
	s.routes()
	return s
}

func (s *Server) routes() {
	m := s.mux
	m.HandleFunc("GET /{$}", s.page(s.home))
	m.HandleFunc("GET /items", s.page(s.items))
	m.HandleFunc("GET /item/{id}", s.page(s.item))
	m.HandleFunc("GET /search", s.page(s.search))
	m.HandleFunc("GET /flips/{slug}", s.page(s.finder))
	m.HandleFunc("GET /alch", s.page(s.alch))
	m.HandleFunc("GET /store-profit", s.page(s.storeProfit))
	m.HandleFunc("GET /ge-tax-calculator", s.page(s.taxCalc))
	m.HandleFunc("GET /calc", s.page(s.calcIndex))
	m.HandleFunc("GET /calc/{kind}", s.page(s.calcKind))
	m.HandleFunc("GET /calc/{kind}/{id}", s.page(s.calcRecipe))
	m.HandleFunc("GET /indices", s.page(s.indices))
	m.HandleFunc("GET /indices/{id}", s.page(s.indexPage))
	m.HandleFunc("GET /about", s.page(s.about))
	m.HandleFunc("GET /status", s.page(s.status))
	m.HandleFunc("POST /f2p", s.postF2P)
	m.HandleFunc("POST /theme", s.postTheme)

	m.HandleFunc("GET /chart/{id}", s.chartSVG)
	m.HandleFunc("GET /sitemap.xml", s.sitemap)
	m.HandleFunc("GET /static/", s.static)
	m.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		fmt.Fprintln(w, "ok")
	})

	s.apiRoutes(m)
	s.retroRoutes(m)
	s.personalRoutes(m)
}

func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	start := time.Now()
	// GNU Terry Pratchett. Set here rather than per-handler so it rides on every response the daemon makes — pages, the API, static assets and the 404 alike. A man is not dead while his name is still spoken.
	w.Header().Set("X-Clacks-Overhead", "GNU Terry Pratchett")
	sw := &statusWriter{ResponseWriter: w, code: 200}
	s.mux.ServeHTTP(sw, r)
	s.log.Debug("http", "method", r.Method, "path", r.URL.Path,
		"status", sw.code, "dur", time.Since(start).Round(time.Microsecond))
}

type statusWriter struct {
	http.ResponseWriter
	code int
}

func (w *statusWriter) WriteHeader(c int) { w.code = c; w.ResponseWriter.WriteHeader(c) }

// ---------------------------------------------------------------------------
// Page plumbing
// ---------------------------------------------------------------------------

// pageFunc builds a Doc and the HTML options for rendering it.
type pageFunc func(context.Context, *http.Request) (*render.Doc, render.HTMLOptions, error)

// page wraps a pageFunc into an http.HandlerFunc, mapping store.ErrNotFound to a 404 and anything else to a 500 with the detail logged rather than shown.
func (s *Server) page(fn pageFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		doc, opts, err := fn(r.Context(), r)
		switch {
		case errors.Is(err, store.ErrNotFound):
			s.errorPage(w, r, http.StatusNotFound, "Not found",
				"There is no page at "+r.URL.Path+".")
			return
		case err != nil:
			s.log.Error("page failed", "path", r.URL.Path, "err", err)
			s.errorPage(w, r, http.StatusInternalServerError, "Something broke",
				"That page could not be built. The error has been logged.")
			return
		}
		s.renderDoc(w, r, doc, opts, http.StatusOK)
	}
}

func (s *Server) renderDoc(w http.ResponseWriter, r *http.Request, doc *render.Doc, opts render.HTMLOptions, code int) {
	// The list pages (/items, /flips/*, and everything linked from Money makers except the /calc index itself and individual recipe pages) show a title/blurb pair that just repeats the nav tab and page <title>; move the blurb into the Notes section at the bottom instead of rendering it a second time up top.
	//
	// The alch page carries its spell and rune options in its Path's query string, so it is matched by prefix rather than equality — on an equality test, switching to low alchemy would silently bring the duplicate back.
	isOtherListPage := strings.HasPrefix(doc.Path, "/alch") ||
		doc.Path == "/store-profit" || doc.Path == "/ge-tax-calculator" ||
		doc.Path == "/indices" ||
		(strings.HasPrefix(doc.Path, "/calc/") && !strings.Contains(doc.Path[len("/calc/"):], "/"))
	isListPage := doc.Path == "/items" || strings.HasPrefix(doc.Path, "/flips/") || isOtherListPage
	noHeading := doc.Path == "/" || isListPage
	subtitle := doc.Subtitle
	// The tax calculator has no notes of its own, so relocating its blurb would conjure a whole Notes panel to hold a single stray line. Drop the blurb from the visible page instead; it still feeds the meta description, which is the point of keeping it on the Doc.
	if isListPage && subtitle != "" && doc.Path != "/ge-tax-calculator" {
		doc.Footnotes = append([]string{subtitle}, doc.Footnotes...)
	}
	body := render.HTMLBody(doc, opts)
	data := layoutData{
		Title:     doc.Title,
		PageTitle: pageTitle(doc.Title),
		Subtitle:  subtitle,
		Body:      template.HTML(body),
		Nav:       navItems(r.URL.Path),
		Query:     r.URL.Query().Get("q"),
		Version:   s.version,
		NoIndex:   doc.NoIndex,
		Credit:    views.Credit,
		NoHeading: noHeading,
		F2P:       f2pFrom(r),
		Theme:     themeFrom(r),
		Themes:    themes,
		Return:    r.URL.RequestURI(),
	}
	// Two fields rather than one string: a Windows status bar is segmented, and the relative age and the absolute clock time are answering two different questions anyway ("is this fresh?" and "fresh as of when?").
	if !doc.Updated.IsZero() {
		data.UpdatedAgo = render.Ago(doc.Updated)
		data.UpdatedAt = doc.Updated.UTC().Format("15:04:05") + " UTC"
		// Both fields are the same instant said two ways, wrapped in <time datetime> pointing at it — see openget.txt, ACCESSIBILITY, on why the timestamp is the part that stays true under shared cache.
		data.UpdatedISO = doc.Updated.UTC().Format(time.RFC3339)
	}
	if doc.NoIndex {
		w.Header().Set("X-Robots-Tag", "noindex, nofollow")
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	// Prices move on a five-minute cadence upstream; a minute of shared cache keeps a crawler or a burst of readers off the database without ever showing a price that is meaningfully stale.
	w.Header().Set("Cache-Control", "public, max-age=60")
	// Which is only safe to share because of this: the free-to-play toggle and the favourite button both read cookies, so without Vary an intermediary could hand one reader's filtered page to somebody who never set it.
	w.Header().Set("Vary", "Cookie")
	w.WriteHeader(code)
	if err := s.tmpl.Execute(w, data); err != nil {
		s.log.Error("template", "err", err)
	}
}

func (s *Server) errorPage(w http.ResponseWriter, r *http.Request, code int, title, msg string) {
	d := &render.Doc{Title: title}
	d.Add(render.Para{Text: msg})
	d.Add(render.Links{Title: "Try instead", Items: []render.Link{
		{Text: "Front page", Href: "/"},
		{Text: "All items", Href: "/items"},
		{Text: "Search", Href: "/search"},
	}})
	s.renderDoc(w, r, d, render.HTMLOptions{}, code)
}

type navEntry struct {
	Label, Href string
	Current     bool
}

func navItems(path string) []navEntry {
	entries := []navEntry{
		{Label: "Home", Href: "/"},
		{Label: "Items", Href: "/items"},
		{Label: "Margins", Href: "/flips/margin"},
		{Label: "ROI", Href: "/flips/roi"},
		{Label: "Potential", Href: "/flips/potential"},
		{Label: "Volume", Href: "/flips/volume"},
		{Label: "Alch", Href: "/alch"},
		{Label: "Money makers", Href: "/calc"},
		{Label: "Indices", Href: "/indices"},
		{Label: "GE tax", Href: "/ge-tax-calculator"},
		{Label: "Favourites", Href: "/favourites"},
		{Label: "Tracker", Href: "/tracker"},
		{Label: "Alerts", Href: "/alerts"},
		{Label: "About", Href: "/about"},
	}
	for i := range entries {
		h := entries[i].Href
		entries[i].Current = path == h || (h != "/" && strings.HasPrefix(path, h))
	}
	return entries
}

// pageTitle builds the <title> and og:title text.
//
// The front page's own title is already "OpenGET", so the usual "<page> — OpenGET" suffix turned it into "OpenGET — OpenGET" in the browser tab and in every link unfurl. Computed here rather than in the template because two places need it and they must not drift.
func pageTitle(docTitle string) string {
	const brand = "OpenGET"
	if docTitle == "" || docTitle == brand {
		return brand
	}
	return docTitle + " — " + brand
}

type layoutData struct {
	Title string
	// PageTitle is Title with the brand suffix, for <title> and og:title.
	PageTitle string
	Subtitle  string
	Body      template.HTML
	Nav       []navEntry
	// UpdatedAgo and UpdatedAt are the two status bar fields: "3m ago" and "14:22:01 UTC". UpdatedISO is the same instant in RFC 3339, for the datetime attribute both of them carry.
	UpdatedAgo string
	UpdatedAt  string
	UpdatedISO string
	Query      string
	Version    string
	NoIndex    bool
	Credit     string
	// NoHeading suppresses the VISIBLE in-page h1/subtitle, for the front page (the masthead already shows the brand and tagline) and the list pages (see renderDoc).
	//
	// The h1 itself still ships, hidden. Dropped outright, /items and every /calc/<kind> page would carry exactly one heading — the "Notes" panel at the bottom — so a reader navigating by headings gets the footnotes and no title at all.
	NoHeading bool
	// F2P is the state of the site-wide free-to-play checkbox in the masthead.
	F2P bool
	// Theme is the skin this reader has chosen, and Themes is every skin on offer, for the picker beside the checkbox.
	Theme  Theme
	Themes []Theme
	// Return is where those forms come back to, so ticking the checkbox on page 3 of the margin finder does not dump the reader on the front page.
	Return string
}

const layoutHTML = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="{{if .Theme.Dark}}dark{{else}}light{{end}}">
<meta name="theme-color" content="{{.Theme.ThemeColor}}">
<title>{{.PageTitle}}</title>
{{if .Subtitle}}<meta name="description" content="{{.Subtitle}}">{{end}}
{{if .NoIndex}}<meta name="robots" content="noindex, nofollow">{{end}}
<meta property="og:title" content="{{.PageTitle}}">
{{if .Subtitle}}<meta property="og:description" content="{{.Subtitle}}">{{end}}
<meta property="og:type" content="website">
<link rel="stylesheet" href="/static/openget-layout.css">
{{range .Theme.Sheets}}<link rel="stylesheet" href="/static/{{.}}">
{{end}}
<link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'><text y='13' font-size='14'>%F0%9F%93%88</text></svg>">
</head>
<body>
<a class="skip" href="#content">Skip to content</a>
<header class="masthead">
  <div class="masthead-inner">
    <div class="brand"><a href="/">OpenGET</a>
      <small>Old School RuneScape Grand Exchange tracker</small>
    </div>
    <form class="sitesearch" method="get" action="/search" role="search" aria-label="Search items">
      <input type="search" name="q" value="{{.Query}}" placeholder="Search items…" aria-label="Search items">
      <button type="submit">Go</button>
    </form>
    <form class="f2ptoggle" method="post" action="/f2p" aria-label="Membership filter">
      <input type="hidden" name="return" value="{{.Return}}">
      <label><input type="checkbox" name="f2p" value="1"{{if .F2P}} checked{{end}}> Free-to-play only</label>
      <button type="submit">Apply</button>
    </form>
    <form class="themepick" method="post" action="/theme" aria-label="Site theme">
      <input type="hidden" name="return" value="{{.Return}}">
      <label><span class="vh">Theme</span>
        <select name="theme">
          {{range .Themes}}<option value="{{.Key}}"{{if eq .Key $.Theme.Key}} selected{{end}}>{{.Label}}</option>{{end}}
        </select>
      </label>
      <button type="submit">Apply</button>
    </form>
  </div>
  <nav class="tabs">
    {{/* The newline between the links is load-bearing for text browsers: nav.tabs is a flex container, so graphical browsers drop whitespace-only text nodes between flex items and the gap property alone spaces the tabs, while Lynx (which reads no CSS) collapses it to the single space that keeps "Home Items Margins" from rendering as "HomeItemsMargins". */}}
    {{range .Nav}}<a href="{{.Href}}"{{if .Current}} aria-current="page"{{end}}>{{.Label}}</a>
    {{end}}
  </nav>
</header>
<main id="content" tabindex="-1">
  {{if not .NoHeading}}
  {{if .Title}}<h1>{{.Title}}</h1>{{end}}
  {{if .Subtitle}}<p class="subtitle">{{.Subtitle}}</p>{{end}}
  {{else}}
  {{if .Title}}<h1 class="vh">{{.Title}}</h1>{{end}}
  {{end}}
  {{.Body}}
  {{if .UpdatedAgo}}<div class="status-bar">
    <p class="status-bar-field muted">Prices updated <time datetime="{{.UpdatedISO}}">{{.UpdatedAgo}}</time></p>
    <p class="status-bar-field muted"><time datetime="{{.UpdatedISO}}">{{.UpdatedAt}}</time></p>
  </div>{{end}}
</main>
<footer>
  <div class="inner">
    <p>{{.Credit}}
      <a href="https://oldschool.runescape.wiki/w/RuneScape:Real-time_Prices">API documentation</a> ·
      <a href="https://oldschool.runescape.wiki/">OSRS Wiki</a> ·
      <a href="https://runelite.net/">RuneLite</a></p>
    <p class="retro">Also served over
      <a href="gopher://dreamstation.systems/1/ge">gopher</a>,
      <a href="gemini://dreamstation.systems/ge/">gemini</a>,
      <a href="spartan://dreamstation.systems/ge/">spartan</a>,
      and <code>finger abyssal_whip@dreamstation.systems</code>.</p>
    <p>Old School RuneScape is a trademark of Jagex Limited; OpenGET is an unofficial fan tool with no affiliation or endorsement from Jagex, the OSRS Wiki, or RuneLite.</p>
    <p><a href="/about">About</a> · <a href="/status">Status</a> · <a href="/api">API</a> · openget {{.Version}}</p>
    <p class="badges"><a href="https://www.w3.org/WAI/WCAG2AA-Conformance"
        title="Explanation of WCAG 2 Level AA conformance"><img src="/static/wcag2.2AA.svg"
        width="88" height="31"
        alt="Level AA conformance, W3C Web Content Accessibility Guidelines 2.2"></a><img
        src="/static/debian-powered.gif" width="88" height="31" alt="Powered by Debian"><img
        src="/static/trans-flag.gif" width="88" height="31" alt="Transgender pride flag"></p>
  </div>
</footer>
</body>
</html>`

// ---------------------------------------------------------------------------
// Static assets
// ---------------------------------------------------------------------------

func (s *Server) static(w http.ResponseWriter, r *http.Request) {
	name := strings.TrimPrefix(r.URL.Path, "/static/")
	if name == "" || strings.Contains(name, "..") {
		http.NotFound(w, r)
		return
	}
	b, err := staticFS.ReadFile("static/" + name)
	if err != nil {
		http.NotFound(w, r)
		return
	}
	switch {
	case strings.HasSuffix(name, ".css"):
		w.Header().Set("Content-Type", "text/css; charset=utf-8")
	case strings.HasSuffix(name, ".svg"):
		w.Header().Set("Content-Type", "image/svg+xml")
	case strings.HasSuffix(name, ".gif"):
		w.Header().Set("Content-Type", "image/gif")
	case strings.HasSuffix(name, ".woff2"):
		w.Header().Set("Content-Type", "font/woff2")
	default:
		w.Header().Set("Content-Type", "application/octet-stream")
	}
	// Assets are embedded in the binary, so they only ever change on deploy.
	w.Header().Set("Cache-Control", "public, max-age=3600")
	w.Write(b)
}

func (s *Server) sitemap(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	w.Header().Set("Content-Type", "application/xml; charset=utf-8")
	fmt.Fprint(w, `<?xml version="1.0" encoding="UTF-8"?>`+"\n")
	fmt.Fprint(w, `<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">`+"\n")
	add := func(loc string) {
		fmt.Fprintf(w, "  <url><loc>%s%s</loc></url>\n", s.cfg.BaseURL, loc)
	}
	for _, p := range []string{"/", "/items", "/alch", "/alch?spell=low", "/store-profit",
		"/ge-tax-calculator", "/calc", "/indices", "/about", "/status"} {
		add(p)
	}
	for _, f := range views.Finders() {
		add("/flips/" + f.Slug)
	}
	if kinds, err := s.db.RecipeKinds(ctx); err == nil {
		for k := range kinds {
			add("/calc/" + k)
		}
	}
	if idx, err := s.db.Indices(ctx); err == nil {
		for _, i := range idx {
			add("/indices/" + i.ID)
		}
	}
	// Item pages, most-traded first and capped: a sitemap listing every one of 4,650 items mostly advertises pages with no data on them.
	items, _, err := s.db.ListItems(ctx, store.ListOptions{
		Sort: "gpvol", Desc: true, Limit: 500, Tradeable: true,
	})
	if err == nil {
		for _, it := range items {
			add(views.ItemPath(it.ID))
		}
	}
	fmt.Fprint(w, "</urlset>\n")
}

// ---------------------------------------------------------------------------
// Small parameter helpers
// ---------------------------------------------------------------------------

func qInt(r *http.Request, key string, def int) int {
	v, err := strconv.Atoi(strings.TrimSpace(r.URL.Query().Get(key)))
	if err != nil {
		return def
	}
	return v
}

func qInt64(r *http.Request, key string, def int64) int64 {
	v, err := strconv.ParseInt(strings.TrimSpace(r.URL.Query().Get(key)), 10, 64)
	if err != nil {
		return def
	}
	return v
}

func qBool(r *http.Request, key string) bool {
	v := r.URL.Query().Get(key)
	return v == "1" || v == "true" || v == "on"
}
