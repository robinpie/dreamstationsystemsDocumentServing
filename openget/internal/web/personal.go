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

package web

import (
	"context"
	"encoding/xml"
	"errors"
	"fmt"
	"net"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"dreamstation.systems/openget/internal/calc"
	"dreamstation.systems/openget/internal/ident"
	"dreamstation.systems/openget/internal/render"
	"dreamstation.systems/openget/internal/store"
	"dreamstation.systems/openget/internal/views"
)

// cookieName is short because it appears in every request.
const cookieName = "ge"

// cookieMaxAge is two years, slid forward on each write.
const cookieMaxAge = 2 * 365 * 24 * 60 * 60

func (s *Server) personalRoutes(m *http.ServeMux) {
	m.HandleFunc("GET /favourites", s.page(s.favourites))
	m.HandleFunc("POST /favourites", s.postFavourite)
	m.HandleFunc("GET /prefs", s.page(s.prefsPage))
	m.HandleFunc("POST /prefs", s.postPrefs)
	m.HandleFunc("GET /tracker", s.page(s.tracker))
	m.HandleFunc("POST /tracker", s.postLedger)
	m.HandleFunc("POST /tracker/import", s.postImport)
	m.HandleFunc("GET /tracker/clear", s.page(s.clearLedgerPage))
	m.HandleFunc("POST /tracker/clear", s.postClearLedger)
	m.HandleFunc("GET /alerts", s.page(s.alertsPage))
	m.HandleFunc("POST /alerts", s.postAlert)
	m.HandleFunc("GET /code", s.page(s.codePage))
	m.HandleFunc("GET /restore/{code}", s.restore)
	m.HandleFunc("POST /restore", s.postRestore)
	m.HandleFunc("GET /u/{code}/alerts.xml", s.alertFeed)
	m.HandleFunc("GET /forget", s.page(s.forgetPage))
	m.HandleFunc("POST /forget", s.postForget)
}

// tokenFrom reads the cookie without creating anything. A reader who has never written has no token, and asking for one must not manufacture a row.
func tokenFrom(r *http.Request) (ident.Token, bool) {
	c, err := r.Cookie(cookieName)
	if err != nil {
		return "", false
	}
	tok, err := ident.Parse(c.Value)
	if err != nil {
		return "", false
	}
	return tok, true
}

// setCookie writes (or slides forward) the token cookie.
func (s *Server) setCookie(w http.ResponseWriter, r *http.Request, tok ident.Token) {
	http.SetCookie(w, &http.Cookie{
		Name:     cookieName,
		Value:    tok.Reveal(),
		Path:     "/",
		MaxAge:   cookieMaxAge,
		HttpOnly: true,
		// Secure only when we are actually on TLS, or a plain-HTTP test deployment silently loses every cookie it sets.
		Secure:   r.TLS != nil || strings.HasPrefix(s.cfg.BaseURL, "https://"),
		SameSite: http.SameSiteLaxMode,
	})
}

// mintLimiter caps token minting per client IP.
type mintLimiter struct {
	mu    sync.Mutex
	seen  map[string][]time.Time
	perHr int
}

func newMintLimiter(perHour int) *mintLimiter {
	return &mintLimiter{seen: map[string][]time.Time{}, perHr: perHour}
}

func (l *mintLimiter) allow(ip string) bool {
	if l.perHr <= 0 {
		return true
	}
	l.mu.Lock()
	defer l.mu.Unlock()
	now := time.Now()
	cut := now.Add(-time.Hour)
	kept := l.seen[ip][:0]
	for _, t := range l.seen[ip] {
		if t.After(cut) {
			kept = append(kept, t)
		}
	}
	if len(kept) >= l.perHr {
		l.seen[ip] = kept
		return false
	}
	l.seen[ip] = append(kept, now)
	// Opportunistic sweep so an unbounded set of IPs cannot grow the map forever; this only ever runs on a write path.
	if len(l.seen) > 4096 {
		for k, v := range l.seen {
			if len(v) == 0 || v[len(v)-1].Before(cut) {
				delete(l.seen, k)
			}
		}
	}
	return true
}

func clientIP(r *http.Request) string {
	// nginx sits in front, so trust its header; fall back to the socket.
	if v := r.Header.Get("X-Real-IP"); v != "" {
		return v
	}
	if v := r.Header.Get("X-Forwarded-For"); v != "" {
		if i := strings.IndexByte(v, ','); i > 0 {
			return strings.TrimSpace(v[:i])
		}
		return strings.TrimSpace(v)
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

// requireToken returns the caller's token, minting one if this is their first write. Returns ok=false when minting was rate-limited.
func (s *Server) requireToken(w http.ResponseWriter, r *http.Request) (ident.Token, bool) {
	if tok, ok := tokenFrom(r); ok {
		s.setCookie(w, r, tok) // slide the expiry forward
		return tok, true
	}
	if !s.mint.allow(clientIP(r)) {
		return "", false
	}
	tok, err := ident.New()
	if err != nil {
		s.log.Error("token mint", "err", err)
		return "", false
	}
	s.setCookie(w, r, tok)
	return tok, true
}

// redirectBack returns to the referring page, or to a fallback.
func redirectBack(w http.ResponseWriter, r *http.Request, fallback string) {
	dest := r.FormValue("return")
	if dest == "" {
		dest = r.Referer()
	}
	// Only ever redirect within this site: an open redirect is a phishing primitive and this form is posted from arbitrary pages.
	if dest == "" || !strings.HasPrefix(dest, "/") || strings.HasPrefix(dest, "//") {
		dest = fallback
	}
	http.Redirect(w, r, dest, http.StatusSeeOther)
}

// ---------------------------------------------------------------------------
// Favourites
// ---------------------------------------------------------------------------

func (s *Server) favourites(ctx context.Context, r *http.Request) (*render.Doc, render.HTMLOptions, error) {
	d := &render.Doc{Title: "Favourites", Path: "/favourites", NoIndex: true}
	tok, ok := tokenFrom(r)
	if !ok {
		d.Add(render.Para{Text: "You have no favourites yet."})
		d.Add(render.Links{Items: []render.Link{{Text: "Browse items", Href: "/items"}}})
		return d, render.HTMLOptions{}, nil
	}
	items, _, err := s.db.ListItems(ctx, store.ListOptions{
		Favourites: tok.Hash(), Sort: "margin", Desc: true, Limit: 500,
	})
	if err != nil {
		return nil, render.HTMLOptions{}, err
	}
	vb := views.New(s.db, s.cfg)
	d.Add(vb.ItemTable(items, ""))
	d.Add(render.Links{Items: []render.Link{
		{Text: "Your restore code", Href: "/code", Desc: "save this or you will lose these"},
	}})
	return d, render.HTMLOptions{}, nil
}

func (s *Server) postFavourite(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.Atoi(r.FormValue("item"))
	if err != nil {
		http.Error(w, "bad item", http.StatusBadRequest)
		return
	}
	tok, ok := s.requireToken(w, r)
	if !ok {
		http.Error(w, "too many new tokens from this address; try again later", http.StatusTooManyRequests)
		return
	}
	ctx := r.Context()
	if r.FormValue("remove") != "" {
		if err := s.db.RemoveFavourite(ctx, tok.Hash(), id); err != nil {
			s.log.Error("remove favourite", "err", err)
		}
		redirectBack(w, r, "/favourites")
		return
	}
	err = s.db.AddFavourite(ctx, tok.Hash(), id, s.cfg.Limits.Favourites)
	if errors.Is(err, store.ErrLimit) {
		http.Error(w, err.Error(), http.StatusConflict)
		return
	}
	if err != nil {
		s.log.Error("add favourite", "err", err)
		http.Error(w, "could not save", http.StatusInternalServerError)
		return
	}
	redirectBack(w, r, "/favourites")
}

// ---------------------------------------------------------------------------
// Restore codes
// ---------------------------------------------------------------------------

func (s *Server) codePage(ctx context.Context, r *http.Request) (*render.Doc, render.HTMLOptions, error) {
	d := &render.Doc{Title: "Your restore code", Path: "/code", NoIndex: true}
	tok, ok := tokenFrom(r)
	if !ok {
		d.Add(render.Para{Text: "You do not have a code yet. One is created the first time you save something — " +
			"a favourite, a preference, a trade."})
		d.Add(render.Form{
			Action: "/restore", Method: "post", Prompt: "Already have a code? Paste it here to use it on this device.",
			Fields: []render.Field{{Name: "code", Label: "Restore code"}},
			Submit: "Restore",
		})
		return d, render.HTMLOptions{}, nil
	}
	d.Add(render.Facts{Title: "Code", Pairs: []render.KV{
		{Key: "Your code", Value: tok.Display()},
		{Key: "One-click link", Value: s.cfg.BaseURL + "/restore/" + tok.Reveal()},
	}})
	d.Add(render.Para{Text: "Save this in a password manager. It is the only way back to your data."})
	d.Add(render.Para{Text: "Paste it on another device to use the same favourites, preferences, trades and alerts there. " +
		"Both devices then share one set of data — that is what an account is here."})
	d.Add(render.Heading{Level: 2, Text: "There is no recovery"})
	d.Add(render.Para{Text: "If you lose this code and clear your cookies, the data is gone. Nobody can restore it, " +
		"including us: only a hash of the code is stored, so we cannot look yours up or reset it."})
	d.Add(render.Para{Muted: true, Text: "Recovery is your responsibility."})
	d.Add(render.Para{Muted: true, Text: fmt.Sprintf(
		"Data attached to a code untouched for %d months is deleted automatically.",
		int(s.cfg.Limits.PruneAfter.Duration.Hours()/24/30))})
	d.Add(render.Links{Items: []render.Link{
		{Text: "Delete everything now", Href: "/forget"},
	}})
	return d, render.HTMLOptions{}, nil
}

func (s *Server) restore(w http.ResponseWriter, r *http.Request) {
	tok, err := ident.Parse(r.PathValue("code"))
	if err != nil {
		s.errorPage(w, r, http.StatusBadRequest, "That is not a valid code",
			"Restore codes are 26 characters. Check for a typo and try again.")
		return
	}
	s.setCookie(w, r, tok)
	http.Redirect(w, r, "/code", http.StatusSeeOther)
}

func (s *Server) postRestore(w http.ResponseWriter, r *http.Request) {
	tok, err := ident.Parse(r.FormValue("code"))
	if err != nil {
		s.errorPage(w, r, http.StatusBadRequest, "That is not a valid code",
			"Restore codes are 26 characters, in six dash-separated groups.")
		return
	}
	s.setCookie(w, r, tok)
	http.Redirect(w, r, "/code", http.StatusSeeOther)
}

func (s *Server) forgetPage(ctx context.Context, r *http.Request) (*render.Doc, render.HTMLOptions, error) {
	d := &render.Doc{Title: "Delete everything", Path: "/forget", NoIndex: true}
	if _, ok := tokenFrom(r); !ok {
		d.Add(render.Para{Text: "There is nothing stored for this browser."})
		return d, render.HTMLOptions{}, nil
	}
	d.Add(render.Para{Text: "This deletes your favourites, preferences, trades, alerts and the code itself. " +
		"It cannot be undone."})
	d.Add(render.Form{Action: "/forget", Method: "post", Submit: "Delete everything"})
	return d, render.HTMLOptions{}, nil
}

func (s *Server) postForget(w http.ResponseWriter, r *http.Request) {
	tok, ok := tokenFrom(r)
	if ok {
		// Cascades through favourites, prefs, ledger, alerts and certs.
		if _, err := s.db.Writer().ExecContext(r.Context(),
			`DELETE FROM tokens WHERE token_hash = ?`, tok.Hash()); err != nil {
			s.log.Error("forget", "err", err)
		}
	}
	http.SetCookie(w, &http.Cookie{Name: cookieName, Value: "", Path: "/", MaxAge: -1})
	http.Redirect(w, r, "/", http.StatusSeeOther)
}

// ---------------------------------------------------------------------------
// Preferences
// ---------------------------------------------------------------------------

func (s *Server) prefsPage(ctx context.Context, r *http.Request) (*render.Doc, render.HTMLOptions, error) {
	p := store.DefaultPrefs()
	if tok, ok := tokenFrom(r); ok {
		var err error
		if p, err = s.db.GetPrefs(ctx, tok.Hash()); err != nil {
			return nil, render.HTMLOptions{}, err
		}
	}
	d := &render.Doc{Title: "Preferences", Path: "/prefs", NoIndex: true}
	var sortOpts []render.Option
	for _, k := range []string{"margin", "roi", "potential", "volume", "gpvol", "name"} {
		sortOpts = append(sortOpts, render.Option{Value: k, Label: k, Selected: p.DefaultSort == k})
	}
	d.Add(render.Form{
		Action: "/prefs", Method: "post",
		Fields: []render.Field{
			{Name: "sort", Label: "Default sort", Kind: "select", Options: sortOpts},
			{Name: "rows", Label: "Rows per page", Kind: "number", Value: strconv.Itoa(p.RowsPerPage)},
			{Name: "minvol", Label: "Hide items below this 24h volume", Kind: "number", Value: strconv.FormatInt(p.MinVolume, 10)},
			{Name: "tz", Label: "Time zone", Value: p.TZ, Hint: "IANA name, e.g. Europe/London"},
		},
		Submit: "Save",
	})
	d.Add(render.Para{Muted: true, Text: "Saving creates a restore code if you do not already have one. " +
		"No email, no password, nothing to verify."})
	return d, render.HTMLOptions{}, nil
}

func (s *Server) postPrefs(w http.ResponseWriter, r *http.Request) {
	tok, ok := s.requireToken(w, r)
	if !ok {
		http.Error(w, "too many new tokens from this address; try again later", http.StatusTooManyRequests)
		return
	}
	rows, _ := strconv.Atoi(r.FormValue("rows"))
	if rows < 10 || rows > 500 {
		rows = 50
	}
	minvol, _ := strconv.ParseInt(r.FormValue("minvol"), 10, 64)
	tz := strings.TrimSpace(r.FormValue("tz"))
	if tz == "" {
		tz = "UTC"
	}
	if _, err := time.LoadLocation(tz); err != nil {
		tz = "UTC"
	}
	p := store.Prefs{
		Theme:       "auto",
		DefaultSort: r.FormValue("sort"),
		TZ:          tz,
		RowsPerPage: rows,
		MinVolume:   minvol,
	}
	if _, ok := sortKeyValid(p.DefaultSort); !ok {
		p.DefaultSort = "margin"
	}
	if err := s.db.SetPrefs(r.Context(), tok.Hash(), p); err != nil {
		s.log.Error("save prefs", "err", err)
		http.Error(w, "could not save", http.StatusInternalServerError)
		return
	}
	http.Redirect(w, r, "/prefs", http.StatusSeeOther)
}

func sortKeyValid(k string) (string, bool) {
	for _, v := range store.SortKeys() {
		if v == k {
			return k, true
		}
	}
	return "", false
}

// ---------------------------------------------------------------------------
// Profit tracker
// ---------------------------------------------------------------------------

func (s *Server) tracker(ctx context.Context, r *http.Request) (*render.Doc, render.HTMLOptions, error) {
	d := &render.Doc{Title: "Profit tracker", Path: "/tracker", NoIndex: true,
		Subtitle: "A private ledger of your trades."}

	d.Add(render.Form{
		Action: "/tracker", Method: "post", Prompt: "Record a trade",
		Fields: []render.Field{
			{Name: "item", Label: "Item ID", Kind: "number"},
			{Name: "side", Label: "Side", Kind: "select", Options: []render.Option{
				{Value: "buy", Label: "bought"}, {Value: "sell", Label: "sold"}}},
			{Name: "qty", Label: "Quantity", Kind: "number", Value: "1"},
			{Name: "price", Label: "Price each", Kind: "number"},
			{Name: "note", Label: "Note"},
		},
		Submit: "Record",
	})

	tok, ok := tokenFrom(r)
	if !ok {
		d.Add(render.Para{Muted: true, Text: "Recording your first trade creates a restore code automatically."})
		return d, render.HTMLOptions{}, nil
	}

	st, err := s.db.Profit(ctx, tok.Hash())
	if err != nil {
		return nil, render.HTMLOptions{}, err
	}
	d.Add(render.Facts{Title: "Totals", Pairs: []render.KV{
		{Key: "Trades recorded", Value: render.GP(int64(st.Trades))},
		{Key: "Distinct items", Value: render.GP(int64(st.Items))},
		{Key: "Spent buying", Value: render.GP(st.Bought)},
		{Key: "Received selling", Value: render.GP(st.Sold), Hint: "after GE tax"},
		{Key: "GE tax paid", Value: render.GP(st.TaxPaid)},
		{Key: "Realised profit", Value: render.GP(st.Realised), Tone: render.Tone(st.Realised)},
	}})

	entries, err := s.db.Ledger(ctx, tok.Hash(), 200)
	if err != nil {
		return nil, render.HTMLOptions{}, err
	}
	t := render.Table{
		Caption: "Trades",
		Empty:   "No trades recorded yet.",
		Columns: []render.Column{
			{Title: "When", Retro: true},
			{Title: "Item", Retro: true},
			{Title: "Side", Retro: true},
			{Title: "Qty", Align: render.AlignRight, Retro: true},
			{Title: "Each", Align: render.AlignRight, Retro: true},
			{Title: "Tax", Align: render.AlignRight},
			{Title: "Net", Align: render.AlignRight, Retro: true},
		},
	}
	for _, e := range entries {
		t.Rows = append(t.Rows, []render.Cell{
			render.C(e.TS.UTC().Format("2006-01-02 15:04")),
			render.CL(e.ItemName, views.ItemPath(e.ItemID)),
			render.C(e.Side),
			render.C(render.GP(e.Qty)),
			render.C(render.GP(e.UnitPrice)),
			render.C(render.GP(e.TaxPaid)),
			render.Cell{Text: render.GP(e.Total()), Tone: render.Tone(e.Total())},
		})
	}
	d.Add(t)

	d.Add(render.Heading{Level: 2, Text: "Import from RuneLite"})
	d.Add(render.Form{
		Action: "/tracker/import", Method: "post",
		Prompt: "Paste RuneLite's exported trade CSV. Expected columns: time, item id, quantity, price, buy/sell.",
		Fields: []render.Field{{Name: "csv", Label: "CSV"}},
		Submit: "Import",
	})

	if st.Trades > 0 {
		d.Add(render.Links{Items: []render.Link{
			{Text: "Clear the ledger", Href: "/tracker/clear", Desc: "deletes every recorded trade"},
		}})
	}

	d.Note("Realised profit is money received minus money spent.")
	d.Note("Your ledger is private.")
	return d, render.HTMLOptions{}, nil
}

func (s *Server) postLedger(w http.ResponseWriter, r *http.Request) {
	tok, ok := s.requireToken(w, r)
	if !ok {
		http.Error(w, "too many new tokens from this address; try again later", http.StatusTooManyRequests)
		return
	}
	itemID, err := strconv.Atoi(r.FormValue("item"))
	if err != nil {
		http.Error(w, "bad item id", http.StatusBadRequest)
		return
	}
	qty, _ := strconv.ParseInt(r.FormValue("qty"), 10, 64)
	price, _ := strconv.ParseInt(r.FormValue("price"), 10, 64)
	if qty <= 0 || price < 0 {
		http.Error(w, "quantity and price must be positive", http.StatusBadRequest)
		return
	}
	side := r.FormValue("side")
	e := store.LedgerEntry{
		ItemID: itemID, Side: side, Qty: qty, UnitPrice: price,
		Note: strings.TrimSpace(r.FormValue("note")),
	}
	// Compute the tax ourselves rather than trusting a typed figure: it is derivable, and a wrong one would quietly corrupt the profit total.
	if side == "sell" {
		e.TaxPaid = calc.Tax(itemID, price) * qty
	}
	err = s.db.AddLedger(r.Context(), tok.Hash(), e, s.cfg.Limits.LedgerRows)
	if errors.Is(err, store.ErrLimit) {
		http.Error(w, err.Error(), http.StatusConflict)
		return
	}
	if err != nil {
		s.log.Error("add ledger", "err", err)
		http.Error(w, "could not record", http.StatusInternalServerError)
		return
	}
	http.Redirect(w, r, "/tracker", http.StatusSeeOther)
}

// clearLedgerPage is the confirmation step for emptying the ledger.
//
// A separate page rather than a button on /tracker, matching /forget: the site ships no JavaScript, so there is no confirm() dialog to fall back on, and wiping a hand-kept ledger on one stray click would be unrecoverable.
func (s *Server) clearLedgerPage(ctx context.Context, r *http.Request) (*render.Doc, render.HTMLOptions, error) {
	d := &render.Doc{Title: "Clear the ledger", Path: "/tracker/clear", NoIndex: true}
	tok, ok := tokenFrom(r)
	if !ok {
		d.Add(render.Para{Text: "There are no trades stored for this browser."})
		return d, render.HTMLOptions{}, nil
	}
	st, err := s.db.Profit(ctx, tok.Hash())
	if err != nil {
		return nil, render.HTMLOptions{}, err
	}
	if st.Trades == 0 {
		d.Add(render.Para{Text: "Your ledger is already empty."})
		return d, render.HTMLOptions{}, nil
	}
	d.Add(render.Para{Text: fmt.Sprintf("This deletes all %s recorded trades and the totals worked out from them. "+
		"It cannot be undone.", render.GP(int64(st.Trades)))})
	d.Add(render.Para{Muted: true, Text: "Your favourites, preferences, alerts and restore code are left alone."})
	d.Add(render.Form{Action: "/tracker/clear", Method: "post", Submit: "Clear the ledger"})
	return d, render.HTMLOptions{}, nil
}

func (s *Server) postClearLedger(w http.ResponseWriter, r *http.Request) {
	// No token means nothing to clear; deliberately not requireToken, which would mint one just to delete nothing from it.
	if tok, ok := tokenFrom(r); ok {
		if err := s.db.ClearLedger(r.Context(), tok.Hash()); err != nil {
			s.log.Error("clear ledger", "err", err)
			http.Error(w, "could not clear the ledger", http.StatusInternalServerError)
			return
		}
	}
	http.Redirect(w, r, "/tracker", http.StatusSeeOther)
}

// postImport ingests a pasted RuneLite trade export.
func (s *Server) postImport(w http.ResponseWriter, r *http.Request) {
	tok, ok := s.requireToken(w, r)
	if !ok {
		http.Error(w, "too many new tokens from this address; try again later", http.StatusTooManyRequests)
		return
	}
	body := r.FormValue("csv")
	n, skipped := 0, 0
	for _, line := range strings.Split(body, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		f := strings.Split(line, ",")
		if len(f) < 5 {
			skipped++
			continue
		}
		for i := range f {
			f[i] = strings.TrimSpace(strings.Trim(f[i], `"`))
		}
		itemID, err1 := strconv.Atoi(f[1])
		qty, err2 := strconv.ParseInt(f[2], 10, 64)
		price, err3 := strconv.ParseInt(f[3], 10, 64)
		if err1 != nil || err2 != nil || err3 != nil {
			skipped++ // header row or a line we do not understand
			continue
		}
		side := strings.ToLower(f[4])
		if side != "buy" && side != "sell" {
			skipped++
			continue
		}
		ts := time.Now()
		if sec, err := strconv.ParseInt(f[0], 10, 64); err == nil && sec > 0 {
			ts = time.Unix(sec, 0)
		} else if t, err := time.Parse(time.RFC3339, f[0]); err == nil {
			ts = t
		}
		e := store.LedgerEntry{ItemID: itemID, Side: side, Qty: qty, UnitPrice: price, TS: ts, Note: "runelite"}
		if side == "sell" {
			e.TaxPaid = calc.Tax(itemID, price) * qty
		}
		if err := s.db.AddLedger(r.Context(), tok.Hash(), e, s.cfg.Limits.LedgerRows); err != nil {
			if errors.Is(err, store.ErrLimit) {
				break
			}
			skipped++
			continue
		}
		n++
	}
	s.log.Info("runelite import", "imported", n, "skipped", skipped)
	http.Redirect(w, r, "/tracker", http.StatusSeeOther)
}

// ---------------------------------------------------------------------------
// Alerts
// ---------------------------------------------------------------------------

func (s *Server) alertsPage(ctx context.Context, r *http.Request) (*render.Doc, render.HTMLOptions, error) {
	d := &render.Doc{Title: "Price alerts", Path: "/alerts", NoIndex: true,
		Subtitle: "Watch a price and get a feed telling when it moves."}

	var condOpts []render.Option
	for _, c := range store.AlertConditions {
		condOpts = append(condOpts, render.Option{Value: c.Key, Label: c.Label})
	}
	d.Add(render.Form{
		Action: "/alerts", Method: "post", Prompt: "Add an alert",
		Fields: []render.Field{
			{Name: "item", Label: "Item ID", Kind: "number"},
			{Name: "cond", Label: "When the", Kind: "select", Options: condOpts},
			{Name: "threshold", Label: "Threshold", Kind: "number"},
		},
		Submit: "Add alert",
	})

	tok, ok := tokenFrom(r)
	if !ok {
		d.Add(render.Para{Muted: true, Text: "Adding your first alert creates a restore code automatically."})
		return d, render.HTMLOptions{}, nil
	}

	alerts, err := s.db.Alerts(ctx, tok.Hash())
	if err != nil {
		return nil, render.HTMLOptions{}, err
	}
	t := render.Table{
		Caption: "Your alerts",
		Empty:   "No alerts set.",
		Columns: []render.Column{
			{Title: "Item", Retro: true, RowHeader: true},
			{Title: "Condition", Retro: true},
			{Title: "Threshold", Align: render.AlignRight, Retro: true},
			{Title: "Last fired", Retro: true},
		},
	}
	for _, a := range alerts {
		label := a.Condition
		for _, c := range store.AlertConditions {
			if c.Key == a.Condition {
				label = c.Label
			}
		}
		fired := render.Cell{Text: "never"}
		if !a.LastFired.IsZero() {
			fired = render.Cell{Text: render.Ago(a.LastFired), At: a.LastFired}
		}
		t.Rows = append(t.Rows, []render.Cell{
			render.CL(a.ItemName, views.ItemPath(a.ItemID)),
			render.C(label),
			render.C(render.GP(int64(a.Threshold))),
			fired,
		})
	}
	d.Add(t)

	events, err := s.db.AlertEvents(ctx, tok.Hash(), 30)
	if err != nil {
		return nil, render.HTMLOptions{}, err
	}
	et := render.Table{
		Caption: "Recently triggered",
		Empty:   "Nothing has triggered yet.",
		Columns: []render.Column{
			{Title: "When", Retro: true},
			{Title: "What", Retro: true},
		},
	}
	for _, e := range events {
		et.Rows = append(et.Rows, []render.Cell{
			render.Cell{Text: render.Ago(e.FiredAt), At: e.FiredAt}, render.C(e.Message),
		})
	}
	d.Add(et)

	feed := s.cfg.BaseURL + "/u/" + tok.Reveal() + "/alerts.xml"
	d.Add(render.Facts{Title: "Your private feed", Pairs: []render.KV{
		{Key: "Atom URL", Value: feed},
	}})
	d.Note("An alert fires once when its condition becomes true, and re-arms after it stops being true.")
	return d, render.HTMLOptions{}, nil
}

func (s *Server) postAlert(w http.ResponseWriter, r *http.Request) {
	tok, ok := s.requireToken(w, r)
	if !ok {
		http.Error(w, "too many new tokens from this address; try again later", http.StatusTooManyRequests)
		return
	}
	if id, err := strconv.ParseInt(r.FormValue("delete"), 10, 64); err == nil && id > 0 {
		if err := s.db.DeleteAlert(r.Context(), tok.Hash(), id); err != nil {
			s.log.Error("delete alert", "err", err)
		}
		http.Redirect(w, r, "/alerts", http.StatusSeeOther)
		return
	}
	itemID, err := strconv.Atoi(r.FormValue("item"))
	if err != nil {
		http.Error(w, "bad item id", http.StatusBadRequest)
		return
	}
	threshold, err := strconv.ParseFloat(r.FormValue("threshold"), 64)
	if err != nil {
		http.Error(w, "bad threshold", http.StatusBadRequest)
		return
	}
	err = s.db.AddAlert(r.Context(), tok.Hash(), itemID, r.FormValue("cond"), threshold, s.cfg.Limits.Alerts)
	if errors.Is(err, store.ErrLimit) {
		http.Error(w, err.Error(), http.StatusConflict)
		return
	}
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	http.Redirect(w, r, "/alerts", http.StatusSeeOther)
}

// ---------------------------------------------------------------------------
// Atom feed
// ---------------------------------------------------------------------------

type atomFeed struct {
	XMLName xml.Name    `xml:"http://www.w3.org/2005/Atom feed"`
	Title   string      `xml:"title"`
	ID      string      `xml:"id"`
	Updated string      `xml:"updated"`
	Link    []atomLink  `xml:"link"`
	Entries []atomEntry `xml:"entry"`
}

type atomLink struct {
	Rel  string `xml:"rel,attr"`
	Href string `xml:"href,attr"`
}

type atomEntry struct {
	Title   string   `xml:"title"`
	ID      string   `xml:"id"`
	Updated string   `xml:"updated"`
	Link    atomLink `xml:"link"`
	Summary string   `xml:"summary"`
}

func (s *Server) alertFeed(w http.ResponseWriter, r *http.Request) {
	tok, err := ident.Parse(r.PathValue("code"))
	if err != nil {
		http.NotFound(w, r)
		return
	}
	ctx := r.Context()
	events, err := s.db.AlertEvents(ctx, tok.Hash(), 50)
	if err != nil {
		s.log.Error("alert feed", "err", err)
		http.Error(w, "feed unavailable", http.StatusInternalServerError)
		return
	}

	// The URL is a bearer credential. Keep it out of search engines and out of any intermediary cache.
	w.Header().Set("X-Robots-Tag", "noindex, nofollow")
	w.Header().Set("Cache-Control", "private, no-store")
	w.Header().Set("Content-Type", "application/atom+xml; charset=utf-8")

	base := s.cfg.BaseURL
	f := atomFeed{
		Title:   "OpenGET price alerts",
		ID:      base + "/u/" + tok.Hash()[:16] + "/alerts",
		Updated: time.Now().UTC().Format(time.RFC3339),
		Link: []atomLink{
			{Rel: "self", Href: base + "/u/" + tok.Reveal() + "/alerts.xml"},
			{Rel: "alternate", Href: base + "/alerts"},
		},
	}
	for _, e := range events {
		f.Entries = append(f.Entries, atomEntry{
			Title:   e.Message,
			ID:      fmt.Sprintf("%s/alert/%d", base, e.ID),
			Updated: e.FiredAt.UTC().Format(time.RFC3339),
			Link:    atomLink{Rel: "alternate", Href: base + views.ItemPath(e.ItemID)},
			Summary: e.Message,
		})
	}
	if len(f.Entries) == 0 {
		f.Entries = append(f.Entries, atomEntry{
			Title:   "No alerts have triggered yet",
			ID:      base + "/alert/none",
			Updated: f.Updated,
			Link:    atomLink{Rel: "alternate", Href: base + "/alerts"},
			Summary: "This feed will fill in when one of your alerts fires.",
		})
	}
	fmt.Fprint(w, xml.Header)
	enc := xml.NewEncoder(w)
	enc.Indent("", "  ")
	if err := enc.Encode(f); err != nil {
		s.log.Error("atom encode", "err", err)
	}
}
