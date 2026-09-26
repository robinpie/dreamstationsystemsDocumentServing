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
	"errors"
	"fmt"
	"os"
	"strings"

	"github.com/BurntSushi/toml"
)

// indexFile is the TOML seed format for data/indices.toml.
type indexFile struct {
	Index []struct {
		ID      string    `toml:"id"`
		Name    string    `toml:"name"`
		Blurb   string    `toml:"blurb"`
		Items   []string  `toml:"items"`
		Weights []float64 `toml:"weights"`
	} `toml:"index"`
}

// LoadIndicesFile reads index definitions and resolves their constituents by name against the items table.
//
// Names rather than ids, because a basket is a human-maintained editorial choice and "Ranarr weed" survives re-review in a way that 257 does not. Unresolvable names are returned as a warning list rather than a hard error: one renamed herb should not cost us every other index.
func (d *DB) LoadIndicesFile(ctx context.Context, path string) (int, []string, error) {
	b, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return 0, nil, nil
	}
	if err != nil {
		return 0, nil, err
	}
	var f indexFile
	if err := toml.Unmarshal(b, &f); err != nil {
		return 0, nil, fmt.Errorf("store: parse %s: %w", path, err)
	}

	// One pass over items, since resolving the names one query at a time would be a round trip each for no reason.
	byName := map[string]int{}
	rows, err := d.r.QueryContext(ctx, `SELECT id, name FROM items ORDER BY id`)
	if err != nil {
		return 0, nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var id int
		var name string
		if err := rows.Scan(&id, &name); err != nil {
			return 0, nil, err
		}
		k := strings.ToLower(name)
		// Keep the lowest id on a duplicate name: that is the tradeable form.
		if _, seen := byName[k]; !seen {
			byName[k] = id
		}
	}
	if err := rows.Err(); err != nil {
		return 0, nil, err
	}
	if len(byName) == 0 {
		// The items table has not been populated yet; loading now would store a set of empty baskets that nothing would ever repair.
		return 0, nil, nil
	}

	var unresolved []string
	var out []Index
	for _, in := range f.Index {
		idx := Index{ID: in.ID, Name: in.Name, Blurb: in.Blurb}
		for i, n := range in.Items {
			id, ok := byName[strings.ToLower(n)]
			if !ok {
				unresolved = append(unresolved, fmt.Sprintf("%s: %s", in.ID, n))
				continue
			}
			w := 1.0
			if i < len(in.Weights) && in.Weights[i] > 0 {
				w = in.Weights[i]
			}
			idx.Members = append(idx.Members, IndexMember{ItemID: id, Weight: w})
		}
		if len(idx.Members) == 0 {
			continue
		}
		out = append(out, idx)
	}
	if err := d.LoadIndices(ctx, out); err != nil {
		return 0, unresolved, err
	}
	return len(out), unresolved, nil
}
