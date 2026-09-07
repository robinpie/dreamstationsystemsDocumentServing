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
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/BurntSushi/toml"

	"dreamstation.systems/openget/internal/wiki"
)

// StockUnlimited is the stored stock of a shelf that never runs out.
const StockUnlimited = -1

// ShopExclusions is a set of shop names whose rows are dropped on ingest, keyed by lowercased name.
type ShopExclusions map[string]string // name -> reason

// shopFile is the TOML format of data/shops.toml.
type shopFile struct {
	Exclude []struct {
		Shop string `toml:"shop"`
		Why  string `toml:"why"`
	} `toml:"exclude"`
}

// LoadShopExclusions reads the list of shops to ignore.
//
// A missing file is not an error: the exclusions are a correction to upstream data, not a dependency, and an empty set still produces a far better page than ranking on item value did.
func LoadShopExclusions(path string) (ShopExclusions, error) {
	b, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return ShopExclusions{}, nil
	}
	if err != nil {
		return nil, err
	}
	var f shopFile
	if err := toml.Unmarshal(b, &f); err != nil {
		return nil, fmt.Errorf("store: parse %s: %w", path, err)
	}
	out := make(ShopExclusions, len(f.Exclude))
	for _, e := range f.Exclude {
		if n := strings.TrimSpace(e.Shop); n != "" {
			out[shopKey(n)] = e.Why
		}
	}
	return out, nil
}

// shopKey normalises a shop name for comparison. The wiki writes some shop names with a trailing full stop and some without, sometimes both for the same shop.
func shopKey(s string) string {
	return strings.ToLower(strings.TrimRight(strings.TrimSpace(s), "."))
}

// parseStock converts a bucket stock string ("∞", a count, "0", or "N/A"/"")
// to a stored value, reporting whether the shelf is one a player can actually
// buy from. "0" and unknown values are rejected as a matter of policy — see
// openget.txt for why.
func parseStock(s string) (int64, bool) {
	s = strings.TrimSpace(s)
	if s == "∞" {
		return StockUnlimited, true
	}
	n, err := strconv.ParseInt(strings.ReplaceAll(s, ",", ""), 10, 64)
	if err != nil || n <= 0 {
		return 0, false
	}
	return n, true
}

// Usable reports whether a storeline row describes something a player could
// walk up to a shop and buy for coins. It rejects non-coin currencies,
// Leagues-only rows, unstocked shelves, and shops in data/shops.toml.
func Usable(l wiki.StoreLine, ex ShopExclusions) (price, stock int64, ok bool) {
	if !strings.EqualFold(strings.TrimSpace(l.Currency), "Coins") {
		return 0, 0, false
	}
	if strings.Contains(l.Notes, "League") {
		return 0, 0, false
	}
	if _, bad := ex[shopKey(l.Shop)]; bad {
		return 0, 0, false
	}
	stock, ok = parseStock(l.Stock)
	if !ok {
		return 0, 0, false
	}
	price, err := strconv.ParseInt(strings.ReplaceAll(strings.TrimSpace(l.SellPrice), ",", ""), 10, 64)
	if err != nil || price < 0 {
		return 0, 0, false
	}
	return price, stock, true
}

// ReplaceShopOffers rebuilds shop_offers from a freshly-fetched set of storeline
// rows, resolving item names against the items table. stored+dropped does not
// sum to len(lines): unmatched item names (holiday tat, quest items, etc.) are
// neither stored nor counted as dropped. The table is replaced wholesale
// rather than upserted, so an item a shop stopped stocking disappears.
func (d *DB) ReplaceShopOffers(ctx context.Context, lines []wiki.StoreLine, ex ShopExclusions, now time.Time) (stored, dropped int, err error) {
	byName := map[string]int{}
	rows, err := d.r.QueryContext(ctx, `SELECT id, name FROM items ORDER BY id`)
	if err != nil {
		return 0, 0, err
	}
	defer rows.Close()
	for rows.Next() {
		var id int
		var name string
		if err := rows.Scan(&id, &name); err != nil {
			return 0, 0, err
		}
		k := strings.ToLower(name)
		// Keep the lowest id on a duplicate name: that is the tradeable form.
		if _, seen := byName[k]; !seen {
			byName[k] = id
		}
	}
	if err := rows.Err(); err != nil {
		return 0, 0, err
	}
	if len(byName) == 0 {
		// The items table has not been populated yet. Wiping shop_offers now would trade a stale table for an empty one, which is strictly worse.
		return 0, 0, nil
	}

	ts := now.Unix()
	err = d.Tx(ctx, func(tx *sql.Tx) error {
		if _, err := tx.ExecContext(ctx, `DELETE FROM shop_offers`); err != nil {
			return err
		}
		st, err := tx.PrepareContext(ctx, `
			INSERT INTO shop_offers (item_id,shop,price,stock,restock,notes,fetched_at)
			VALUES (?,?,?,?,?,?,?)
			ON CONFLICT(item_id,shop,price) DO UPDATE SET
				stock = max(shop_offers.stock, excluded.stock)`)
		if err != nil {
			return err
		}
		defer st.Close()

		for _, l := range lines {
			price, stock, ok := Usable(l, ex)
			if !ok {
				dropped++
				continue
			}
			id, known := byName[strings.ToLower(strings.TrimSpace(l.Item))]
			if !known {
				continue
			}
			// The same shelf is sometimes recorded twice, identically. The conflict clause keeps the more favourable stock, which for a true duplicate is the same number either way.
			shop := strings.TrimRight(strings.TrimSpace(l.Shop), ".")
			if _, err := st.ExecContext(ctx, id, shop, price, stock,
				strings.TrimSpace(l.Restock), strings.TrimSpace(l.Notes), ts); err != nil {
				return fmt.Errorf("insert shop offer %q@%q: %w", l.Item, shop, err)
			}
		}
		// Count the rows rather than the inserts. A collapsed duplicate takes the ON CONFLICT branch and stores nothing new, so counting calls would report a few hundred offers this table does not hold.
		return tx.QueryRowContext(ctx, `SELECT count(*) FROM shop_offers`).Scan(&stored)
	})
	if err != nil {
		return 0, 0, err
	}
	return stored, dropped, nil
}

// ShopOfferCount reports how many offers are stored, for /status and for the freshness note.
func (d *DB) ShopOfferCount(ctx context.Context) (int, error) {
	var n int
	err := d.r.QueryRowContext(ctx, `SELECT count(*) FROM shop_offers`).Scan(&n)
	return n, err
}
