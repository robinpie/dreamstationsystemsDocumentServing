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

// Package wiki is a client for the OSRS Wiki real-time prices API
// (https://prices.runescape.wiki/api/v1/osrs). It refuses to start without a
// descriptive User-Agent, since upstream's acceptable-use policy blocks
// default library UAs, and every request goes through a shared rate limiter
// to stay polite to a free, volunteer-run service.
package wiki

import (
	"compress/gzip"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"
)

// DefaultBase is the v1 API root. v2 also answers 200 but v1 is the documented, stable one — stay on v1.
const DefaultBase = "https://prices.runescape.wiki/api/v1/osrs"

// bannedUA matches User-Agent strings the upstream policy rejects. We check locally so a misconfiguration fails at startup rather than as a wall of 403s an hour into a backfill.
var bannedUA = []string{"go-http-client", "python-requests", "curl/", "java/", "wget", "okhttp", "scrapy", "libwww", "postman"}

// Client talks to the prices API. Safe for concurrent use.
type Client struct {
	base  string
	ua    string
	hc    *http.Client
	limit *limiter

	mu    sync.Mutex
	etags map[string]etagEntry // path -> last ETag + decoded-at
}

type etagEntry struct {
	etag string
	seen time.Time
}

// Options configures a Client.
type Options struct {
	Base      string        // API root; DefaultBase if empty
	UserAgent string        // required, must identify us and carry contact info
	MinGap    time.Duration // minimum spacing between requests (politeness)
	Timeout   time.Duration // per-request timeout
}

// New returns a Client, or an error if the User-Agent would violate upstream's acceptable-use policy.
func New(o Options) (*Client, error) {
	ua := strings.TrimSpace(o.UserAgent)
	if ua == "" {
		return nil, errors.New("wiki: User-Agent is required by the upstream acceptable-use policy")
	}
	if len(ua) < 12 || !strings.ContainsAny(ua, "@.") {
		return nil, fmt.Errorf("wiki: User-Agent %q carries no contact info; upstream policy requires one", ua)
	}
	low := strings.ToLower(ua)
	for _, b := range bannedUA {
		if strings.Contains(low, b) {
			return nil, fmt.Errorf("wiki: User-Agent %q looks like a default library UA, which upstream blocks", ua)
		}
	}
	base := o.Base
	if base == "" {
		base = DefaultBase
	}
	gap := o.MinGap
	if gap <= 0 {
		gap = 500 * time.Millisecond
	}
	to := o.Timeout
	if to <= 0 {
		to = 60 * time.Second
	}
	return &Client{
		base:  strings.TrimRight(base, "/"),
		ua:    ua,
		hc:    &http.Client{Timeout: to},
		limit: newLimiter(gap),
		etags: map[string]etagEntry{},
	}, nil
}

// UserAgent reports the UA this client sends. Used by /about pages so the value we advertise is provably the value we send.
func (c *Client) UserAgent() string { return c.ua }

// ErrNotModified is returned when a conditional request got a 304. Callers that just want to skip a poll cycle can treat it as a no-op.
var ErrNotModified = errors.New("wiki: not modified")

// get fetches path (e.g. "/latest") relative to the prices API root and decodes JSON into v. If cond is true the request is conditional on the previously-seen ETag and may return ErrNotModified.
func (c *Client) get(ctx context.Context, path string, cond bool, v any) error {
	return c.getURL(ctx, c.base+path, path, cond, v)
}

// getURL is get against a fully-qualified URL, for the endpoints that do not hang off the prices root. key names the request in error messages and in the ETag cache, so a long bucket query and a prices path can never collide there.
func (c *Client) getURL(ctx context.Context, url, key string, cond bool, v any) error {
	var lastErr error
	// Three attempts with backoff. Upstream is Cloudflare-fronted and occasionally 5xxs or rate-limits; a transient blip should not abort a 40-minute backfill.
	for attempt := 0; attempt < 3; attempt++ {
		if attempt > 0 {
			wait := time.Duration(1<<attempt) * time.Second
			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-time.After(wait):
			}
		}
		if err := c.limit.wait(ctx); err != nil {
			return err
		}
		err := c.once(ctx, url, key, cond, v)
		if err == nil || errors.Is(err, ErrNotModified) || errors.Is(err, context.Canceled) {
			return err
		}
		var he *HTTPError
		// 4xx other than 429 is our fault (bad id, bad timestep) — retrying just annoys a volunteer-run service.
		if errors.As(err, &he) && he.Status >= 400 && he.Status < 500 && he.Status != 429 {
			return err
		}
		lastErr = err
	}
	return lastErr
}

// HTTPError is a non-2xx response.
type HTTPError struct {
	Status int
	Path   string
	Body   string
}

func (e *HTTPError) Error() string {
	b := e.Body
	if len(b) > 200 {
		b = b[:200] + "..."
	}
	return fmt.Sprintf("wiki: GET %s: HTTP %d: %s", e.Path, e.Status, b)
}

func (c *Client) once(ctx context.Context, url, key string, cond bool, v any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	req.Header.Set("User-Agent", c.ua)
	req.Header.Set("Accept", "application/json")
	// Ask for gzip explicitly rather than letting the transport do it, so we can log real wire bytes. /mapping is 861 KB raw and compresses well.
	req.Header.Set("Accept-Encoding", "gzip")
	if cond {
		c.mu.Lock()
		e, ok := c.etags[key]
		c.mu.Unlock()
		if ok && e.etag != "" {
			req.Header.Set("If-None-Match", e.etag)
		}
	}

	resp, err := c.hc.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotModified {
		return ErrNotModified
	}
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		return &HTTPError{Status: resp.StatusCode, Path: key, Body: strings.TrimSpace(string(b))}
	}

	var r io.Reader = resp.Body
	if strings.EqualFold(resp.Header.Get("Content-Encoding"), "gzip") {
		gz, err := gzip.NewReader(resp.Body)
		if err != nil {
			return fmt.Errorf("wiki: gzip %s: %w", key, err)
		}
		defer gz.Close()
		r = gz
	}
	if err := json.NewDecoder(r).Decode(v); err != nil {
		return fmt.Errorf("wiki: decode %s: %w", key, err)
	}
	if tag := resp.Header.Get("ETag"); tag != "" {
		c.mu.Lock()
		c.etags[key] = etagEntry{etag: tag, seen: time.Now()}
		c.mu.Unlock()
	}
	return nil
}

// ---------------------------------------------------------------------------
// Payload types
// ---------------------------------------------------------------------------

// Item is one entry of /mapping: static-ish metadata that only changes on game updates. Limit and Value are pointers because they are genuinely absent for some items (507 of 4650 carry no buy limit), and "absent" must not collapse to "zero" — a zero buy limit would mean untradeable, which is a different claim entirely.
type Item struct {
	ID       int    `json:"id"`
	Name     string `json:"name"`
	Examine  string `json:"examine"`
	Members  bool   `json:"members"`
	LowAlch  *int   `json:"lowalch"`
	HighAlch *int   `json:"highalch"`
	Limit    *int   `json:"limit"` // 4-hour GE buy limit
	Value    *int   `json:"value"`
	Icon     string `json:"icon"` // wiki image filename, e.g. "Abyssal whip.png"
}

// Latest is one entry of /latest.
//
// High is the highest instant-BUY price: what you pay to buy right now. Low is the lowest instant-SELL price: what you receive selling right now. Either may be null if the item has never been observed trading.
type Latest struct {
	High     *int64 `json:"high"`
	HighTime *int64 `json:"highTime"`
	Low      *int64 `json:"low"`
	LowTime  *int64 `json:"lowTime"`
}

// Avg is one entry of the /5m, /1h, /6h and /24h bucket endpoints.
type Avg struct {
	AvgHighPrice    *int64 `json:"avgHighPrice"`
	HighPriceVolume int64  `json:"highPriceVolume"`
	AvgLowPrice     *int64 `json:"avgLowPrice"`
	LowPriceVolume  int64  `json:"lowPriceVolume"`
}

// Bucket is a whole bucket-endpoint response.
type Bucket struct {
	Timestamp int64          `json:"timestamp"`
	Data      map[string]Avg `json:"data"`
}

// TimePoint is one point of /timeseries.
type TimePoint struct {
	Timestamp       int64  `json:"timestamp"`
	AvgHighPrice    *int64 `json:"avgHighPrice"`
	HighPriceVolume int64  `json:"highPriceVolume"`
	AvgLowPrice     *int64 `json:"avgLowPrice"`
	LowPriceVolume  int64  `json:"lowPriceVolume"`
}

// ---------------------------------------------------------------------------
// Endpoints
// ---------------------------------------------------------------------------

// Mapping fetches /mapping: 4650 items, ~861 KB. Poll daily; it only changes on game updates.
func (c *Client) Mapping(ctx context.Context) ([]Item, error) {
	var out []Item
	if err := c.get(ctx, "/mapping", true, &out); err != nil {
		return nil, err
	}
	return out, nil
}

// Latest fetches /latest for every item, keyed by item id.
func (c *Client) Latest(ctx context.Context) (map[int]Latest, error) {
	var raw struct {
		Data map[string]Latest `json:"data"`
	}
	if err := c.get(ctx, "/latest", true, &raw); err != nil {
		return nil, err
	}
	return keyByID(raw.Data), nil
}

// Timestep is a bucket size understood by the bucket and timeseries endpoints.
type Timestep string

const (
	Step5m  Timestep = "5m"
	Step1h  Timestep = "1h"
	Step6h  Timestep = "6h"  // undocumented but works; best-effort
	Step24h Timestep = "24h" // undocumented but works; best-effort
)

// Valid reports whether t is a timestep the API accepts.
func (t Timestep) Valid() bool {
	switch t {
	case Step5m, Step1h, Step6h, Step24h:
		return true
	}
	return false
}

// Seconds is the wall-clock width of one bucket.
func (t Timestep) Seconds() int64 {
	switch t {
	case Step5m:
		return 300
	case Step1h:
		return 3600
	case Step6h:
		return 21600
	case Step24h:
		return 86400
	}
	return 0
}

// Bucket fetches /5m, /1h, /6h or /24h. If at is non-zero the specific historical bucket at that unix time is requested instead of the current one.
//
// Note /6h and /24h are not in the published docs but do respond; treat them as best-effort and never build anything load-bearing on them alone.
func (c *Client) Bucket(ctx context.Context, step Timestep, at int64) (*Bucket, error) {
	if !step.Valid() {
		return nil, fmt.Errorf("wiki: bad timestep %q", step)
	}
	path := "/" + string(step)
	if at > 0 {
		path += "?timestamp=" + strconv.FormatInt(at, 10)
	}
	var out Bucket
	// Historical buckets are immutable, so a conditional request is pointless there; the live bucket is worth an ETag.
	if err := c.get(ctx, path, at == 0, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// Volumes fetches /volumes: total traded volume per item. Undocumented but stable in practice.
func (c *Client) Volumes(ctx context.Context) (int64, map[int]int64, error) {
	var raw struct {
		Timestamp int64            `json:"timestamp"`
		Data      map[string]int64 `json:"data"`
	}
	if err := c.get(ctx, "/volumes", true, &raw); err != nil {
		return 0, nil, err
	}
	return raw.Timestamp, keyByID(raw.Data), nil
}

// MaxTimeseriesPoints is the hard cap the API applies to /timeseries
// regardless of timestep, which is what makes our own archive valuable: the
// window you can ever re-fetch is 365 * timestep. See openget.txt.
const MaxTimeseriesPoints = 365

// Timeseries fetches per-item history. Returns at most MaxTimeseriesPoints points, so the timestep chooses the window:
//
//	5m  -> 365 pts ->   1.3 days
//	1h  -> 365 pts ->  15.2 days
//	6h  -> 365 pts ->  91.0 days
//	24h -> 365 pts -> 364.0 days
//
// This is the one-time history bootstrap, not a steady-state call. Live data comes from the bulk bucket endpoints, which cover every item in one request.
func (c *Client) Timeseries(ctx context.Context, id int, step Timestep) ([]TimePoint, error) {
	if !step.Valid() {
		return nil, fmt.Errorf("wiki: bad timestep %q", step)
	}
	var raw struct {
		Data []TimePoint `json:"data"`
	}
	path := "/timeseries?timestep=" + string(step) + "&id=" + strconv.Itoa(id)
	if err := c.get(ctx, path, false, &raw); err != nil {
		return nil, err
	}
	return raw.Data, nil
}

// keyByID converts the API's string-keyed maps to int keys, dropping any key that is not a number (none observed, but the decode should not panic if one ever appears).
func keyByID[T any](in map[string]T) map[int]T {
	out := make(map[int]T, len(in))
	for k, v := range in {
		id, err := strconv.Atoi(k)
		if err != nil {
			continue
		}
		out[id] = v
	}
	return out
}

// ---------------------------------------------------------------------------
// Rate limiting
// ---------------------------------------------------------------------------

// limiter spaces requests by at least gap. Deliberately a plain mutex+clock rather than a token bucket: we never want a burst allowance, because the only thing a burst buys us is being rude to a service run by volunteers.
type limiter struct {
	mu   sync.Mutex
	gap  time.Duration
	next time.Time
}

func newLimiter(gap time.Duration) *limiter { return &limiter{gap: gap} }

func (l *limiter) wait(ctx context.Context) error {
	l.mu.Lock()
	now := time.Now()
	if l.next.Before(now) {
		l.next = now
	}
	at := l.next
	l.next = at.Add(l.gap)
	l.mu.Unlock()

	d := time.Until(at)
	if d <= 0 {
		return nil
	}
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-t.C:
		return nil
	}
}
