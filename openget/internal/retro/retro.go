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

// Package retro generates the Gopher, Gemini and Spartan frontends.
//
// The approach is deliberately static where it can be. After each stats recomputation the generator writes a tree of gophermaps into /srv/gopher/ge and gemtext into /srv/gemini/ge. gophernicus and molly-brown serve those files with no new daemon, no new listening socket and no new attack surface, and Spartan gets the gemtext for free because spartan.pl shares molly-brown's document root.
//
// Only the things that genuinely cannot be precomputed — item lookup across 4,650 items — are dynamic, and those go through a small CGI that talks to the JSON API over localhost.
package retro

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"sync"
	"time"

	"dreamstation.systems/openget/internal/config"
	"dreamstation.systems/openget/internal/render"
	"dreamstation.systems/openget/internal/store"
	"dreamstation.systems/openget/internal/views"
)

// Generator writes the static retro trees.
type Generator struct {
	db  *store.DB
	cfg config.Config
	log *slog.Logger
	vb  *views.Builder

	st      StatusSource
	version string

	mu   sync.Mutex
	last time.Time
}

// StatusSource supplies the two live numbers the status page reports that the
// database does not know. It is an interface rather than the concrete
// *ingest.Ingester so this package need not import the ingester to print them.
type StatusSource interface {
	Paused() (string, bool)
	FreeDiskMB() int64
}

// New builds a Generator. st may be nil, in which case no status page is written.
func New(db *store.DB, cfg config.Config, log *slog.Logger, st StatusSource, version string) *Generator {
	return &Generator{db: db, cfg: cfg, log: log, vb: views.New(db, cfg), st: st, version: version}
}

// gopherHost is the hostname advertised in generated gophermaps. It must match what gophernicus is started with (-h), or clients will follow links to a host that does not answer.
const gopherHost = "dreamstation.systems"

// Regenerate rewrites every generated page. Safe to call on every stats recomputation; it debounces so a burst of polls does not thrash the disk.
func (g *Generator) Regenerate(ctx context.Context) error {
	g.mu.Lock()
	if time.Since(g.last) < g.cfg.Retro.WriteEvery.Duration/2 {
		g.mu.Unlock()
		return nil
	}
	g.last = time.Now()
	g.mu.Unlock()

	start := time.Now()
	pages, err := g.buildPages(ctx)
	if err != nil {
		return err
	}

	var wrote int
	if dir := g.cfg.Retro.GopherDir; dir != "" {
		n, err := g.writeGopher(dir, pages)
		if err != nil {
			g.log.Error("gopher generation failed", "dir", dir, "err", err)
		} else {
			wrote += n
		}
	}
	if dir := g.cfg.Retro.GeminiDir; dir != "" {
		n, err := g.writeGemini(dir, pages)
		if err != nil {
			g.log.Error("gemini generation failed", "dir", dir, "err", err)
		} else {
			wrote += n
		}
	}
	g.log.Info("retro frontends regenerated", "files", wrote, "dur", time.Since(start).Round(time.Millisecond))
	return nil
}

// page is one generated document plus the filename it lands under.
type page struct {
	slug string // "" for the index
	doc  *render.Doc
}

// buildPages assembles everything worth precomputing.
//
// Deliberately NOT every item page: regenerating 4,650 item files every five minutes would be a great deal of disk churn to serve pages nobody has asked for. Item lookup is handled by the type-7 search selector and the Gemini CGI instead, which is what those mechanisms are for.
func (g *Generator) buildPages(ctx context.Context) ([]page, error) {
	n := g.cfg.Retro.TopN
	var pages []page

	index := &render.Doc{
		Title:    "OpenGET — OSRS Grand Exchange prices",
		Subtitle: "Live margins, ROI and money-making calculators.",
	}
	index.Add(render.Links{Title: "Flip finders", Items: []render.Link{
		{Text: "Highest margins", Href: "/margin", Desc: "profit per item after tax"},
		{Text: "Highest ROI", Href: "/roi", Desc: "profit per gp invested"},
		{Text: "Potential profit", Href: "/potential", Desc: "margin x buy limit"},
		{Text: "High volume", Href: "/volume", Desc: "what is actually trading"},
		{Text: "Biggest risers", Href: "/risers", Desc: "24 hour movers"},
		{Text: "Biggest fallers", Href: "/fallers", Desc: "24 hour movers"},
		{Text: "High alchemy", Href: "/alch", Desc: "alch profit, untaxed"},
		{Text: "Low alchemy", Href: "/alch-low", Desc: "the level 21 spell"},
	}})
	index.Add(render.Links{Title: "Reference", Items: []render.Link{
		{Text: "Market indices", Href: "/indices"},
		{Text: "Money makers", Href: "/calc"},
		{Text: "About and credits", Href: "/about"},
	}})
	index.Add(render.Form{
		Action: "/search", Prompt: "Search for an item by name",
	})
	index.Add(render.Para{Muted: true, Text: "You can also look an item up over finger: " +
		"finger abyssal_whip@dreamstation.systems"})
	index.Note("%s", views.Credit)
	pages = append(pages, page{"", index})

	lists := []struct {
		slug, title, blurb string
		opt                store.ListOptions
	}{
		{"margin", "Highest margins", "Profit per item after the 2% GE tax.",
			store.ListOptions{Sort: "margin", Desc: true, Tradeable: true, MinVolume: 50, MaxAge: views.FreshWindow, Limit: n}},
		{"roi", "Highest ROI", "Profit as a percentage of capital tied up.",
			store.ListOptions{Sort: "roi", Desc: true, Tradeable: true, MinVolume: 500, MaxAge: views.FreshWindow, Limit: n}},
		{"potential", "Potential profit", "Margin multiplied by the 4-hour buy limit.",
			store.ListOptions{Sort: "potential", Desc: true, Tradeable: true, HasLimit: true, MinVolume: 50, MaxAge: views.FreshWindow, Limit: n}},
		{"volume", "High volume", "Most actively traded over the last 24 hours.",
			store.ListOptions{Sort: "volume", Desc: true, Tradeable: true, Limit: n}},
		{"risers", "Biggest 24h risers", "Largest upward price moves.",
			store.ListOptions{Sort: "change24h", Desc: true, Tradeable: true, MinVolume: 1000, Limit: n}},
		{"fallers", "Biggest 24h fallers", "Largest downward price moves.",
			store.ListOptions{Sort: "change24h", Desc: false, Tradeable: true, MinVolume: 1000, Limit: n}},
	}
	for _, l := range lists {
		d, _, err := g.vb.ListPage(ctx, l.title, "/flips/"+l.slug, l.opt, l.blurb)
		if err != nil {
			return nil, err
		}
		pages = append(pages, page{l.slug, d})
	}

	// The capsules get one page per spell with the defaults applied. The web form that switches between them is WebOnly for a reason: neither Gopher nor Gemini can carry a two-control form, so the variants become files.
	if d, err := g.vb.AlchList(ctx, views.AlchOptions{Limit: n}); err == nil {
		pages = append(pages, page{"alch", d})
	}
	if d, err := g.vb.AlchList(ctx, views.AlchOptions{Spell: "low", Limit: n}); err == nil {
		pages = append(pages, page{"alch-low", d})
	}
	if d, err := g.vb.IndicesPage(ctx); err == nil {
		pages = append(pages, page{"indices", d})
	}
	if d, err := g.vb.CalcIndex(ctx); err == nil {
		pages = append(pages, page{"calc", d})
	}
	if d, err := g.vb.About(ctx); err == nil {
		pages = append(pages, page{"about", d})
	}
	// The money-maker families are small and change slowly, so they are cheap to precompute and are the most interesting thing to find on a capsule.
	//
	// The data timestamp is the same for every page in one run, so it is read once here rather than by each page builder.
	updated, _ := g.db.LatestFetch(ctx)
	if kinds, err := g.db.RecipeKinds(ctx); err == nil {
		for kind := range kinds {
			d, err := g.vb.CalcKind(ctx, kind)
			if err != nil {
				continue
			}
			pages = append(pages, page{"calc-" + kind, d})

			// And one page per recipe, since every row of the page just added links to its own breakdown. One price book is fetched for the whole family rather than one per recipe; see openget.txt, "NOTE ON THE TWO TREE LAYOUTS".
			rs, err := g.db.Recipes(ctx, kind)
			if err != nil {
				continue
			}
			pb, err := g.db.PriceBookFor(ctx, store.RecipeItemIDs(rs))
			if err != nil {
				g.log.Warn("recipe pages skipped", "kind", kind, "err", err)
				continue
			}
			for _, r := range rs {
				rd := g.vb.CalcRecipeDoc(r, pb)
				rd.Updated = updated
				pages = append(pages, page{"calc-" + kind + "/" + r.ID, rd})
			}
		}
	}
	// The home page links a status page, so the capsules need one. Cheap now
	// that the archive numbers on it are measured on a timer rather than read
	// when the page is built (see store.ArchiveStats).
	if g.st != nil {
		why, paused := g.st.Paused()
		if d, err := g.vb.Status(ctx, g.version, g.st.FreeDiskMB(), why, paused); err == nil {
			pages = append(pages, page{"status", d})
		} else {
			g.log.Warn("status page skipped", "err", err)
		}
	}
	return pages, nil
}

// writeGopher renders every page as a gophermap.
func (g *Generator) writeGopher(dir string, pages []page) (int, error) {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return 0, err
	}
	n := 0
	for _, p := range pages {
		opts := render.GopherOptions{
			Host:   gopherHost,
			Port:   70,
			Prefix: "/ge",
			Width:  70,
			// gophernicus runs CGI from the doc root's cgi-bin directory; the type-7 entry points there so item lookup works from a menu.
			SearchSelector: "/ge/cgi-bin/search",
		}
		body := render.Gophermap(p.doc, opts)
		// Rewrite the placeholder link targets used in the shared view models into gopher selectors under our own tree.
		body = render.RetroLinks(body, "/ge", "gopher")

		name := filepath.Join(dir, "gophermap")
		if p.slug != "" {
			sub := filepath.Join(dir, p.slug)
			if err := os.MkdirAll(sub, 0o755); err != nil {
				return n, err
			}
			name = filepath.Join(sub, "gophermap")
		}
		if err := writeFileAtomic(name, []byte(body)); err != nil {
			return n, err
		}
		n++
	}
	return n, nil
}

// writeGemini renders every page as gemtext.
//
// Spartan gets these for free: spartan.pl serves the same /srv/gemini root, so a file written here is immediately reachable over both protocols.
func (g *Generator) writeGemini(dir string, pages []page) (int, error) {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return 0, err
	}
	n := 0
	for _, p := range pages {
		opts := render.GemtextOptions{
			Prefix:  "/ge",
			Width:   72,
			WebBase: g.cfg.BaseURL,
		}
		body := render.Gemtext(p.doc, opts)
		body = render.RetroLinks(body, "/ge", "gemini")

		name := filepath.Join(dir, "index.gmi")
		if p.slug != "" {
			name = filepath.Join(dir, p.slug+".gmi")
			// Recipe slugs carry a directory component ("calc-herblore/herb-prayer"), and unlike the gopher writer this one is not creating a directory per page.
			if err := os.MkdirAll(filepath.Dir(name), 0o755); err != nil {
				return n, err
			}
		}
		if err := writeFileAtomic(name, []byte(body)); err != nil {
			return n, err
		}
		n++
	}
	return n, nil
}

// writeFileAtomic writes via a temporary file and a rename, so a reader never sees a half-written gophermap. gophernicus and molly-brown are serving out of this directory continuously.
func writeFileAtomic(path string, b []byte) error {
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, b, 0o644); err != nil {
		return err
	}
	if err := os.Rename(tmp, path); err != nil {
		os.Remove(tmp)
		return err
	}
	return nil
}

// ---------------------------------------------------------------------------
// Plain text, for finger
// ---------------------------------------------------------------------------

// ItemText renders one item as the plain text finger serves.
//
// verbose corresponds to finger's /W switch: the short form is the price and the margin, the long form adds ROI, buy limit, alch values, volume and a sparkline.
func (g *Generator) ItemText(ctx context.Context, id int, verbose bool) (string, error) {
	doc, err := g.vb.ItemPage(ctx, id, "1w")
	if err != nil {
		return "", err
	}
	if !verbose {
		doc = trimForFinger(doc)
	}
	return render.Text(doc, render.TextOptions{Width: 72, CRLF: true}), nil
}

// trimForFinger keeps only the headline facts for a non-verbose query.
func trimForFinger(d *render.Doc) *render.Doc {
	out := &render.Doc{Title: d.Title, Subtitle: d.Subtitle, Updated: d.Updated}
	for _, b := range d.Blocks {
		f, ok := b.(render.Facts)
		if !ok || f.Title != "Prices" {
			continue
		}
		out.Add(f)
		break
	}
	out.Add(render.Para{Muted: true, Text: "Use finger /W for the full listing."})
	return out
}

// SearchText renders search results as plain text.
func (g *Generator) SearchText(ctx context.Context, q string) (string, error) {
	doc, err := g.vb.Search(ctx, q)
	if err != nil {
		return "", err
	}
	return render.Text(doc, render.TextOptions{Width: 72, CRLF: true}), nil
}

// SummaryText is the greeting finger shows for a bare query.
func (g *Generator) SummaryText(ctx context.Context) (string, error) {
	doc, err := g.vb.Home(ctx)
	if err != nil {
		return "", err
	}
	return render.Text(doc, render.TextOptions{Width: 72, CRLF: true}), nil
}

// Dirs reports where the generator writes, for the status page.
func (g *Generator) Dirs() string {
	return fmt.Sprintf("gopher=%s gemini=%s", g.cfg.Retro.GopherDir, g.cfg.Retro.GeminiDir)
}
