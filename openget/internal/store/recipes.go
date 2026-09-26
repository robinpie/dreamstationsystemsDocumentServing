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
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"

	"github.com/BurntSushi/toml"

	"dreamstation.systems/openget/internal/calc"
)

// recipeFile is the TOML seed format produced by contrib/gen_recipes.py.
type recipeFile struct {
	Recipe []calc.Recipe `toml:"recipe"`
}

// LoadRecipes replaces the recipes table from a TOML file.
//
// The seed is authoritative: recipes are data, and the file in the repository is where they are edited. Reloading on start means a game update is a regenerate-and-restart, not a migration.
func (d *DB) LoadRecipes(ctx context.Context, path string) (int, error) {
	b, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return 0, nil
	}
	if err != nil {
		return 0, err
	}
	var f recipeFile
	if err := toml.Unmarshal(b, &f); err != nil {
		return 0, fmt.Errorf("store: parse %s: %w", path, err)
	}

	n := 0
	err = d.Tx(ctx, func(tx *sql.Tx) error {
		if _, err := tx.ExecContext(ctx, `DELETE FROM recipes`); err != nil {
			return err
		}
		st, err := tx.PrepareContext(ctx, `
			INSERT INTO recipes (id,kind,name,inputs,outputs,skill_reqs,notes,extra,sort_key)
			VALUES (?,?,?,?,?,?,?,?,?)`)
		if err != nil {
			return err
		}
		defer st.Close()
		for _, r := range f.Recipe {
			in, err := calc.MarshalIngredients(r.Inputs)
			if err != nil {
				return err
			}
			out, err := calc.MarshalIngredients(r.Outputs)
			if err != nil {
				return err
			}
			ex, err := calc.MarshalExtra(r.Extra)
			if err != nil {
				return err
			}
			if _, err := st.ExecContext(ctx, r.ID, r.Kind, r.Name, in, out,
				r.SkillReqs, r.Notes, ex, r.SortKey); err != nil {
				return fmt.Errorf("insert recipe %s: %w", r.ID, err)
			}
			n++
		}
		return nil
	})
	return n, err
}

// Recipes lists recipes, optionally filtered to one kind.
func (d *DB) Recipes(ctx context.Context, kind string) ([]calc.Recipe, error) {
	q := `SELECT id,kind,name,inputs,outputs,skill_reqs,notes,extra,sort_key FROM recipes`
	var args []any
	if kind != "" {
		q += ` WHERE kind = ?`
		args = append(args, kind)
	}
	q += ` ORDER BY sort_key, id`
	rows, err := d.r.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanRecipes(rows)
}

// Recipe loads one recipe by id.
func (d *DB) Recipe(ctx context.Context, id string) (*calc.Recipe, error) {
	rows, err := d.r.QueryContext(ctx,
		`SELECT id,kind,name,inputs,outputs,skill_reqs,notes,extra,sort_key FROM recipes WHERE id = ?`, id)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	rs, err := scanRecipes(rows)
	if err != nil {
		return nil, err
	}
	if len(rs) == 0 {
		return nil, ErrNotFound
	}
	return &rs[0], nil
}

// RecipeKinds lists the kinds that actually have recipes loaded, with counts, so the menu never offers an empty category.
func (d *DB) RecipeKinds(ctx context.Context) (map[string]int, error) {
	rows, err := d.r.QueryContext(ctx, `SELECT kind, count(*) FROM recipes GROUP BY kind`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]int{}
	for rows.Next() {
		var k string
		var n int
		if err := rows.Scan(&k, &n); err != nil {
			return nil, err
		}
		out[k] = n
	}
	return out, rows.Err()
}

func scanRecipes(rows *sql.Rows) ([]calc.Recipe, error) {
	var out []calc.Recipe
	for rows.Next() {
		var r calc.Recipe
		var in, outs, extra string
		if err := rows.Scan(&r.ID, &r.Kind, &r.Name, &in, &outs,
			&r.SkillReqs, &r.Notes, &extra, &r.SortKey); err != nil {
			return nil, err
		}
		var err error
		if r.Inputs, err = calc.UnmarshalIngredients(in); err != nil {
			return nil, fmt.Errorf("recipe %s inputs: %w", r.ID, err)
		}
		if r.Outputs, err = calc.UnmarshalIngredients(outs); err != nil {
			return nil, fmt.Errorf("recipe %s outputs: %w", r.ID, err)
		}
		if r.Extra, err = calc.UnmarshalExtra(extra); err != nil {
			return nil, fmt.Errorf("recipe %s extra: %w", r.ID, err)
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// ---------------------------------------------------------------------------
// Price book
// ---------------------------------------------------------------------------

// PriceBook is an in-memory snapshot of prices for a set of items, satisfying calc.Prices. Recipes reference a handful of items each, so loading the whole set once and evaluating in memory beats a query per ingredient by a wide margin when the calculator index page costs every recipe at once.
type PriceBook struct {
	buy   map[int]int64
	sell  map[int]int64
	name  map[int]string
	limit map[int]int
}

// Buy implements calc.Prices.
func (p *PriceBook) Buy(id int) (int64, bool) { v, ok := p.buy[id]; return v, ok && v > 0 }

// Sell implements calc.Prices.
func (p *PriceBook) Sell(id int) (int64, bool) { v, ok := p.sell[id]; return v, ok && v > 0 }

// Name implements calc.Prices.
func (p *PriceBook) Name(id int) string {
	if n, ok := p.name[id]; ok {
		return n
	}
	return fmt.Sprintf("item %d", id)
}

// Limit implements calc.Prices.
func (p *PriceBook) Limit(id int) int { return p.limit[id] }

// PriceBookFor loads prices for the given item ids.
//
// Inputs are priced at `high` (the instant-buy price — what you pay to get one now) and outputs at `high` too, since that is the price a sell offer fills at. Using `low` for outputs would silently assume you undercut the market on every single sale.
func (d *DB) PriceBookFor(ctx context.Context, ids []int) (*PriceBook, error) {
	pb := &PriceBook{
		buy: map[int]int64{}, sell: map[int]int64{},
		name: map[int]string{}, limit: map[int]int{},
	}
	if len(ids) == 0 {
		return pb, nil
	}
	rows, err := d.r.QueryContext(ctx, `
		SELECT i.id, i.name, i.buy_limit, l.high, l.low
		  FROM items i LEFT JOIN latest l ON l.item_id = i.id
		 WHERE i.id IN (`+joinIDs(ids)+`)`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var id int
		var name string
		var limit sql.NullInt64
		var high, low sql.NullInt64
		if err := rows.Scan(&id, &name, &limit, &high, &low); err != nil {
			return nil, err
		}
		pb.name[id] = name
		if limit.Valid {
			pb.limit[id] = int(limit.Int64)
		}
		// Fall back to the other side of the book when one is unobserved: a thin item with only a sell print is better priced approximately than dropped from the calculator entirely.
		switch {
		case high.Valid:
			pb.buy[id], pb.sell[id] = high.Int64, high.Int64
		case low.Valid:
			pb.buy[id], pb.sell[id] = low.Int64, low.Int64
		}
	}
	return pb, rows.Err()
}

// RecipeItemIDs collects every item id referenced by a set of recipes.
func RecipeItemIDs(rs []calc.Recipe) []int {
	seen := map[int]bool{}
	var out []int
	for _, r := range rs {
		for _, side := range [][]calc.Ingredient{r.Inputs, r.Outputs} {
			for _, i := range side {
				if !seen[i.ItemID] {
					seen[i.ItemID] = true
					out = append(out, i.ItemID)
				}
			}
		}
	}
	return out
}

// ---------------------------------------------------------------------------
// Market indices
// ---------------------------------------------------------------------------

// Index is a weighted basket of items tracked over time.
type Index struct {
	ID      string
	Name    string
	Blurb   string
	Members []IndexMember
}

// IndexMember is one constituent.
type IndexMember struct {
	ItemID int     `json:"item_id"`
	Weight float64 `json:"weight"`
}

// LoadIndices upserts the index definitions and retires any that the seed file no longer defines.
//
// Upsert rather than delete-and-reinsert: index_points carries a foreign key into indices, so wiping the table on every start fails the moment any history exists — and would throw that history away if it did not.
func (d *DB) LoadIndices(ctx context.Context, idx []Index) error {
	return d.Tx(ctx, func(tx *sql.Tx) error {
		var ids []string
		for _, i := range idx {
			b, err := json.Marshal(i.Members)
			if err != nil {
				return err
			}
			if _, err := tx.ExecContext(ctx,
				`INSERT INTO indices (id,name,blurb,members) VALUES (?,?,?,?)
				 ON CONFLICT(id) DO UPDATE SET
					name=excluded.name, blurb=excluded.blurb, members=excluded.members`,
				i.ID, i.Name, i.Blurb, string(b)); err != nil {
				return err
			}
			ids = append(ids, i.ID)
		}
		if len(ids) == 0 {
			return nil
		}
		// Retire indices dropped from the seed file, points first so the foreign key stays satisfied.
		ph := strings.TrimSuffix(strings.Repeat("?,", len(ids)), ",")
		args := make([]any, len(ids))
		for i, s := range ids {
			args[i] = s
		}
		if _, err := tx.ExecContext(ctx,
			`DELETE FROM index_points WHERE index_id NOT IN (`+ph+`)`, args...); err != nil {
			return err
		}
		_, err := tx.ExecContext(ctx,
			`DELETE FROM indices WHERE id NOT IN (`+ph+`)`, args...)
		return err
	})
}

// Indices lists every index with its constituents.
func (d *DB) Indices(ctx context.Context) ([]Index, error) {
	rows, err := d.r.QueryContext(ctx, `SELECT id,name,blurb,members FROM indices ORDER BY id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Index
	for rows.Next() {
		var i Index
		var mem string
		if err := rows.Scan(&i.ID, &i.Name, &i.Blurb, &mem); err != nil {
			return nil, err
		}
		if err := json.Unmarshal([]byte(mem), &i.Members); err != nil {
			return nil, err
		}
		out = append(out, i)
	}
	return out, rows.Err()
}

// IndexByID loads one index.
func (d *DB) IndexByID(ctx context.Context, id string) (*Index, error) {
	all, err := d.Indices(ctx)
	if err != nil {
		return nil, err
	}
	for _, i := range all {
		if i.ID == id {
			return &i, nil
		}
	}
	return nil, ErrNotFound
}

// RecordIndexPoints computes each index's current value and appends it.
//
// The value is a weighted average price rebased so the first recorded reading is 100. Publishing the constituents (see the /indices page) is the whole differentiator here: ge-tracker's nine indices are opaque baskets, and an index you cannot audit is a number you cannot use.
func (d *DB) RecordIndexPoints(ctx context.Context, at int64) error {
	idx, err := d.Indices(ctx)
	if err != nil {
		return err
	}
	for _, i := range idx {
		ids := make([]int, 0, len(i.Members))
		for _, m := range i.Members {
			ids = append(ids, m.ItemID)
		}
		if len(ids) == 0 {
			continue
		}
		pb, err := d.PriceBookFor(ctx, ids)
		if err != nil {
			return err
		}
		var sum, wsum float64
		for _, m := range i.Members {
			p, ok := pb.Sell(m.ItemID)
			if !ok {
				continue
			}
			sum += float64(p) * m.Weight
			wsum += m.Weight
		}
		if wsum == 0 {
			continue
		}
		raw := sum / wsum

		// Rebase so the first reading is 100. The raw basket price at that epoch is kept in meta: deriving it back out of a stored index value would compound rounding on every subsequent point.
		baseKey := "index_base:" + i.ID
		var baseRaw float64
		if s, err := d.GetMeta(ctx, baseKey); err == nil && s != "" {
			baseRaw, _ = strconv.ParseFloat(s, 64)
		}
		if baseRaw <= 0 {
			baseRaw = raw
			if err := d.SetMeta(ctx, baseKey, strconv.FormatFloat(raw, 'f', -1, 64)); err != nil {
				return err
			}
		}
		val := raw / baseRaw * 100
		if _, err := d.w.ExecContext(ctx,
			`INSERT INTO index_points (index_id,ts,value) VALUES (?,?,?)
			 ON CONFLICT(index_id,ts) DO UPDATE SET value = excluded.value`,
			i.ID, at, val); err != nil {
			return err
		}
	}
	return nil
}

// IndexSeries loads an index's history.
func (d *DB) IndexSeries(ctx context.Context, id string, since int64) ([]struct {
	TS    int64
	Value float64
}, error) {
	rows, err := d.r.QueryContext(ctx,
		`SELECT ts, value FROM index_points WHERE index_id = ? AND ts >= ? ORDER BY ts`, id, since)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []struct {
		TS    int64
		Value float64
	}
	for rows.Next() {
		var p struct {
			TS    int64
			Value float64
		}
		if err := rows.Scan(&p.TS, &p.Value); err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}
