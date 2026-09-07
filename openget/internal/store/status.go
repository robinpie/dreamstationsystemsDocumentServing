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
	"time"
)

// ArchiveStats is the expensive half of the status page: how many rows each
// table holds and how much history each tier covers. It is computed on a
// timer rather than on demand — a full count(*)/min/max scan takes tens of
// seconds — so callers always get the last snapshot, with a background
// refresh kicked off if it has gone stale (see openget.txt).
type ArchiveStats struct {
	// Counts is keyed by table name. Empty until the first refresh lands.
	Counts map[string]int64
	// Spans is keyed by step ("5m", "1h", "24h").
	Spans map[string]ArchiveSpanInfo
	// At is when this snapshot was taken; zero means "not measured yet".
	At time.Time
}

// ArchiveSpanInfo is one history tier's extent.
type ArchiveSpanInfo struct {
	Oldest, Newest time.Time
	Rows           int64
}

// ArchiveStatsTTL is how stale a snapshot may get before a refresh is started.
const ArchiveStatsTTL = time.Hour

// archiveStatsTimeout caps a refresh, so a pathological scan cannot pin a
// connection for the life of the process.
const archiveStatsTimeout = 10 * time.Minute

// countedTables are the tables whose row counts the status pages show.
var countedTables = []string{"items", "latest", "volumes", "item_stats", "shop_offers"}

// archiveSteps are the history tiers whose extent the status pages show.
var archiveSteps = []string{"5m", "1h", "24h"}

// ArchiveStats returns the most recent snapshot, starting a background refresh
// if it is missing or stale. It never blocks on the database.
func (d *DB) ArchiveStats() ArchiveStats {
	d.statsMu.Lock()
	defer d.statsMu.Unlock()

	if d.statsAt.IsZero() || time.Since(d.statsAt) > ArchiveStatsTTL {
		d.startArchiveRefreshLocked()
	}
	// Copy the maps out: the caller must not be able to see a later refresh
	// mutate the snapshot it is halfway through rendering.
	out := ArchiveStats{
		Counts: make(map[string]int64, len(d.statsCounts)),
		Spans:  make(map[string]ArchiveSpanInfo, len(d.statsSpans)),
		At:     d.statsAt,
	}
	for k, v := range d.statsCounts {
		out.Counts[k] = v
	}
	for k, v := range d.statsSpans {
		out.Spans[k] = v
	}
	return out
}

// startArchiveRefreshLocked kicks off one refresh. Caller holds statsMu.
func (d *DB) startArchiveRefreshLocked() {
	if d.statsRunning {
		return
	}
	d.statsRunning = true
	go func() {
		// Deliberately not the caller's context: this outlives the request or
		// the generation run that happened to notice the snapshot was stale.
		ctx, cancel := context.WithTimeout(context.Background(), archiveStatsTimeout)
		defer cancel()

		counts := map[string]int64{}
		for _, t := range countedTables {
			var n int64
			if err := d.r.QueryRowContext(ctx, `SELECT count(*) FROM `+t).Scan(&n); err != nil {
				// Give up on this pass rather than publish a half-measured
				// snapshot; statsAt stays where it was, so the next caller
				// retries.
				d.statsMu.Lock()
				d.statsRunning = false
				d.statsMu.Unlock()
				return
			}
			counts[t] = n
		}
		spans := map[string]ArchiveSpanInfo{}
		for _, step := range archiveSteps {
			oldest, newest, rows, err := d.ArchiveSpan(ctx, step)
			if err != nil {
				d.statsMu.Lock()
				d.statsRunning = false
				d.statsMu.Unlock()
				return
			}
			spans[step] = ArchiveSpanInfo{Oldest: oldest, Newest: newest, Rows: rows}
		}

		d.statsMu.Lock()
		d.statsCounts, d.statsSpans, d.statsAt = counts, spans, time.Now()
		d.statsRunning = false
		d.statsMu.Unlock()
	}()
}
