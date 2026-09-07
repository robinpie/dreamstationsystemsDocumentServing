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

// Package ingest runs the pollers, the one-time historical backfill, and the
// nightly rollup and prune. This is the part of OpenGET that matters most:
// upstream's /timeseries endpoint returns at most 365 points at any timestep,
// so a day not ingesting is a day of 5m history lost permanently.
package ingest

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"math"
	"path/filepath"
	"sync"
	"time"

	"dreamstation.systems/openget/internal/config"
	"dreamstation.systems/openget/internal/store"
	"dreamstation.systems/openget/internal/wiki"
	"golang.org/x/sys/unix"
)

// Ingester owns every background job.
type Ingester struct {
	db  *store.DB
	api *wiki.Client
	cfg config.Config
	log *slog.Logger

	mu       sync.Mutex
	paused   bool // set when free disk falls below the floor
	pauseWhy string

	// OnStats fires after each successful stats recomputation, so the retro frontends can regenerate without polling the database on a timer. An error from it is logged, never fatal: a failed gophermap write must not take down price ingestion.
	OnStats func(context.Context) error
}

// New builds an Ingester.
func New(db *store.DB, api *wiki.Client, cfg config.Config, log *slog.Logger) *Ingester {
	return &Ingester{db: db, api: api, cfg: cfg, log: log}
}

// Run starts every job and blocks until ctx is cancelled.
func (in *Ingester) Run(ctx context.Context) {
	var wg sync.WaitGroup

	// The mapping poll must land before anything else: every other table has a foreign key into items, so a first run with an empty items table would discard an entire /latest response.
	if err := in.Mapping(ctx); err != nil {
		in.log.Error("initial mapping poll failed; other pollers will skip unknown ids until it succeeds", "err", err)
	}

	jobs := []struct {
		name  string
		every time.Duration
		fn    func(context.Context) error
	}{
		{"latest", in.cfg.Poll.Latest.Duration, in.Latest},
		{"5m", in.cfg.Poll.FiveMin.Duration, func(c context.Context) error { return in.BucketPoll(c, wiki.Step5m) }},
		{"1h", in.cfg.Poll.Hourly.Duration, func(c context.Context) error { return in.BucketPoll(c, wiki.Step1h) }},
		{"24h", in.cfg.Poll.Daily.Duration, func(c context.Context) error { return in.BucketPoll(c, wiki.Step24h) }},
		{"volumes", in.cfg.Poll.Volumes.Duration, in.Volumes},
		{"mapping", in.cfg.Poll.Daily.Duration, in.Mapping},
		{"shops", in.cfg.Poll.Daily.Duration, in.Shops},
	}
	for _, j := range jobs {
		if j.every <= 0 {
			continue
		}
		wg.Add(1)
		go func(name string, every time.Duration, fn func(context.Context) error) {
			defer wg.Done()
			in.loop(ctx, name, every, fn)
		}(j.name, j.every, j.fn)
	}

	wg.Add(1)
	go func() { defer wg.Done(); in.maintenanceLoop(ctx) }()

	if in.cfg.Backfill.Enabled {
		wg.Add(1)
		go func() { defer wg.Done(); in.backfillLoop(ctx) }()
	}

	wg.Wait()
}

// loop runs fn every `every`, aligned so the 5m poll lands just after the upstream bucket closes rather than at an arbitrary offset from process start. Jitter keeps us from hitting the CDN on the exact second every time.
func (in *Ingester) loop(ctx context.Context, name string, every time.Duration, fn func(context.Context) error) {
	// First run immediately (minus mapping, already done in Run).
	if name != "mapping" {
		in.runJob(ctx, name, fn)
	}
	for {
		wait := untilNext(time.Now(), every)
		t := time.NewTimer(wait)
		select {
		case <-ctx.Done():
			t.Stop()
			return
		case <-t.C:
		}
		in.runJob(ctx, name, fn)
	}
}

// untilNext returns the delay to the next tick boundary of `every`, plus a small settling offset so we read a bucket after upstream has published it.
func untilNext(now time.Time, every time.Duration) time.Duration {
	if every < time.Minute {
		return every
	}
	// Align to wall-clock boundaries, then wait 20s for the bucket to appear.
	const settle = 20 * time.Second
	next := now.Truncate(every).Add(every).Add(settle)
	if !next.After(now) {
		next = next.Add(every)
	}
	return next.Sub(now)
}

func (in *Ingester) runJob(ctx context.Context, name string, fn func(context.Context) error) {
	if why, paused := in.pauseState(); paused {
		in.log.Warn("ingestion paused, skipping job", "job", name, "reason", why)
		return
	}
	start := time.Now()
	id, err := in.db.StartRun(ctx, name)
	if err != nil {
		in.log.Error("could not record run start", "job", name, "err", err)
	}
	err = fn(ctx)
	dur := time.Since(start)
	note := ""
	if err != nil {
		note = err.Error()
	}
	if id > 0 {
		if e := in.db.FinishRun(ctx, id, err == nil, 0, note); e != nil {
			in.log.Error("could not record run end", "job", name, "err", e)
		}
	}
	switch {
	case err == nil:
		in.log.Info("poll ok", "job", name, "dur", dur.Round(time.Millisecond))
	case errors.Is(err, context.Canceled):
		// shutting down
	default:
		in.log.Error("poll failed", "job", name, "dur", dur.Round(time.Millisecond), "err", err)
	}
}

// ---------------------------------------------------------------------------
// Individual jobs
// ---------------------------------------------------------------------------

// Mapping refreshes the item catalogue. It only changes on game updates, so daily is generous.
func (in *Ingester) Mapping(ctx context.Context) error {
	items, err := in.api.Mapping(ctx)
	if errors.Is(err, wiki.ErrNotModified) {
		in.log.Debug("mapping unchanged")
		return nil
	}
	if err != nil {
		return err
	}
	n, err := in.db.UpsertItems(ctx, items, time.Now())
	if err != nil {
		return err
	}
	in.log.Info("mapping updated", "items", n)
	return nil
}

// Latest refreshes the hot price table and then recomputes item_stats, which is what every list view reads.
func (in *Ingester) Latest(ctx context.Context) error {
	data, err := in.api.Latest(ctx)
	if errors.Is(err, wiki.ErrNotModified) {
		return nil
	}
	if err != nil {
		return err
	}
	if _, err := in.db.UpsertLatest(ctx, data, time.Now()); err != nil {
		return err
	}
	return in.Recompute(ctx)
}

// Recompute rebuilds item_stats, samples the market indices, and fires OnStats.
func (in *Ingester) Recompute(ctx context.Context) error {
	if _, err := in.db.ComputeStats(ctx, time.Now()); err != nil {
		return err
	}
	// Index readings are sampled hourly rather than every minute: they are a long-horizon signal, and a point per minute would be 500k rows a year per index to draw exactly the same line.
	bucket := time.Now().Truncate(time.Hour).Unix()
	if err := in.db.RecordIndexPoints(ctx, bucket); err != nil {
		in.log.Warn("index sampling failed", "err", err)
	}
	// Alerts are evaluated here rather than on a timer of their own, so a firing can never be based on a price the site is not already showing.
	if n, err := in.db.EvaluateAlerts(ctx, time.Now()); err != nil {
		in.log.Warn("alert evaluation failed", "err", err)
	} else if n > 0 {
		in.log.Info("alerts fired", "count", n)
	}
	if in.OnStats != nil {
		if err := in.OnStats(ctx); err != nil {
			in.log.Error("post-stats hook failed", "err", err)
		}
	}
	return nil
}

// BucketPoll fetches one bulk bucket endpoint.
//
// One /5m call every five minutes covers every actively-traded item in about 150 KB. There is never a reason to loop /latest?id= across thousands of items when one unfiltered call gets the lot.
func (in *Ingester) BucketPoll(ctx context.Context, step wiki.Timestep) error {
	b, err := in.api.Bucket(ctx, step, 0)
	if errors.Is(err, wiki.ErrNotModified) {
		return nil
	}
	if err != nil {
		return err
	}
	table := string(step)
	if step == wiki.Step6h {
		return nil // 6h is derived on read, not stored
	}
	n, err := in.db.UpsertBucket(ctx, table, b)
	if err != nil {
		return err
	}
	in.log.Debug("bucket stored", "step", table, "bucket", b.Timestamp, "rows", n)
	return nil
}

// MetaShopsFetched is the meta key holding when shop inventories were last read. Exposed so /store-profit can date its own data.
const MetaShopsFetched = "shops_fetched_at"

// Shops refreshes what each shop in the game stocks, from the wiki's storeline bucket.
//
// A second upstream, and the only one that is not the prices API: shop inventories are not price data and nothing in the real-time feed carries them. Two requests — the data changes on game updates, not on trades.
//
// A failure here is survivable. The previous fetch stays in the table and /store-profit keeps working on it, which is why this returns its error to the job runner rather than taking anything down.
func (in *Ingester) Shops(ctx context.Context) error { return in.shops(ctx, false) }

// ShopsNow refetches regardless of how recent the stored copy is. This is what `-once shops` runs, because the reason to ask for it by hand is usually that data/shops.toml just changed.
func (in *Ingester) ShopsNow(ctx context.Context) error { return in.shops(ctx, true) }

func (in *Ingester) shops(ctx context.Context, force bool) error {
	// Every job in the table runs once at startup. For a daily job against a wiki that changes weekly, that turns a restart loop into a stream of pointless requests, so skip when the stored copy is still young.
	if !force {
		last, err := in.db.GetMetaTime(ctx, MetaShopsFetched)
		if err == nil && !last.IsZero() && time.Since(last) < in.cfg.Poll.Daily.Duration {
			if n, err := in.db.ShopOfferCount(ctx); err == nil && n > 0 {
				in.log.Debug("shop offers still fresh, skipping fetch",
					"age", time.Since(last).Round(time.Minute), "offers", n)
				return nil
			}
		}
	}

	lines, err := in.api.StoreLines(ctx)
	if err != nil {
		return err
	}
	// Read the exclusions each time rather than caching them at startup, so correcting a bad shop is an edit and a re-run, not a restart.
	ex := store.ShopExclusions{}
	if in.cfg.DataDir != "" {
		ex, err = store.LoadShopExclusions(filepath.Join(in.cfg.DataDir, "shops.toml"))
		if err != nil {
			return err
		}
	}
	now := time.Now()
	stored, dropped, err := in.db.ReplaceShopOffers(ctx, lines, ex, now)
	if err != nil {
		return err
	}
	if stored == 0 {
		// Items were not loaded yet, so nothing was written and nothing was destroyed. Do not stamp the clock, or the freshness guard would suppress the retry.
		in.log.Warn("shop offers not stored: the items table is still empty")
		return nil
	}
	if err := in.db.SetMetaTime(ctx, MetaShopsFetched, now); err != nil {
		in.log.Warn("could not record shop fetch time", "err", err)
	}
	in.log.Info("shop offers updated", "offers", stored, "rows", len(lines),
		"unusable", dropped, "excluded_shops", len(ex))
	return nil
}

// Volumes records the undocumented /volumes snapshot. Stored under its own name and never presented as a 24-hour figure — see store.ComputeStats for why the two disagree.
func (in *Ingester) Volumes(ctx context.Context) error {
	ts, data, err := in.api.Volumes(ctx)
	if errors.Is(err, wiki.ErrNotModified) {
		return nil
	}
	if err != nil {
		return err
	}
	_, err = in.db.UpsertVolumes(ctx, ts, data)
	return err
}

// ---------------------------------------------------------------------------
// Historical backfill
// ---------------------------------------------------------------------------

// backfillLoop seeds history from per-item /timeseries calls.
//
// This is a one-time operation, not steady state: roughly 4650 requests to seed a year of daily history. At the default 2 requests/second that is about 40 minutes, spread across batches with a pause between them. Items are taken most-traded-first, so an interrupted backfill still leaves the items people actually look up complete.
func (in *Ingester) backfillLoop(ctx context.Context) {
	for _, step := range in.cfg.Backfill.Steps {
		if !wiki.Timestep(step).Valid() {
			in.log.Error("ignoring unknown backfill step", "step", step)
			continue
		}
		if step == "6h" {
			// 6h has no table; its history would have nowhere to go.
			in.log.Warn("skipping 6h backfill: the 6h view is derived from prices_1h on read")
			continue
		}
		in.backfillStep(ctx, step)
		if ctx.Err() != nil {
			return
		}
	}
	done, total, _ := in.db.BackfillProgress(ctx, "24h")
	in.log.Info("backfill complete", "step", "24h", "items", done, "of", total)
}

func (in *Ingester) backfillStep(ctx context.Context, step string) {
	gap := time.Duration(float64(time.Second) / in.cfg.Backfill.RatePerSec)
	for {
		if ctx.Err() != nil {
			return
		}
		if why, paused := in.pauseState(); paused {
			in.log.Warn("backfill paused", "reason", why)
			if !sleepCtx(ctx, 10*time.Minute) {
				return
			}
			continue
		}
		ids, err := in.db.PendingBackfill(ctx, step, in.cfg.Backfill.BatchSize)
		if err != nil {
			in.log.Error("backfill: could not list pending items", "step", step, "err", err)
			return
		}
		if len(ids) == 0 {
			return
		}
		done, total, _ := in.db.BackfillProgress(ctx, step)
		in.log.Info("backfill pass starting", "step", step, "batch", len(ids), "done", done, "of", total)

		for _, id := range ids {
			if ctx.Err() != nil {
				return
			}
			pts, err := in.api.Timeseries(ctx, id, wiki.Timestep(step))
			if err != nil {
				if errors.Is(err, context.Canceled) {
					return
				}
				in.log.Warn("backfill: timeseries failed", "item", id, "step", step, "err", err)
				// Mark it done anyway so one permanently broken id cannot wedge the loop forever; a later re-run can clear backfill_state.
				_ = in.db.MarkBackfilled(ctx, step, id, 0)
				continue
			}
			n, err := in.db.UpsertTimeseries(ctx, step, id, pts)
			if err != nil {
				in.log.Error("backfill: store failed", "item", id, "err", err)
				continue
			}
			if err := in.db.MarkBackfilled(ctx, step, id, n); err != nil {
				in.log.Error("backfill: bookkeeping failed", "item", id, "err", err)
			}
			if !sleepCtx(ctx, gap) {
				return
			}
		}
		if !sleepCtx(ctx, in.cfg.Backfill.Pause.Duration) {
			return
		}
	}
}

// ---------------------------------------------------------------------------
// Maintenance: rollup, prune, disk guard
// ---------------------------------------------------------------------------

func (in *Ingester) maintenanceLoop(ctx context.Context) {
	in.checkDisk(ctx)
	// Disk is checked far more often than the nightly job runs, because the consequence of missing a full disk is worse than the cost of a statfs.
	diskTick := time.NewTicker(5 * time.Minute)
	defer diskTick.Stop()

	for {
		wait := untilNextNightly(time.Now())
		t := time.NewTimer(wait)
		select {
		case <-ctx.Done():
			t.Stop()
			return
		case <-diskTick.C:
			t.Stop()
			in.checkDisk(ctx)
			continue
		case <-t.C:
		}
		in.runJob(ctx, "maintenance", in.Maintenance)
	}
}

// untilNextNightly returns the delay to the next 03:17 UTC. An odd minute keeps us off the same second as every other cron on the internet.
func untilNextNightly(now time.Time) time.Duration {
	n := now.UTC()
	next := time.Date(n.Year(), n.Month(), n.Day(), 3, 17, 0, 0, time.UTC)
	if !next.After(n) {
		next = next.Add(24 * time.Hour)
	}
	return next.Sub(n)
}

// Maintenance rolls finer tiers up into coarser ones, prunes to the retention policy, and compacts.
func (in *Ingester) Maintenance(ctx context.Context) error {
	now := time.Now()

	// Roll up from the last two windows, so a bucket that was still open at the previous run gets recomputed with its full set of contributions.
	if n, err := in.db.Rollup(ctx, "5m", "1h", now.Add(-48*time.Hour).Unix()); err != nil {
		return fmt.Errorf("rollup 5m->1h: %w", err)
	} else if n > 0 {
		in.log.Info("rollup filled gaps", "from", "5m", "to", "1h", "rows", n)
	}
	if n, err := in.db.Rollup(ctx, "1h", "24h", now.Add(-14*24*time.Hour).Unix()); err != nil {
		return fmt.Errorf("rollup 1h->24h: %w", err)
	} else if n > 0 {
		in.log.Info("rollup filled gaps", "from", "1h", "to", "24h", "rows", n)
	}

	// Prune only after the rollups, so nothing is deleted before the coarser tier has had its chance to absorb it.
	type tier struct {
		step string
		keep time.Duration
	}
	for _, t := range []tier{
		{"5m", in.cfg.Retention.FiveMin.Duration},
		{"1h", in.cfg.Retention.Hourly.Duration},
		{"24h", in.cfg.Retention.Daily.Duration},
	} {
		if t.keep <= 0 {
			continue // keep forever
		}
		n, err := in.db.Prune(ctx, t.step, now.Add(-t.keep).Unix())
		if err != nil {
			return fmt.Errorf("prune %s: %w", t.step, err)
		}
		if n > 0 {
			in.log.Info("pruned", "tier", t.step, "rows", n, "keeping", t.keep)
		}
	}
	if k := in.cfg.Retention.Volumes.Duration; k > 0 {
		if n, err := in.db.PruneVolumes(ctx, now.Add(-k).Unix()); err != nil {
			return fmt.Errorf("prune volumes: %w", err)
		} else if n > 0 {
			in.log.Info("pruned volumes", "rows", n)
		}
	}

	if err := in.db.TrimRuns(ctx, 2000); err != nil {
		in.log.Warn("could not trim poll_runs", "err", err)
	}
	// Retire tokens nobody has touched in a year, and everything attached to them. Announced on the site as a privacy feature, which is what it is: data that expires on its own cannot be leaked later.
	if keep := in.cfg.Limits.PruneAfter.Duration; keep > 0 {
		if n, err := in.db.PruneTokens(ctx, now.Add(-keep).Unix()); err != nil {
			in.log.Warn("could not prune tokens", "err", err)
		} else if n > 0 {
			in.log.Info("pruned dormant tokens", "count", n, "idle_for", keep)
		}
	}
	if err := in.db.Optimize(ctx); err != nil {
		in.log.Warn("PRAGMA optimize failed", "err", err)
	}
	if err := in.db.Checkpoint(ctx); err != nil {
		in.log.Warn("WAL checkpoint failed", "err", err)
	}
	in.checkDisk(ctx)
	return nil
}

// checkDisk pauses or resumes ingestion based on free space.
//
// The archive is irreplaceable, which is exactly why this exists: an unattended poller that fills the root filesystem takes down NTP, mail and everything else on the box, and a dead box records nothing at all.
func (in *Ingester) checkDisk(ctx context.Context) {
	floor := in.cfg.Retention.MinFreeDiskMB
	if floor <= 0 {
		return
	}
	var st unix.Statfs_t
	if err := unix.Statfs(in.db.Path(), &st); err != nil {
		in.log.Warn("statfs failed; disk guard inactive", "err", err)
		return
	}
	freeMB := int64(st.Bavail) * int64(st.Bsize) / (1 << 20)

	in.mu.Lock()
	was := in.paused
	if freeMB < floor {
		in.paused = true
		in.pauseWhy = fmt.Sprintf("only %d MB free on the volume holding %s (floor is %d MB)", freeMB, in.db.Path(), floor)
	} else {
		in.paused = false
		in.pauseWhy = ""
	}
	now, why := in.paused, in.pauseWhy
	in.mu.Unlock()

	switch {
	case now && !was:
		in.log.Error("PAUSING INGESTION: low disk", "free_mb", freeMB, "floor_mb", floor, "db", in.db.Path())
	case !now && was:
		in.log.Info("resuming ingestion: disk recovered", "free_mb", freeMB)
	default:
		_ = why
	}
}

func (in *Ingester) pauseState() (string, bool) {
	in.mu.Lock()
	defer in.mu.Unlock()
	return in.pauseWhy, in.paused
}

// Paused reports whether ingestion is currently held off, for /status.
func (in *Ingester) Paused() (string, bool) { return in.pauseState() }

// FreeDiskMB reports free space on the database's filesystem.
func (in *Ingester) FreeDiskMB() int64 {
	var st unix.Statfs_t
	if err := unix.Statfs(in.db.Path(), &st); err != nil {
		return -1
	}
	return int64(st.Bavail) * int64(st.Bsize) / (1 << 20)
}

// sleepCtx sleeps for d, returning false if ctx was cancelled first.
func sleepCtx(ctx context.Context, d time.Duration) bool {
	if d <= 0 {
		return ctx.Err() == nil
	}
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
		return false
	case <-t.C:
		return true
	}
}

// EstimateRows projects archive growth, used by the status page so the retention knobs can be tuned against a real number rather than a guess.
func EstimateRows(activeItems int, keep time.Duration, bucket time.Duration) int64 {
	if bucket <= 0 || keep <= 0 {
		return 0
	}
	return int64(math.Round(float64(activeItems) * (float64(keep) / float64(bucket))))
}
