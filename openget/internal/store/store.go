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

// Package store owns the SQLite database: schema, migrations and every query.
// It uses modernc.org/sqlite (pure Go, no cgo) in WAL mode, matching the read-mostly, single-writer workload this runs.
package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	_ "modernc.org/sqlite"
)

// DB wraps two connection pools over one database file: a single-connection
// write pool (SQLite allows exactly one writer) and a multi-connection read pool.
type DB struct {
	r    *sql.DB // readers
	w    *sql.DB // single writer
	path string

	// The status page's row counts and archive spans, measured on a timer
	// rather than per request. See status.go.
	statsMu      sync.Mutex
	statsCounts  map[string]int64
	statsSpans   map[string]ArchiveSpanInfo
	statsAt      time.Time
	statsRunning bool
}

// pragmas applied to every connection. cache_size is deliberately modest: this box has under 1 GiB of RAM and is already into swap, so a generous per-connection page cache would cost more than it buys.
const pragmas = `
	PRAGMA journal_mode = WAL;
	PRAGMA synchronous = NORMAL;
	PRAGMA busy_timeout = 15000;
	PRAGMA foreign_keys = ON;
	PRAGMA cache_size = -8000;
	PRAGMA mmap_size = 67108864;
`

// Open opens (creating if needed) the database at path and migrates it to the current schema.
func Open(ctx context.Context, path string) (*DB, error) {
	if dir := filepath.Dir(path); dir != "" && dir != "." {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return nil, fmt.Errorf("store: mkdir %s: %w", dir, err)
		}
	}
	dsn := "file:" + path + "?_pragma=busy_timeout(15000)&_txlock=immediate"

	w, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, err
	}
	w.SetMaxOpenConns(1)
	w.SetMaxIdleConns(1)
	w.SetConnMaxLifetime(0)

	r, err := sql.Open("sqlite", dsn)
	if err != nil {
		w.Close()
		return nil, err
	}
	r.SetMaxOpenConns(4)
	r.SetMaxIdleConns(4)
	r.SetConnMaxLifetime(0)

	db := &DB{r: r, w: w, path: path}
	for _, pool := range []*sql.DB{w, r} {
		if _, err := pool.ExecContext(ctx, pragmas); err != nil {
			db.Close()
			return nil, fmt.Errorf("store: pragmas: %w", err)
		}
	}
	if err := db.migrate(ctx); err != nil {
		db.Close()
		return nil, err
	}
	return db, nil
}

// Close releases both pools.
func (d *DB) Close() error {
	var errs []error
	if d.r != nil {
		errs = append(errs, d.r.Close())
	}
	if d.w != nil {
		errs = append(errs, d.w.Close())
	}
	return errors.Join(errs...)
}

// Path is the database file location.
func (d *DB) Path() string { return d.path }

// Reader exposes the read pool for ad-hoc queries.
func (d *DB) Reader() *sql.DB { return d.r }

// Writer exposes the single-connection write pool.
func (d *DB) Writer() *sql.DB { return d.w }

// Tx runs fn inside a write transaction, rolling back on error.
func (d *DB) Tx(ctx context.Context, fn func(*sql.Tx) error) error {
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	if err := fn(tx); err != nil {
		tx.Rollback()
		return err
	}
	return tx.Commit()
}

// ---------------------------------------------------------------------------
// Migrations
// ---------------------------------------------------------------------------

// migrations are applied in order; PRAGMA user_version records how many have run. Append only — never edit a migration that has shipped.
var migrations = []string{
	// -- 1 ------------------------------------------------------------------
	// Core price archive. Price tiers are WITHOUT ROWID tables, since the
	// primary key is the row and this avoids storing every row twice.
	`
	CREATE TABLE items (
		id          INTEGER PRIMARY KEY,
		name        TEXT NOT NULL,
		examine     TEXT NOT NULL DEFAULT '',
		members     INTEGER NOT NULL DEFAULT 0,
		lowalch     INTEGER,
		highalch    INTEGER,
		buy_limit   INTEGER,          -- 4-hour GE buy limit; NULL means the
		                              -- API reports none, which is NOT zero
		value       INTEGER,
		icon        TEXT NOT NULL DEFAULT '',
		first_seen  INTEGER NOT NULL,
		last_seen   INTEGER NOT NULL, -- last /mapping that still listed it;
		                              -- delisted items keep their rows forever
		removed     INTEGER NOT NULL DEFAULT 0
	);
	CREATE INDEX items_name ON items(name COLLATE NOCASE);

	CREATE TABLE latest (
		item_id    INTEGER PRIMARY KEY REFERENCES items(id),
		high       INTEGER,
		high_time  INTEGER,
		low        INTEGER,
		low_time   INTEGER,
		fetched_at INTEGER NOT NULL
	);

	CREATE TABLE prices_5m (
		item_id   INTEGER NOT NULL,
		bucket_ts INTEGER NOT NULL,
		avg_high  INTEGER,
		high_vol  INTEGER NOT NULL DEFAULT 0,
		avg_low   INTEGER,
		low_vol   INTEGER NOT NULL DEFAULT 0,
		PRIMARY KEY (item_id, bucket_ts)
	) WITHOUT ROWID;
	CREATE INDEX prices_5m_ts ON prices_5m(bucket_ts);

	CREATE TABLE prices_1h (
		item_id   INTEGER NOT NULL,
		bucket_ts INTEGER NOT NULL,
		avg_high  INTEGER,
		high_vol  INTEGER NOT NULL DEFAULT 0,
		avg_low   INTEGER,
		low_vol   INTEGER NOT NULL DEFAULT 0,
		PRIMARY KEY (item_id, bucket_ts)
	) WITHOUT ROWID;
	CREATE INDEX prices_1h_ts ON prices_1h(bucket_ts);

	CREATE TABLE prices_24h (
		item_id   INTEGER NOT NULL,
		bucket_ts INTEGER NOT NULL,
		avg_high  INTEGER,
		high_vol  INTEGER NOT NULL DEFAULT 0,
		avg_low   INTEGER,
		low_vol   INTEGER NOT NULL DEFAULT 0,
		PRIMARY KEY (item_id, bucket_ts)
	) WITHOUT ROWID;
	CREATE INDEX prices_24h_ts ON prices_24h(bucket_ts);

	CREATE TABLE volumes (
		item_id INTEGER NOT NULL,
		ts      INTEGER NOT NULL,
		volume  INTEGER NOT NULL,
		PRIMARY KEY (item_id, ts)
	) WITHOUT ROWID;
	CREATE INDEX volumes_ts ON volumes(ts);
	`,

	// -- 2 ------------------------------------------------------------------
	// Denormalised list-view cache. Recomputed after each 5m poll; this is what makes "sort 4650 items by ROI" a single indexed scan instead of a correlated subquery per row.
	`
	CREATE TABLE item_stats (
		item_id          INTEGER PRIMARY KEY REFERENCES items(id),
		high             INTEGER,
		low              INTEGER,
		margin           INTEGER,  -- post-tax profit per item
		margin_pct       REAL,
		roi_pct          REAL,
		potential_profit INTEGER,  -- margin * buy_limit
		tax              INTEGER,
		avg_vol_24h      INTEGER NOT NULL DEFAULT 0,
		daily_gp_vol     INTEGER NOT NULL DEFAULT 0, -- volume * price, "how
		                                             -- much gp moves per day"
		change_1h        REAL,
		change_24h       REAL,
		change_7d        REAL,
		change_30d       REAL,
		high_time        INTEGER,
		low_time         INTEGER,
		alch_profit      INTEGER,  -- highalch - nature rune - buy price
		last_computed    INTEGER NOT NULL
	);
	CREATE INDEX item_stats_margin    ON item_stats(margin DESC);
	CREATE INDEX item_stats_roi       ON item_stats(roi_pct DESC);
	CREATE INDEX item_stats_potential ON item_stats(potential_profit DESC);
	CREATE INDEX item_stats_volume    ON item_stats(avg_vol_24h DESC);
	CREATE INDEX item_stats_gpvol     ON item_stats(daily_gp_vol DESC);
	CREATE INDEX item_stats_alch      ON item_stats(alch_profit DESC);
	`,

	// -- 3 ------------------------------------------------------------------
	// Operational bookkeeping: what ran, when, and how the long backfill is getting on across restarts.
	`
	CREATE TABLE meta (
		key   TEXT PRIMARY KEY,
		value TEXT NOT NULL
	);

	CREATE TABLE poll_runs (
		id         INTEGER PRIMARY KEY AUTOINCREMENT,
		job        TEXT NOT NULL,
		started_at INTEGER NOT NULL,
		ended_at   INTEGER,
		ok         INTEGER,
		rows       INTEGER NOT NULL DEFAULT 0,
		note       TEXT NOT NULL DEFAULT ''
	);
	CREATE INDEX poll_runs_job ON poll_runs(job, started_at DESC);

	CREATE TABLE backfill_state (
		step        TEXT NOT NULL,     -- '24h' | '6h' | '1h'
		item_id     INTEGER NOT NULL,
		done_at     INTEGER NOT NULL,
		points      INTEGER NOT NULL,
		PRIMARY KEY (step, item_id)
	) WITHOUT ROWID;
	`,

	// -- 4 ------------------------------------------------------------------
	// Recipes drive every money-maker calculator. Storing them as data rather than bespoke Go per calculator is what makes the long tail tractable: a new calculator is a TOML entry, and every frontend gets it at once.
	`
	CREATE TABLE recipes (
		id         TEXT PRIMARY KEY,
		kind       TEXT NOT NULL,
		name       TEXT NOT NULL,
		inputs     TEXT NOT NULL DEFAULT '[]',  -- JSON [{item_id,qty,...}]
		outputs    TEXT NOT NULL DEFAULT '[]',
		skill_reqs TEXT NOT NULL DEFAULT '',
		notes      TEXT NOT NULL DEFAULT '',
		extra      TEXT NOT NULL DEFAULT '{}',  -- JSON, per-kind knobs
		sort_key   INTEGER NOT NULL DEFAULT 0
	);
	CREATE INDEX recipes_kind ON recipes(kind, sort_key);

	CREATE TABLE indices (
		id      TEXT PRIMARY KEY,
		name    TEXT NOT NULL,
		blurb   TEXT NOT NULL DEFAULT '',
		members TEXT NOT NULL DEFAULT '[]'      -- JSON [{item_id,weight}]
	);

	CREATE TABLE index_points (
		index_id TEXT NOT NULL REFERENCES indices(id),
		ts       INTEGER NOT NULL,
		value    REAL NOT NULL,
		PRIMARY KEY (index_id, ts)
	) WITHOUT ROWID;
	`,

	// -- 5 ------------------------------------------------------------------
	// Identity without accounts. We store only SHA-256(token); the plaintext lives solely in the user's cookie, so a leaked database yields no usable tokens.
	`
	CREATE TABLE tokens (
		token_hash TEXT PRIMARY KEY,
		created    INTEGER NOT NULL,
		last_seen  INTEGER NOT NULL,
		label      TEXT NOT NULL DEFAULT ''
	);
	CREATE INDEX tokens_last_seen ON tokens(last_seen);

	CREATE TABLE favourites (
		token_hash TEXT NOT NULL REFERENCES tokens(token_hash) ON DELETE CASCADE,
		item_id    INTEGER NOT NULL REFERENCES items(id),
		added      INTEGER NOT NULL,
		PRIMARY KEY (token_hash, item_id)
	) WITHOUT ROWID;

	CREATE TABLE prefs (
		token_hash    TEXT PRIMARY KEY REFERENCES tokens(token_hash) ON DELETE CASCADE,
		theme         TEXT NOT NULL DEFAULT 'auto',
		default_sort  TEXT NOT NULL DEFAULT 'margin',
		columns       TEXT NOT NULL DEFAULT '',
		tz            TEXT NOT NULL DEFAULT 'UTC',
		rows_per_page INTEGER NOT NULL DEFAULT 50,
		members_only  INTEGER NOT NULL DEFAULT 0,
		min_volume    INTEGER NOT NULL DEFAULT 0
	);

	CREATE TABLE ledger (
		id         INTEGER PRIMARY KEY AUTOINCREMENT,
		token_hash TEXT NOT NULL REFERENCES tokens(token_hash) ON DELETE CASCADE,
		item_id    INTEGER NOT NULL REFERENCES items(id),
		side       TEXT NOT NULL CHECK (side IN ('buy','sell')),
		qty        INTEGER NOT NULL,
		unit_price INTEGER NOT NULL,
		tax_paid   INTEGER NOT NULL DEFAULT 0,
		ts         INTEGER NOT NULL,
		note       TEXT NOT NULL DEFAULT ''
	);
	CREATE INDEX ledger_token ON ledger(token_hash, ts DESC);
	CREATE INDEX ledger_item  ON ledger(token_hash, item_id, ts);

	CREATE TABLE alerts (
		id         INTEGER PRIMARY KEY AUTOINCREMENT,
		token_hash TEXT NOT NULL REFERENCES tokens(token_hash) ON DELETE CASCADE,
		item_id    INTEGER NOT NULL REFERENCES items(id),
		condition  TEXT NOT NULL,  -- 'high_below','high_above','low_below',
		                           -- 'low_above','margin_above','roi_above'
		threshold  REAL NOT NULL,
		active     INTEGER NOT NULL DEFAULT 1,
		created    INTEGER NOT NULL,
		last_fired INTEGER
	);
	CREATE INDEX alerts_token  ON alerts(token_hash);
	CREATE INDEX alerts_active ON alerts(active, item_id);

	CREATE TABLE alert_events (
		id         INTEGER PRIMARY KEY AUTOINCREMENT,
		token_hash TEXT NOT NULL REFERENCES tokens(token_hash) ON DELETE CASCADE,
		alert_id   INTEGER NOT NULL,
		item_id    INTEGER NOT NULL,
		fired_at   INTEGER NOT NULL,
		message    TEXT NOT NULL
	);
	CREATE INDEX alert_events_feed ON alert_events(token_hash, fired_at DESC);

	CREATE TABLE gemini_certs (
		cert_hash  TEXT PRIMARY KEY,
		token_hash TEXT NOT NULL REFERENCES tokens(token_hash) ON DELETE CASCADE,
		bound_at   INTEGER NOT NULL
	);
	CREATE INDEX gemini_certs_token ON gemini_certs(token_hash);
	`,

	// -- 6 ------------------------------------------------------------------
	// What each shop actually stocks, from the wiki's storeline bucket. One
	// row per (item, shop, price); the same shop can appear twice for one
	// item at different prices (diary discounts, quest states).
	`
	CREATE TABLE shop_offers (
		item_id    INTEGER NOT NULL REFERENCES items(id),
		shop       TEXT NOT NULL,
		price      INTEGER NOT NULL,  -- coins paid per item
		stock      INTEGER NOT NULL,  -- base stock; -1 means unlimited
		restock    TEXT NOT NULL DEFAULT '',
		notes      TEXT NOT NULL DEFAULT '',  -- shop variant: diary tier, quest state
		fetched_at INTEGER NOT NULL,
		PRIMARY KEY (item_id, shop, price)
	) WITHOUT ROWID;
	CREATE INDEX shop_offers_price ON shop_offers(item_id, price);
	`,
}

func (d *DB) migrate(ctx context.Context) error {
	var version int
	if err := d.w.QueryRowContext(ctx, "PRAGMA user_version").Scan(&version); err != nil {
		return fmt.Errorf("store: read user_version: %w", err)
	}
	if version > len(migrations) {
		return fmt.Errorf("store: database is at schema %d but this binary only knows %d — refusing to downgrade", version, len(migrations))
	}
	for i := version; i < len(migrations); i++ {
		tx, err := d.w.BeginTx(ctx, nil)
		if err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, migrations[i]); err != nil {
			tx.Rollback()
			return fmt.Errorf("store: migration %d: %w", i+1, err)
		}
		// user_version does not accept a bind parameter.
		if _, err := tx.ExecContext(ctx, fmt.Sprintf("PRAGMA user_version = %d", i+1)); err != nil {
			tx.Rollback()
			return fmt.Errorf("store: bump user_version to %d: %w", i+1, err)
		}
		if err := tx.Commit(); err != nil {
			return err
		}
	}
	return nil
}

// SchemaVersion reports how many migrations have been applied.
func (d *DB) SchemaVersion(ctx context.Context) (int, error) {
	var v int
	err := d.r.QueryRowContext(ctx, "PRAGMA user_version").Scan(&v)
	return v, err
}

// ---------------------------------------------------------------------------
// meta helpers
// ---------------------------------------------------------------------------

// GetMeta reads a meta key, returning "" if absent.
func (d *DB) GetMeta(ctx context.Context, key string) (string, error) {
	var v string
	err := d.r.QueryRowContext(ctx, `SELECT value FROM meta WHERE key = ?`, key).Scan(&v)
	if errors.Is(err, sql.ErrNoRows) {
		return "", nil
	}
	return v, err
}

// SetMeta upserts a meta key.
func (d *DB) SetMeta(ctx context.Context, key, value string) error {
	_, err := d.w.ExecContext(ctx,
		`INSERT INTO meta(key,value) VALUES(?,?)
		 ON CONFLICT(key) DO UPDATE SET value = excluded.value`, key, value)
	return err
}

// GetMetaTime reads a meta key holding a unix timestamp.
func (d *DB) GetMetaTime(ctx context.Context, key string) (time.Time, error) {
	s, err := d.GetMeta(ctx, key)
	if err != nil || s == "" {
		return time.Time{}, err
	}
	var sec int64
	if _, err := fmt.Sscan(s, &sec); err != nil {
		return time.Time{}, nil
	}
	return time.Unix(sec, 0), nil
}

// SetMetaTime writes a unix timestamp to a meta key.
func (d *DB) SetMetaTime(ctx context.Context, key string, t time.Time) error {
	return d.SetMeta(ctx, key, fmt.Sprint(t.Unix()))
}

// ---------------------------------------------------------------------------
// Maintenance
// ---------------------------------------------------------------------------

// Checkpoint truncates the WAL. Called after the nightly rollup so the -wal file does not grow without bound between restarts.
func (d *DB) Checkpoint(ctx context.Context) error {
	_, err := d.w.ExecContext(ctx, `PRAGMA wal_checkpoint(TRUNCATE)`)
	return err
}

// Optimize runs SQLite's incremental optimiser (query-planner statistics).
func (d *DB) Optimize(ctx context.Context) error {
	_, err := d.w.ExecContext(ctx, `PRAGMA optimize`)
	return err
}

// SizeOnDisk totals the database file and its sidecars.
func (d *DB) SizeOnDisk() int64 {
	var total int64
	for _, suffix := range []string{"", "-wal", "-shm"} {
		if fi, err := os.Stat(d.path + suffix); err == nil {
			total += fi.Size()
		}
	}
	return total
}

// nullInt converts a *int to a driver-friendly value.
func nullInt(p *int) any {
	if p == nil {
		return nil
	}
	return *p
}

// nullInt64 converts a *int64 to a driver-friendly value.
func nullInt64(p *int64) any {
	if p == nil {
		return nil
	}
	return *p
}

// tableFor maps a timestep to its price table, guarding against injection since the name is interpolated into SQL.
func tableFor(step string) (string, error) {
	switch step {
	case "5m":
		return "prices_5m", nil
	case "1h":
		return "prices_1h", nil
	case "24h":
		return "prices_24h", nil
	}
	return "", fmt.Errorf("store: no price table for timestep %q", step)
}

// joinIDs renders ids as a SQL list. Only ever called with values that came out of the database as integers.
func joinIDs(ids []int) string {
	var b strings.Builder
	for i, id := range ids {
		if i > 0 {
			b.WriteByte(',')
		}
		fmt.Fprint(&b, id)
	}
	return b.String()
}
