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

// Package views builds protocol-agnostic render.Docs from the database.
//
// Nothing in here knows about HTTP, gemtext or gophermaps. A page is built once and rendered by whichever frontend asked for it, which is what keeps the web site and the capsule showing the same numbers with the same caveats instead of drifting apart one calculator at a time.
package views

import (
	"context"
	"fmt"
	"strings"
	"time"

	"dreamstation.systems/openget/internal/calc"
	"dreamstation.systems/openget/internal/config"
	"dreamstation.systems/openget/internal/render"
	"dreamstation.systems/openget/internal/store"
)

// Builder constructs Docs.
type Builder struct {
	DB  *store.DB
	Cfg config.Config
	// F2POnly hides members' items from every list this Builder builds — the site-wide free-to-play toggle. It lives on the Builder rather than in a parameter on each method because it applies to every page at once, and threading a bool through a dozen signatures would guarantee that the thirteenth page silently forgot it.
	F2POnly bool
}

// New returns a Builder.
func New(db *store.DB, cfg config.Config) *Builder { return &Builder{DB: db, Cfg: cfg} }

// F2P returns a copy of the Builder with the free-to-play filter set.
//
// A copy, because the server holds one shared Builder for the life of the process and this setting belongs to a single reader's request.
func (b *Builder) F2P(on bool) *Builder {
	c := *b
	c.F2POnly = on
	return &c
}

// filter applies the site-wide toggle to a list query as a DEFAULT rather than an override: a page that has already picked a side of the members split (the ?members= parameter on /items) keeps what it asked for, so a hand-written URL still means what it says.
func (b *Builder) filter(o store.ListOptions) store.ListOptions {
	if b.F2POnly && !o.MembersOnly && !o.F2POnly {
		o.F2POnly = true
	}
	return o
}

// f2pNote says on the page itself that rows have been withheld. Without it, a reader who set the toggle days ago and forgot concludes the whip has been delisted rather than hidden.
func (b *Builder) f2pNote(d *render.Doc) {
	if b.F2POnly {
		d.Note("Members' items are hidden. Untick \"Free-to-play only\" in the header to show them.")
	}
}

// ItemPath is the canonical path for an item page.
func ItemPath(id int) string { return fmt.Sprintf("/item/%d", id) }

// Credit is shown on every page. The API is free, volunteer-run and offered for exactly this kind of tool; saying so prominently is the least we owe.
const Credit = "Price data from the OSRS Wiki real-time prices API, run by the OSRS Wiki in partnership with RuneLite."

// ---------------------------------------------------------------------------
// Home
// ---------------------------------------------------------------------------

// Home builds the front page: a few leaderboards and the archive status.
func (b *Builder) Home(ctx context.Context) (*render.Doc, error) {
	d := &render.Doc{
		Title:    "OpenGET",
		Subtitle: "Old School RuneScape Grand Exchange prices, margins and money-making calculators",
		Path:     "/",
	}

	top, _, err := b.DB.ListItems(ctx, b.filter(store.ListOptions{
		Sort: "potential", Desc: true, Limit: 15, Tradeable: true, HasLimit: true,
		MinVolume: 100, MaxAge: FreshWindow,
	}))
	if err != nil {
		return nil, err
	}
	d.Add(render.Heading{Level: 2, Text: "Best flips right now", Anchor: "flips"})
	d.Add(b.itemTable(top, "Ranked by profit per 4-hour buy limit, after the 2% GE tax."))

	movers, _, err := b.DB.ListItems(ctx, b.filter(store.ListOptions{
		Sort: "change24h", Desc: true, Limit: 10, Tradeable: true, MinVolume: 1000,
	}))
	if err != nil {
		return nil, err
	}
	d.Add(render.Heading{Level: 2, Text: "Biggest 24-hour risers", Anchor: "movers"})
	d.Add(b.itemTable(movers, ""))

	d.Add(render.Links{Title: "Tools", Items: []render.Link{
		{Text: "All items", Href: "/items", Desc: "every tradeable item, sortable"},
		{Text: "Highest margins", Href: "/flips/margin", Desc: "raw profit per item"},
		{Text: "Highest ROI", Href: "/flips/roi", Desc: "profit per gp invested"},
		{Text: "Potential profit", Href: "/flips/potential", Desc: "margin times buy limit"},
		{Text: "High volume", Href: "/flips/volume", Desc: "what is actually trading"},
		{Text: "New items", Href: "/flips/new", Desc: "recently added to the game"},
		{Text: "High alchemy", Href: "/alch", Desc: "alch profit, correctly untaxed"},
		{Text: "Money makers", Href: "/calc", Desc: "decanting, planks, herblore and more"},
		{Text: "GE tax calculator", Href: "/ge-tax-calculator", Desc: "what you actually receive"},
		{Text: "Market indices", Href: "/indices", Desc: "with published constituents"},
	}})

	b.f2pNote(d)
	b.addFreshness(ctx, d)
	return d, nil
}

// ---------------------------------------------------------------------------
// Item list and finders
// ---------------------------------------------------------------------------

// ListPage builds a filtered item table.
func (b *Builder) ListPage(ctx context.Context, title, path string, o store.ListOptions, blurb string) (*render.Doc, int, error) {
	items, total, err := b.DB.ListItems(ctx, b.filter(o))
	if err != nil {
		return nil, 0, err
	}
	d := &render.Doc{Title: title, Path: path}
	if blurb != "" {
		d.Subtitle = blurb
	}
	d.Add(b.itemTable(items, ""))
	b.f2pNote(d)
	b.addFreshness(ctx, d)
	return d, total, nil
}

// Finder describes one of the flip-finding views.
type Finder struct {
	Slug    string
	Title   string
	Blurb   string
	Options store.ListOptions
	Note    string
}

// FreshWindow is how recently both sides of an item's book must have traded for it to appear in a flip finder. Six hours is generous enough to keep genuinely slow but real items listed, and tight enough to exclude prints that no longer describe a market anyone can trade into.
const FreshWindow = 6 * 3600

// Finders are the flip-finding tools. ge-tracker puts every one of these behind Premium; here they are simply pages.
func Finders() []Finder {
	staleNote := "Items whose last buy or sell was more than six hours ago are excluded. " +
		"Without that filter the top of this list is simply the items with the oldest prices — " +
		"a single ancient print against a current one manufactures an enormous margin that " +
		"nobody can actually trade."
	return []Finder{
		{
			Slug:    "margin",
			Title:   "Highest margins",
			Blurb:   "Raw profit per item after the 2% Grand Exchange tax, buying at the instant-sell price and selling at the instant-buy price.",
			Options: store.ListOptions{Sort: "margin", Desc: true, Tradeable: true, MinVolume: 50, MaxAge: FreshWindow},
			Note:    "A large margin on an item nobody trades is not money. Check the volume column before committing capital. " + staleNote,
		},
		{
			Slug:    "roi",
			Title:   "Highest ROI",
			Blurb:   "Profit as a percentage of the capital tied up, rather than in coins per item.",
			Options: store.ListOptions{Sort: "roi", Desc: true, Tradeable: true, MinVolume: 500, MaxAge: FreshWindow},
			Note:    staleNote,
		},
		{
			Slug:    "potential",
			Title:   "Potential profit",
			Blurb:   "Margin multiplied by the 4-hour buy limit: the most one account can make per limit window.",
			Options: store.ListOptions{Sort: "potential", Desc: true, Tradeable: true, HasLimit: true, MinVolume: 50, MaxAge: FreshWindow},
			Note:    "Buy limits are per-item and reset on a rolling 4-hour window. " + staleNote,
		},
		{
			Slug:    "volume",
			Title:   "High volume",
			Blurb:   "The most actively traded items over the last 24 hours, counted from our own archive.",
			Options: store.ListOptions{Sort: "volume", Desc: true, Tradeable: true},
		},
		{
			Slug:    "new",
			Title:   "New items",
			Blurb:   "Items most recently added to the game, newest first.",
			Options: store.ListOptions{Sort: "newest", Desc: true},
			Note:    "\"New\" means new to this archive. Items that existed before OpenGET started recording all share the date of the first mapping poll.",
		},
	}
}

// FinderBySlug looks up one finder.
func FinderBySlug(slug string) (Finder, bool) {
	for _, f := range Finders() {
		if f.Slug == slug {
			return f, true
		}
	}
	return Finder{}, false
}

// ItemTable renders a slice of items as the standard table. Exported so the personalisation pages can reuse the exact same columns and caveats.
func (b *Builder) ItemTable(items []*store.Item, caption string) render.Table {
	return b.itemTable(items, caption)
}

// itemTable renders a slice of items as the standard table.
func (b *Builder) itemTable(items []*store.Item, caption string) render.Table {
	t := render.Table{
		Caption: caption,
		Empty:   "No items match those filters.",
		Columns: []render.Column{
			{Title: "Item", SortKey: "name", Retro: true, RowHeader: true},
			{Title: "Buy", Align: render.AlignRight, SortKey: "low", Retro: true,
				Hint: "Instant-sell price: what you can buy for right now"},
			{Title: "Sell", Align: render.AlignRight, SortKey: "high", Retro: true,
				Hint: "Instant-buy price: what you can sell for right now"},
			{Title: "Tax", Align: render.AlignRight, SortKey: "tax",
				Hint: "2% of the sale price, capped at 5,000,000 gp"},
			{Title: "Margin", Align: render.AlignRight, SortKey: "margin", Retro: true,
				Hint: "Profit per item after tax"},
			{Title: "ROI", Align: render.AlignRight, SortKey: "roi", Retro: true,
				Hint: "Margin as a percentage of the buy price"},
			{Title: "Limit", Align: render.AlignRight, SortKey: "limit",
				Hint: "4-hour Grand Exchange buy limit"},
			{Title: "Potential", Align: render.AlignRight, SortKey: "potential",
				Hint: "Margin times buy limit"},
			{Title: "Vol 24h", Align: render.AlignRight, SortKey: "volume", Retro: true,
				Hint: "Units traded in the last 24 hours, from our archive"},
			{Title: "24h", Align: render.AlignRight, SortKey: "change24h",
				Hint: "Price change over 24 hours"},
		},
	}
	for _, it := range items {
		name := it.Name
		if it.Members {
			name += " ●"
		}
		t.Rows = append(t.Rows, []render.Cell{
			render.CL(name, ItemPath(it.ID)),
			render.C(render.GPOpt(it.Low)),
			render.C(render.GPOpt(it.High)),
			render.C(render.GPOpt(it.Tax)),
			marginCell(it.Margin),
			pctCell(it.ROIPct),
			render.C(limitText(it)),
			marginCell(it.Potential),
			render.C(render.GPShort(it.AvgVol24h)),
			pctCell(it.Change24h),
		})
	}
	return t
}

func marginCell(p *int64) render.Cell {
	if p == nil {
		return render.C(render.Dash)
	}
	return render.Cell{Text: render.GP(*p), Tone: render.Tone(*p)}
}

func pctCell(p *float64) render.Cell {
	if p == nil {
		return render.C(render.Dash)
	}
	return render.Cell{Text: render.Pct(*p), Tone: render.ToneF(*p)}
}

func limitText(it *store.Item) string {
	if it.BuyLimit == nil {
		return render.Dash
	}
	return render.GP(int64(*it.BuyLimit))
}

// ---------------------------------------------------------------------------
// Item detail
// ---------------------------------------------------------------------------

// Windows are the chart ranges offered on an item page.
var Windows = []struct {
	Key   string
	Label string
	Step  string
	Span  time.Duration
}{
	{"1d", "1 day", "5m", 24 * time.Hour},
	{"1w", "1 week", "1h", 7 * 24 * time.Hour},
	{"1m", "1 month", "6h", 30 * 24 * time.Hour},
	{"1y", "1 year", "24h", 365 * 24 * time.Hour},
	{"all", "All", "24h", 0},
}

// ItemPage builds the detail page for one item.
//
// The favourite control is added by the web layer, not here: it is the one piece of an item page that only makes sense over HTTP, since the retro protocols reach personalisation through their own mechanisms.
func (b *Builder) ItemPage(ctx context.Context, id int, window string) (*render.Doc, error) {
	it, err := b.DB.GetItem(ctx, id)
	if err != nil {
		return nil, err
	}

	d := &render.Doc{
		Title:    it.Name,
		Subtitle: it.Examine,
		Path:     ItemPath(it.ID),
	}
	if it.Removed {
		d.Add(render.Para{Muted: true, Text: "This item no longer appears in the game's item mapping. " +
			"Its price history is kept here because upstream can no longer serve it at all."})
	}

	flip := calc.NewFlip(it.ID, deref(it.Low), deref(it.High), it.Limit())

	facts := render.Facts{Title: "Prices", Pairs: []render.KV{
		{Key: "Buy at (instant-sell)", Value: render.GPOpt(it.Low), Hint: "The lowest price someone is selling at now"},
		{Key: "Sell at (instant-buy)", Value: render.GPOpt(it.High), Hint: "The highest price someone is buying at now"},
		{Key: "GE tax on sale", Value: render.GP(flip.Tax), Hint: "2% of the sale price, capped at 5,000,000 gp"},
		{Key: "Margin", Value: render.GP(flip.Margin), Tone: render.Tone(flip.Margin)},
		{Key: "ROI", Value: render.PctPlain(flip.ROI), Tone: render.ToneF(flip.ROI)},
	}}
	if it.BuyLimit != nil {
		facts.Pairs = append(facts.Pairs,
			render.KV{Key: "Buy limit (4h)", Value: render.GP(int64(*it.BuyLimit))},
			render.KV{Key: "Potential profit", Value: render.GP(flip.Potential), Tone: render.Tone(flip.Potential)})
	} else {
		facts.Pairs = append(facts.Pairs, render.KV{Key: "Buy limit (4h)", Value: "not published by the API"})
	}
	if calc.IsExempt(it.ID) {
		facts.Pairs = append(facts.Pairs, render.KV{Key: "Tax status", Value: "exempt from the convenience fee"})
	}
	facts.Pairs = append(facts.Pairs,
		render.KV{Key: "Last buy seen", Value: render.AgoUnix(it.HighTime), At: unixAt(it.HighTime)},
		render.KV{Key: "Last sell seen", Value: render.AgoUnix(it.LowTime), At: unixAt(it.LowTime)})
	d.Add(facts)

	details := render.Facts{Title: "Item", Pairs: []render.KV{
		{Key: "Item ID", Value: fmt.Sprint(it.ID)},
		{Key: "Members", Value: yesNo(it.Members)},
	}}
	if it.HighAlch != nil {
		details.Pairs = append(details.Pairs, render.KV{Key: "High alch", Value: render.GP(*it.HighAlch)})
	}
	if it.LowAlch != nil {
		details.Pairs = append(details.Pairs, render.KV{Key: "Low alch", Value: render.GP(*it.LowAlch)})
	}
	if it.Value != nil {
		// Not labelled "shop value": this is the base value from the game's item definitions, which every item carries whether or not a shop has ever stocked it. See openget.txt, SHOP INVENTORIES.
		details.Pairs = append(details.Pairs, render.KV{Key: "Base value", Value: render.GP(*it.Value),
			Hint: "The item's value in the game's own definitions. Alchemy and general-store rates derive from it; it is not a price any shop necessarily charges."})
	}
	// Both spells, computed here rather than read from item_stats.alch_profit: that column covers high alchemy only, and it was priced with whatever a nature rune cost at the last stats run, which would let two rows sitting next to each other disagree about the price of the same rune.
	nature := b.buyPrice(ctx, calc.NatureRuneID)
	for _, s := range calc.AlchSpells {
		v := AlchValue(it, s)
		if v == nil || *v <= 0 || it.High == nil {
			continue
		}
		// Fire runes are not charged, matching /alch's default: a staff supplies them, so a nature rune is the whole cost.
		profit := calc.AlchProfit(*v, nature, *it.High)
		details.Pairs = append(details.Pairs, render.KV{
			Key: s.Short + " profit", Value: render.GP(profit), Tone: render.Tone(profit),
			Hint: s.Short + " value minus a nature rune minus the buy price, assuming a fire staff. " +
				"No GE tax: alching is not a Grand Exchange sale.",
		})
	}
	d.Add(details)

	changes := render.Facts{Title: "Price change", Pairs: []render.KV{
		{Key: "1 hour", Value: render.PctOpt(it.Change1h), Tone: toneOf(it.Change1h)},
		{Key: "24 hours", Value: render.PctOpt(it.Change24h), Tone: toneOf(it.Change24h)},
		{Key: "7 days", Value: render.PctOpt(it.Change7d), Tone: toneOf(it.Change7d)},
		{Key: "30 days", Value: render.PctOpt(it.Change30d), Tone: toneOf(it.Change30d)},
	}}
	d.Add(changes)

	win := Windows[0]
	for _, w := range Windows {
		if w.Key == window {
			win = w
		}
	}
	since := int64(0)
	if win.Span > 0 {
		since = time.Now().Add(-win.Span).Unix()
	}
	pts, err := b.DB.Series(ctx, it.ID, win.Step, since, 5000)
	if err != nil {
		return nil, err
	}
	chart := render.Chart{
		Title:   fmt.Sprintf("%s — %s", it.Name, win.Label),
		Height:  260,
		AltLink: fmt.Sprintf("/chart/%d.svg?w=%s", it.ID, win.Key),
	}
	var hi, lo []render.XY
	for _, p := range pts {
		if p.High != nil {
			hi = append(hi, render.XY{X: p.TS, Y: float64(*p.High)})
		}
		if p.Low != nil {
			lo = append(lo, render.XY{X: p.TS, Y: float64(*p.Low)})
		}
	}
	// Gold and blue are the safest OSRS-palette pairing for red-green colour blindness, but too close in lightness alone — dashing the buy series is what actually separates the two lines. See openget.txt, CHART COLOURS.
	chart.Series = []render.Series{
		{Name: "sell", Points: hi, Colour: "#ffbb22"},
		{Name: "buy", Points: lo, Colour: "#78adff", Dash: "5 3"},
	}
	d.Add(chart)

	var winLinks []render.Link
	for _, w := range Windows {
		winLinks = append(winLinks, render.Link{
			Text: w.Label, Href: ItemPath(it.ID) + "?w=" + w.Key,
			// Marks which range is on screen, so the link list doesn't show five identical-looking choices with no indication of where you already stand.
			Current: w.Key == win.Key,
		})
	}
	d.Add(render.Links{Title: "Chart range", NavLabel: "Chart range", Items: winLinks})

	if vol, at, _ := b.DB.LatestVolume(ctx, it.ID); vol > 0 {
		d.Add(render.Facts{Title: "Volume", Pairs: []render.KV{
			{Key: "Traded (24h, our archive)", Value: render.GP(it.AvgVol24h)},
			{Key: "Upstream /volumes figure", Value: render.GP(vol),
				Hint: "From the wiki's undocumented /volumes endpoint, as at " + at.UTC().Format(time.RFC3339)},
		}})
		d.Note("The upstream /volumes endpoint is undocumented and does not agree with the 24-hour bucket totals, " +
			"so the two volume figures are shown separately rather than blended into one number.")
	}

	if it.BuyLimit != nil {
		d.Note("Some items share a connected buy limit with their other dose or charge variants — " +
			"prayer potions, for instance, draw on one pool across all four doses. The API does not publish those " +
			"connections, so the limit shown here is the per-item figure and may overstate what you can actually buy.")
	}
	b.addFreshness(ctx, d)
	return d, nil
}

func toneOf(p *float64) int {
	if p == nil {
		return 0
	}
	return render.ToneF(*p)
}

func deref(p *int64) int64 {
	if p == nil {
		return 0
	}
	return *p
}

// unixAt turns the API's optional unix timestamps into a time for <time datetime>. A nil pointer means the price has never been observed, and stays the zero time, which timeWrap leaves unmarked.
func unixAt(p *int64) time.Time {
	if p == nil {
		return time.Time{}
	}
	return time.Unix(*p, 0)
}

func yesNo(b bool) string {
	if b {
		return "yes"
	}
	return "no"
}

// ---------------------------------------------------------------------------
// Search
// ---------------------------------------------------------------------------

// Search builds a results page.
func (b *Builder) Search(ctx context.Context, q string) (*render.Doc, error) {
	d := &render.Doc{Title: "Search", Path: "/search"}
	d.Add(render.Form{
		Action: "/search", Method: "get", Prompt: "Item name",
		Fields: []render.Field{{Name: "q", Label: "Item name", Value: q}},
		Submit: "Search",
	})
	q = strings.TrimSpace(q)
	if q == "" {
		return d, nil
	}
	// Filtered in SQL rather than after the fact: post-filtering a 50-row limit would let a search whose first 50 hits are all members' items report no results at all when a free-to-play match exists further down.
	items, err := b.DB.SearchItems(ctx, q, 50, b.F2POnly)
	if err != nil {
		return nil, err
	}
	noun := "results"
	if len(items) == 1 {
		noun = "result"
	}
	d.Subtitle = fmt.Sprintf("%d %s for %q", len(items), noun, q)
	d.Add(b.itemTable(items, ""))
	b.f2pNote(d)
	return d, nil
}

// ---------------------------------------------------------------------------
// Freshness / status
// ---------------------------------------------------------------------------

func (b *Builder) addFreshness(ctx context.Context, d *render.Doc) {
	if t, err := b.DB.LatestFetch(ctx); err == nil && !t.IsZero() {
		d.Updated = t
	}
}

// Status builds the operational page: what is running, how big the archive is, and how the backfill is progressing.
func (b *Builder) Status(ctx context.Context, version string, freeDiskMB int64, pauseWhy string, paused bool) (*render.Doc, error) {
	d := &render.Doc{Title: "Status", Path: "/status"}

	// Measured on a timer, not now: counting the archive takes the better part
	// of a minute (see store.ArchiveStats).
	stats := b.DB.ArchiveStats()
	f := render.Facts{Title: "Service", Pairs: []render.KV{
		{Key: "Version", Value: version},
		{Key: "Database", Value: render.GPShort(b.DB.SizeOnDisk()) + "B on disk"},
		{Key: "Free disk", Value: fmt.Sprintf("%d MB", freeDiskMB)},
	}}
	if paused {
		f.Pairs = append(f.Pairs, render.KV{Key: "Ingestion", Value: "PAUSED — " + pauseWhy, Tone: -1})
	} else {
		f.Pairs = append(f.Pairs, render.KV{Key: "Ingestion", Value: "running", Tone: 1})
	}
	d.Add(f)

	arch := render.Facts{Title: "Archive"}
	if stats.At.IsZero() {
		// Nothing measured yet — the first pass runs shortly after boot. Say so
		// rather than printing zeroes, which would read as an empty archive.
		arch.Pairs = append(arch.Pairs, render.KV{Key: "Size", Value: "being measured, check back shortly"})
	} else {
		for _, step := range []string{"5m", "1h", "24h"} {
			sp, ok := stats.Spans[step]
			if !ok {
				continue
			}
			val := "empty"
			if sp.Rows > 0 {
				val = fmt.Sprintf("%s rows, %s → %s", render.GP(sp.Rows),
					sp.Oldest.UTC().Format("2006-01-02"), sp.Newest.UTC().Format("2006-01-02"))
			}
			arch.Pairs = append(arch.Pairs, render.KV{Key: step + " buckets", Value: val})
		}
		for _, t := range []string{"items", "latest", "volumes", "item_stats", "shop_offers"} {
			arch.Pairs = append(arch.Pairs, render.KV{Key: t, Value: render.GP(stats.Counts[t]) + " rows"})
		}
		arch.Pairs = append(arch.Pairs, render.KV{
			Key:   "Measured",
			Value: stats.At.UTC().Format("2006-01-02 15:04") + " UTC",
			Hint:  "Counting the archive takes about a minute, so it is done on a timer rather than when you load this page",
		})
	}
	d.Add(arch)

	if done, total, err := b.DB.BackfillProgress(ctx, "24h"); err == nil && total > 0 {
		d.Add(render.Facts{Title: "Historical backfill", Pairs: []render.KV{
			{Key: "24h timeseries", Value: fmt.Sprintf("%d of %d items (%.1f%%)", done, total, float64(done)/float64(total)*100)},
		}})
	}

	runs, err := b.DB.RecentRuns(ctx, 25)
	if err != nil {
		return nil, err
	}
	t := render.Table{
		Caption: "Recent jobs",
		Columns: []render.Column{
			{Title: "Job", Retro: true},
			{Title: "Started", Retro: true},
			{Title: "Took", Align: render.AlignRight, Retro: true},
			{Title: "Result", Retro: true},
		},
	}
	for _, r := range runs {
		took := render.Dash
		if !r.Ended.IsZero() {
			took = r.Ended.Sub(r.Started).Round(time.Millisecond).String()
		}
		res := render.Cell{Text: "ok", Tone: 1}
		if !r.OK {
			res = render.Cell{Text: "failed: " + r.Note, Tone: -1}
		}
		t.Rows = append(t.Rows, []render.Cell{
			render.C(r.Job),
			render.Cell{Text: render.Ago(r.Started), At: r.Started},
			render.C(took), res,
		})
	}
	d.Add(t)

	return d, nil
}

// About builds the credits and policy page.
func (b *Builder) About(ctx context.Context) (*render.Doc, error) {
	d := &render.Doc{Title: "About OpenGET", Path: "/about"}
	d.Add(render.Para{Text: "OpenGET is a Grand Exchange price tracker and flipping tool for Old School RuneScape."})

	// First section on the page, ahead of the data credit: this one is an offer rather than an acknowledgement, and the GPL is only meaningful to a reader who can actually get at the source.
	d.Add(render.Heading{Level: 2, Text: "Download source code"})
	d.Add(render.Para{Text: "OpenGET is licensed under the GNU GPL version 2:"})
	d.Add(render.Links{Items: []render.Link{
		{Text: "View directory over FTP", Href: "ftp://dreamstation.systems/robinsSoftware/openget/"},
		{Text: "View on GitHub", Href: "https://github.com/robinpie/httpdreamstationsystems"},
	}})

	d.Add(render.Heading{Level: 2, Text: "Where the data comes from"})
	d.Add(render.Para{Text: Credit})
	d.Add(render.Para{Text: "Shop inventories come from a second source: Bucket, the wiki's structured-data " +
		"extension, which publishes what every shop in the game stocks and at what price. Only /store-profit uses it, " +
		"and only because no price feed carries what a shopkeeper has on the shelf."})
	d.Add(render.Links{Items: []render.Link{
		{Text: "OSRS Wiki real-time prices documentation", Href: "https://oldschool.runescape.wiki/w/RuneScape:Real-time_Prices"},
		{Text: "The wiki's Bucket API", Href: "https://oldschool.runescape.wiki/w/RuneScape:Bucket"},
		{Text: "The OSRS Wiki", Href: "https://oldschool.runescape.wiki/"},
		{Text: "RuneLite", Href: "https://runelite.net/"},
	}})
	d.Add(render.Heading{Level: 2, Text: "How the numbers are worked out"})
	d.Add(render.Para{Text: "\"Buy\" is the instant-sell price and \"sell\" is the instant-buy price, matching the API. " +
		"Margin is the sell price minus the 2% Grand Exchange tax minus the buy price. The tax is paid by the seller only, " +
		"is capped at 5,000,000 gp per item, rounds down to the whole coin, and does not apply to a fixed list of exempt items."})
	d.Add(render.Links{Items: []render.Link{
		{Text: "GE tax calculator, including the full exempt list", Href: "/ge-tax-calculator"},
		{Text: "Market indices and their published constituents", Href: "/indices"},
		{Text: "Service status and archive size", Href: "/status"},
	}})

	d.Add(render.Heading{Level: 2, Text: "Other ways to read this"})
	d.Add(render.Para{Text: "The same data is served over Gopher, Gemini, Spartan and finger. " +
		"Try: finger abyssal_whip@dreamstation.systems"})
	d.Add(render.Links{Items: []render.Link{
		{Text: "gopher://dreamstation.systems/1/ge", Href: "gopher://dreamstation.systems/1/ge"},
		{Text: "gemini://dreamstation.systems/ge/", Href: "gemini://dreamstation.systems/ge/"},
		{Text: "spartan://dreamstation.systems/ge/", Href: "spartan://dreamstation.systems/ge/"},
	}})

	d.Add(render.Heading{Level: 2, Text: "Contact"})
	d.Add(render.Links{Items: []render.Link{
		{Text: "robin@dreamstation.systems", Href: "mailto:robin@dreamstation.systems"},
	}})

	d.Add(render.Heading{Level: 2, Text: "Legal"})
	d.Add(render.Para{Muted: true, Text: "Old School RuneScape is a trademark of Jagex Limited. OpenGET is an unofficial " +
		"fan tool with no affiliation with or endorsement from Jagex."})
	return d, nil
}
