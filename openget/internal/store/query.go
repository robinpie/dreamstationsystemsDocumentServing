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

package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"

	"dreamstation.systems/openget/internal/calc"
)

// ErrNotFound is returned when a lookup matches no row.
var ErrNotFound = errors.New("store: not found")

// Item is an item joined with its cached statistics. Nullable columns are pointers so "not observed" stays distinguishable from "zero" all the way out to the templates — an item nobody has traded must not render as costing 0 gp.
type Item struct {
	ID       int
	Name     string
	Examine  string
	Members  bool
	LowAlch  *int64
	HighAlch *int64
	BuyLimit *int
	Value    *int64
	Icon     string
	Removed  bool

	High      *int64
	Low       *int64
	HighTime  *int64
	LowTime   *int64
	Margin    *int64
	MarginPct *float64
	ROIPct    *float64
	Potential *int64
	Tax       *int64
	AvgVol24h int64
	DailyGPV  int64
	Change1h  *float64
	Change24h *float64
	Change7d  *float64
	Change30d *float64
	AlchProf  *int64

	LastComputed int64
}

// Exempt reports whether this item pays GE tax.
func (i *Item) Exempt() bool { return calc.IsExempt(i.ID) }

// Limit is the buy limit, or 0 when the API reports none.
func (i *Item) Limit() int {
	if i.BuyLimit == nil {
		return 0
	}
	return *i.BuyLimit
}

const itemCols = `
	i.id, i.name, i.examine, i.members, i.lowalch, i.highalch, i.buy_limit,
	i.value, i.icon, i.removed,
	s.high, s.low, s.high_time, s.low_time, s.margin, s.margin_pct, s.roi_pct,
	s.potential_profit, s.tax, COALESCE(s.avg_vol_24h,0), COALESCE(s.daily_gp_vol,0),
	s.change_1h, s.change_24h, s.change_7d, s.change_30d, s.alch_profit,
	COALESCE(s.last_computed,0)`

func scanItem(rows interface{ Scan(...any) error }) (*Item, error) {
	var it Item
	var members, removed int
	err := rows.Scan(
		&it.ID, &it.Name, &it.Examine, &members, &it.LowAlch, &it.HighAlch,
		&it.BuyLimit, &it.Value, &it.Icon, &removed,
		&it.High, &it.Low, &it.HighTime, &it.LowTime, &it.Margin, &it.MarginPct,
		&it.ROIPct, &it.Potential, &it.Tax, &it.AvgVol24h, &it.DailyGPV,
		&it.Change1h, &it.Change24h, &it.Change7d, &it.Change30d, &it.AlchProf,
		&it.LastComputed)
	if err != nil {
		return nil, err
	}
	it.Members = members != 0
	it.Removed = removed != 0
	return &it, nil
}

// GetItem loads one item by id.
func (d *DB) GetItem(ctx context.Context, id int) (*Item, error) {
	row := d.r.QueryRowContext(ctx,
		`SELECT `+itemCols+` FROM items i LEFT JOIN item_stats s ON s.item_id = i.id WHERE i.id = ?`, id)
	it, err := scanItem(row)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	return it, err
}

// GetItemByName loads one item by exact (case-insensitive) name.
func (d *DB) GetItemByName(ctx context.Context, name string) (*Item, error) {
	row := d.r.QueryRowContext(ctx,
		`SELECT `+itemCols+` FROM items i LEFT JOIN item_stats s ON s.item_id = i.id
		 WHERE i.name = ? COLLATE NOCASE ORDER BY i.removed, i.id LIMIT 1`, name)
	it, err := scanItem(row)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	return it, err
}

// ---------------------------------------------------------------------------
// Listing
// ---------------------------------------------------------------------------

// sortColumns maps a public sort key to SQL. Whitelisted rather than interpolated, since the key arrives from a query string.
var sortColumns = map[string]string{
	"name":       "i.name COLLATE NOCASE",
	"id":         "i.id",
	"price":      "s.high",
	"high":       "s.high",
	"low":        "s.low",
	"margin":     "s.margin",
	"margin_pct": "s.margin_pct",
	"roi":        "s.roi_pct",
	"potential":  "s.potential_profit",
	"volume":     "s.avg_vol_24h",
	"gpvol":      "s.daily_gp_vol",
	"alch":       "s.alch_profit",
	// No precomputed column needed: the rune cost is the same for every item, so ranking by (alch value - buy price) ranks by profit regardless of today's rune price.
	"alch_low":  "(i.lowalch - s.high)",
	"limit":     "i.buy_limit",
	"value":     "i.value",
	"highalch":  "i.highalch",
	"change1h":  "s.change_1h",
	"change24h": "s.change_24h",
	"change7d":  "s.change_7d",
	"change30d": "s.change_30d",
	"tax":       "s.tax",
	"newest":    "i.first_seen",
}

// SortKeys lists the accepted sort keys, for validation and the UI.
func SortKeys() []string {
	out := make([]string, 0, len(sortColumns))
	for k := range sortColumns {
		out = append(out, k)
	}
	return out
}

// ListOptions filters and orders an item list.
type ListOptions struct {
	Query       string // substring match on name
	Sort        string // key from sortColumns
	Desc        bool
	MembersOnly bool
	F2POnly     bool
	MinVolume   int64
	MinPrice    int64
	MaxPrice    int64
	MinMargin   int64
	HasLimit    bool // only items with a known buy limit
	Tradeable   bool // only items with both prices observed
	// MaxAge, when set, drops items whose last observed buy or sell print is
	// older than this many seconds — without it, stale prices on one side
	// of the book can produce enormous fake margins.
	MaxAge         int64
	Favourites     string // token hash; empty means no favourites filter
	IncludeRemoved bool
	Limit          int
	Offset         int
}

// ListItems runs a filtered, sorted, paginated item query and also reports the total matching count (for pagination) in one round trip each.
func (d *DB) ListItems(ctx context.Context, o ListOptions) ([]*Item, int, error) {
	var where []string
	var args []any

	if !o.IncludeRemoved {
		where = append(where, "i.removed = 0")
	}
	if q := strings.TrimSpace(o.Query); q != "" {
		where = append(where, "i.name LIKE ? ESCAPE '\\' COLLATE NOCASE")
		args = append(args, "%"+escapeLike(q)+"%")
	}
	if o.MembersOnly {
		where = append(where, "i.members = 1")
	}
	if o.F2POnly {
		where = append(where, "i.members = 0")
	}
	if o.MinVolume > 0 {
		where = append(where, "COALESCE(s.avg_vol_24h,0) >= ?")
		args = append(args, o.MinVolume)
	}
	if o.MinPrice > 0 {
		where = append(where, "s.high >= ?")
		args = append(args, o.MinPrice)
	}
	if o.MaxPrice > 0 {
		where = append(where, "s.high <= ?")
		args = append(args, o.MaxPrice)
	}
	if o.MinMargin != 0 {
		where = append(where, "s.margin >= ?")
		args = append(args, o.MinMargin)
	}
	if o.HasLimit {
		where = append(where, "i.buy_limit IS NOT NULL AND i.buy_limit > 0")
	}
	if o.Tradeable {
		where = append(where, "s.high IS NOT NULL AND s.low IS NOT NULL")
	}
	if o.MaxAge > 0 {
		cutoff := time.Now().Unix() - o.MaxAge
		where = append(where, "s.high_time >= ? AND s.low_time >= ?")
		args = append(args, cutoff, cutoff)
	}
	join := ""
	if o.Favourites != "" {
		join = " JOIN favourites f ON f.item_id = i.id AND f.token_hash = ?"
		args = append([]any{o.Favourites}, args...)
	}

	clause := ""
	if len(where) > 0 {
		clause = " WHERE " + strings.Join(where, " AND ")
	}
	base := `FROM items i LEFT JOIN item_stats s ON s.item_id = i.id` + join + clause

	var total int
	if err := d.r.QueryRowContext(ctx, `SELECT count(*) `+base, args...).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("store: count items: %w", err)
	}

	col, ok := sortColumns[o.Sort]
	if !ok {
		col = sortColumns["margin"]
	}
	dir := "ASC"
	if o.Desc {
		dir = "DESC"
	}
	// NULLs always sort last regardless of direction: an item with no observed margin is not the best flip on the site, and it is not the worst either — it simply has no answer, so it belongs at the bottom of either view.
	order := fmt.Sprintf("ORDER BY (%s IS NULL), %s %s, i.id", col, col, dir)

	limit := o.Limit
	if limit <= 0 || limit > 500 {
		limit = 100
	}
	q := `SELECT ` + itemCols + ` ` + base + ` ` + order + ` LIMIT ? OFFSET ?`
	rows, err := d.r.QueryContext(ctx, q, append(args, limit, max(0, o.Offset))...)
	if err != nil {
		return nil, 0, fmt.Errorf("store: list items: %w", err)
	}
	defer rows.Close()

	var out []*Item
	for rows.Next() {
		it, err := scanItem(rows)
		if err != nil {
			return nil, 0, err
		}
		out = append(out, it)
	}
	return out, total, rows.Err()
}

// SearchItems does a prefix-first name search: exact match, then prefix, then substring. Cheap enough at 4650 rows that a real FTS index would be a solution looking for a problem.
//
// f2pOnly drops members' items, for the site-wide free-to-play toggle.
func (d *DB) SearchItems(ctx context.Context, q string, limit int, f2pOnly bool) ([]*Item, error) {
	q = strings.TrimSpace(q)
	if q == "" {
		return nil, nil
	}
	if limit <= 0 || limit > 200 {
		limit = 25
	}
	members := ""
	if f2pOnly {
		members = " AND i.members = 0"
	}
	esc := escapeLike(q)
	rows, err := d.r.QueryContext(ctx, `
		SELECT `+itemCols+`,
		       CASE WHEN i.name = ?1 COLLATE NOCASE THEN 0
		            WHEN i.name LIKE ?2 ESCAPE '\' COLLATE NOCASE THEN 1
		            ELSE 2 END AS rank
		  FROM items i LEFT JOIN item_stats s ON s.item_id = i.id
		 WHERE i.name LIKE ?3 ESCAPE '\' COLLATE NOCASE`+members+`
		 ORDER BY rank, i.removed, COALESCE(s.daily_gp_vol,0) DESC, i.name
		 LIMIT ?4`, q, esc+"%", "%"+esc+"%", limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []*Item
	for rows.Next() {
		var it Item
		var members, removed, rank int
		if err := rows.Scan(&it.ID, &it.Name, &it.Examine, &members, &it.LowAlch,
			&it.HighAlch, &it.BuyLimit, &it.Value, &it.Icon, &removed,
			&it.High, &it.Low, &it.HighTime, &it.LowTime, &it.Margin, &it.MarginPct,
			&it.ROIPct, &it.Potential, &it.Tax, &it.AvgVol24h, &it.DailyGPV,
			&it.Change1h, &it.Change24h, &it.Change7d, &it.Change30d, &it.AlchProf,
			&it.LastComputed, &rank); err != nil {
			return nil, err
		}
		it.Members = members != 0
		it.Removed = removed != 0
		out = append(out, &it)
	}
	return out, rows.Err()
}

// escapeLike neutralises LIKE wildcards in user input so a search for "50%" does not turn into a match-everything query.
func escapeLike(s string) string {
	r := strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`)
	return r.Replace(s)
}

// ---------------------------------------------------------------------------
// Price history
// ---------------------------------------------------------------------------

// Point is one charted observation.
type Point struct {
	TS      int64
	High    *int64
	Low     *int64
	HighVol int64
	LowVol  int64
}

// Series loads price history for one item at a timestep, oldest first.
//
// The 6h timestep has no table of its own: it is aggregated from prices_1h on read. Storing a fourth tier to serve one chart toggle would cost disk every day to save a GROUP BY over at most a few thousand rows.
func (d *DB) Series(ctx context.Context, itemID int, step string, since int64, limit int) ([]Point, error) {
	var q string
	switch step {
	case "6h":
		q = `SELECT (bucket_ts/21600)*21600 AS b,
		            CASE WHEN sum(CASE WHEN avg_high IS NOT NULL THEN high_vol ELSE 0 END) > 0
		                 THEN sum(CASE WHEN avg_high IS NOT NULL THEN avg_high*high_vol ELSE 0 END)
		                      / sum(CASE WHEN avg_high IS NOT NULL THEN high_vol ELSE 0 END)
		                 ELSE avg(avg_high) END,
		            CASE WHEN sum(CASE WHEN avg_low IS NOT NULL THEN low_vol ELSE 0 END) > 0
		                 THEN sum(CASE WHEN avg_low IS NOT NULL THEN avg_low*low_vol ELSE 0 END)
		                      / sum(CASE WHEN avg_low IS NOT NULL THEN low_vol ELSE 0 END)
		                 ELSE avg(avg_low) END,
		            sum(high_vol), sum(low_vol)
		       FROM prices_1h WHERE item_id = ? AND bucket_ts >= ?
		      GROUP BY b ORDER BY b LIMIT ?`
	default:
		table, err := tableFor(step)
		if err != nil {
			return nil, err
		}
		q = `SELECT bucket_ts, avg_high, avg_low, high_vol, low_vol
		       FROM ` + table + ` WHERE item_id = ? AND bucket_ts >= ?
		      ORDER BY bucket_ts LIMIT ?`
	}
	if limit <= 0 || limit > 20000 {
		limit = 5000
	}
	rows, err := d.r.QueryContext(ctx, q, itemID, since, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []Point
	for rows.Next() {
		var p Point
		var hi, lo sql.NullFloat64
		if err := rows.Scan(&p.TS, &hi, &lo, &p.HighVol, &p.LowVol); err != nil {
			return nil, err
		}
		if hi.Valid {
			v := int64(hi.Float64)
			p.High = &v
		}
		if lo.Valid {
			v := int64(lo.Float64)
			p.Low = &v
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

// ---------------------------------------------------------------------------
// Stats recomputation
// ---------------------------------------------------------------------------

// ComputeStats rebuilds item_stats for every item.
//
// Done entirely in SQL rather than pulling 4650 items into Go and looping,
// which would be several seconds of work every five minutes. avg_vol_24h is
// summed from our own 5m/1h archive rather than the upstream /volumes endpoint.
//
// refWindow bounds how far before a lookback target we will accept a reference
// price, so a thinly-traded item doesn't get compared against a month-old print.
const refWindow int64 = 86400

func (d *DB) ComputeStats(ctx context.Context, now time.Time) (int64, error) {
	nowTS := now.Unix()
	exemptList := joinIDs(calc.ExemptIDs())

	// A nature rune price for the alch column; if unobserved, treat as 0 so the column overstates rather than silently vanishes.
	var nature int64
	_ = d.r.QueryRowContext(ctx,
		`SELECT COALESCE(high, low, 0) FROM latest WHERE item_id = ?`, calc.NatureRuneID).Scan(&nature)

	// "The price N ago" is the price in the LAST 1h bucket at or before now-N,
	// not max(price) over that period (which would turn every spike into a
	// permanent "down 40%") — relies on SQLite's rule that with one max() in
	// the query, bare columns come from the row that produced it. Each
	// lookback is floored so a thinly-traded item yields NULL rather than a
	// change measured against a stale price.
	ref := func(alias string, ago int64) string {
		return fmt.Sprintf(`
	LEFT JOIN (
		SELECT item_id, COALESCE(avg_high, avg_low) AS px, max(bucket_ts) AS bts
		  FROM prices_1h
		 WHERE bucket_ts <= %[2]d - %[3]d AND bucket_ts >= %[2]d - %[3]d - %[4]d
		 GROUP BY item_id
	) %[1]s ON %[1]s.item_id = m.item_id`, alias, nowTS, ago, refWindow)
	}

	q := fmt.Sprintf(`
	WITH base AS (
		SELECT i.id AS item_id, l.high, l.low, l.high_time, l.low_time,
		       i.buy_limit, i.highalch,
		       CASE WHEN l.high IS NULL     THEN NULL
		            WHEN i.id IN (%[1]s)    THEN 0
		            WHEN l.high * 2 / 100 > %[4]d THEN %[4]d
		            ELSE l.high * 2 / 100 END AS tax
		  FROM items i LEFT JOIN latest l ON l.item_id = i.id
		 WHERE i.removed = 0
	),
	m AS (
		SELECT *, CASE WHEN high IS NULL OR low IS NULL THEN NULL
		               ELSE high - tax - low END AS margin
		  FROM base
	)
	INSERT INTO item_stats (
		item_id, high, low, margin, margin_pct, roi_pct, potential_profit, tax,
		avg_vol_24h, daily_gp_vol, change_1h, change_24h, change_7d, change_30d,
		high_time, low_time, alch_profit, last_computed)
	SELECT
		m.item_id, m.high, m.low, m.margin,
		CASE WHEN m.margin IS NULL OR m.high = 0 THEN NULL ELSE m.margin * 100.0 / m.high END,
		CASE WHEN m.margin IS NULL OR m.low  = 0 THEN NULL ELSE m.margin * 100.0 / m.low  END,
		CASE WHEN m.margin IS NULL OR m.buy_limit IS NULL THEN NULL
		     ELSE m.margin * m.buy_limit END,
		m.tax,
		COALESCE(v.vol, 0),
		COALESCE(v.vol, 0) * COALESCE(m.high, m.low, 0),
		CASE WHEN r1h.px  IS NULL OR r1h.px  = 0 OR m.high IS NULL THEN NULL
		     ELSE (COALESCE(m.high,m.low) - r1h.px)  * 100.0 / r1h.px  END,
		CASE WHEN r24h.px IS NULL OR r24h.px = 0 OR m.high IS NULL THEN NULL
		     ELSE (COALESCE(m.high,m.low) - r24h.px) * 100.0 / r24h.px END,
		CASE WHEN r7d.px  IS NULL OR r7d.px  = 0 OR m.high IS NULL THEN NULL
		     ELSE (COALESCE(m.high,m.low) - r7d.px)  * 100.0 / r7d.px  END,
		CASE WHEN r30d.px IS NULL OR r30d.px = 0 OR m.high IS NULL THEN NULL
		     ELSE (COALESCE(m.high,m.low) - r30d.px) * 100.0 / r30d.px END,
		m.high_time, m.low_time,
		CASE WHEN m.highalch IS NULL OR m.high IS NULL THEN NULL
		     ELSE m.highalch - %[2]d - m.high END,
		%[3]d
	FROM m
	LEFT JOIN (
		SELECT item_id, sum(high_vol + low_vol) AS vol
		  FROM prices_1h WHERE bucket_ts >= %[3]d - 86400
		 GROUP BY item_id
	) v ON v.item_id = m.item_id`+
		ref("r1h", 3600)+ref("r24h", 86400)+ref("r7d", 604800)+ref("r30d", 2592000)+`
	WHERE 1
	ON CONFLICT(item_id) DO UPDATE SET
		high=excluded.high, low=excluded.low, margin=excluded.margin,
		margin_pct=excluded.margin_pct, roi_pct=excluded.roi_pct,
		potential_profit=excluded.potential_profit, tax=excluded.tax,
		avg_vol_24h=excluded.avg_vol_24h, daily_gp_vol=excluded.daily_gp_vol,
		change_1h=excluded.change_1h, change_24h=excluded.change_24h,
		change_7d=excluded.change_7d, change_30d=excluded.change_30d,
		high_time=excluded.high_time, low_time=excluded.low_time,
		alch_profit=excluded.alch_profit, last_computed=excluded.last_computed`,
		exemptList, nature, nowTS, calc.TaxCap)

	res, err := d.w.ExecContext(ctx, q)
	if err != nil {
		return 0, fmt.Errorf("store: compute stats: %w", err)
	}
	return res.RowsAffected()
}

// ---------------------------------------------------------------------------
// Misc reads
// ---------------------------------------------------------------------------

// NewestItems lists items first seen most recently — ge-tracker's "new items" finder. first_seen is when WE first saw it, which for items that predate the archive is simply the first mapping poll; the page says so.
func (d *DB) NewestItems(ctx context.Context, limit int) ([]*Item, error) {
	items, _, err := d.ListItems(ctx, ListOptions{Sort: "newest", Desc: true, Limit: limit})
	return items, err
}

// MembersItems reports which of the given ids are members-only items.
//
// The money-maker calculators need this: a recipe has no members flag of its own, so "is this method free-to-play" is answered by asking whether every item it touches is.
func (d *DB) MembersItems(ctx context.Context, ids []int) (map[int]bool, error) {
	out := map[int]bool{}
	if len(ids) == 0 {
		return out, nil
	}
	rows, err := d.r.QueryContext(ctx,
		`SELECT id FROM items WHERE members = 1 AND id IN (`+joinIDs(ids)+`)`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var id int
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		out[id] = true
	}
	return out, rows.Err()
}

// LatestFetch reports when /latest was last written.
func (d *DB) LatestFetch(ctx context.Context) (time.Time, error) {
	var ts sql.NullInt64
	err := d.r.QueryRowContext(ctx, `SELECT max(fetched_at) FROM latest`).Scan(&ts)
	if err != nil || !ts.Valid {
		return time.Time{}, err
	}
	return time.Unix(ts.Int64, 0), nil
}

// ArchiveSpan reports the oldest and newest bucket in a tier — the headline "how much history do we actually own" number.
func (d *DB) ArchiveSpan(ctx context.Context, step string) (oldest, newest time.Time, rows int64, err error) {
	table, err := tableFor(step)
	if err != nil {
		return
	}
	var lo, hi sql.NullInt64
	err = d.r.QueryRowContext(ctx,
		`SELECT min(bucket_ts), max(bucket_ts), count(*) FROM `+table).Scan(&lo, &hi, &rows)
	if err != nil {
		return
	}
	if lo.Valid {
		oldest = time.Unix(lo.Int64, 0)
	}
	if hi.Valid {
		newest = time.Unix(hi.Int64, 0)
	}
	return
}

// Run is one row of poll_runs.
type Run struct {
	Job     string
	Started time.Time
	Ended   time.Time
	OK      bool
	Rows    int
	Note    string
}

// RecentRuns lists the most recent job runs for the status page.
func (d *DB) RecentRuns(ctx context.Context, limit int) ([]Run, error) {
	rows, err := d.r.QueryContext(ctx,
		`SELECT job, started_at, ended_at, ok, rows, note FROM poll_runs ORDER BY id DESC LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Run
	for rows.Next() {
		var r Run
		var started int64
		var ended, ok sql.NullInt64
		if err := rows.Scan(&r.Job, &started, &ended, &ok, &r.Rows, &r.Note); err != nil {
			return nil, err
		}
		r.Started = time.Unix(started, 0)
		if ended.Valid {
			r.Ended = time.Unix(ended.Int64, 0)
		}
		r.OK = ok.Valid && ok.Int64 == 1
		out = append(out, r)
	}
	return out, rows.Err()
}

// LatestVolume returns the most recent upstream /volumes figure for an item. Reported under its own name, never as "24h volume" — see ComputeStats.
func (d *DB) LatestVolume(ctx context.Context, itemID int) (int64, time.Time, error) {
	var vol, ts int64
	err := d.r.QueryRowContext(ctx,
		`SELECT volume, ts FROM volumes WHERE item_id = ? ORDER BY ts DESC LIMIT 1`, itemID).Scan(&vol, &ts)
	if errors.Is(err, sql.ErrNoRows) {
		return 0, time.Time{}, nil
	}
	return vol, time.Unix(ts, 0), err
}
