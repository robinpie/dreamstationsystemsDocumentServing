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

package wiki

import (
	"context"
	"fmt"
	"net/url"
)

// BucketBase is the MediaWiki API root of the OSRS Wiki proper — a different
// host and service from the prices API. Bucket is the wiki's structured-data
// extension and a supported interface, not scraping; see openget.txt.
//
//	https://oldschool.runescape.wiki/w/RuneScape:Bucket
const BucketBase = "https://oldschool.runescape.wiki/api.php"

// bucketPageSize is how many rows one query asks for. The server truncates at 5000 rather than erroring, so a full read pages with .offset() until a short page arrives.
const bucketPageSize = 5000

// maxBucketRows caps a paged read. Nothing we query is anywhere near this — storeline was 6326 rows when this was written — so hitting it means the offset paging is not advancing and the loop must stop rather than hammer a volunteer-run wiki forever.
const maxBucketRows = 100000

// StoreLine is one row of the wiki's storeline bucket: one item on one shop's shelf.
//
// Every field is a string, including the numeric ones, because the bucket declares them TEXT. That is not laziness upstream — it carries real distinctions that an int cannot: Stock is "∞" for a shelf that never runs out and "N/A" where nobody has recorded one, which is a different claim from "0". Parsing is left to the caller so those three cases survive the trip.
type StoreLine struct {
	Shop      string `json:"sold_by"`
	Item      string `json:"sold_item"`
	SellPrice string `json:"store_sell_price"` // coins the player hands over
	Stock     string `json:"store_stock"`      // base stock: "∞", "N/A" or an integer
	Restock   string `json:"restock_time"`
	Currency  string `json:"store_currency"` // "Coins" for ordinary shops, otherwise Tokkul, points, tickets...
	Notes     string `json:"store_notes"`    // shop variant: diary tier, quest state, seasonal mode
}

// storeLineFields is the select list, and must stay in step with StoreLine's tags. Bucket wants lowercase names with underscores.
const storeLineFields = `'sold_by','sold_item','store_sell_price','store_stock','restock_time','store_currency','store_notes'`

// StoreLines fetches every row of the storeline bucket: what each shop in the
// game stocks, at what price, in what quantity — about 6300 rows in two
// requests. It only changes on game updates, so poll it daily at most.
func (c *Client) StoreLines(ctx context.Context) ([]StoreLine, error) {
	var out []StoreLine
	for offset := 0; ; offset += bucketPageSize {
		q := fmt.Sprintf("bucket('storeline').select(%s).limit(%d).offset(%d).run()",
			storeLineFields, bucketPageSize, offset)

		var page struct {
			Bucket []StoreLine `json:"bucket"`
			// MediaWiki reports a bad query as a 200 carrying an error object, so a nil check on the body is the only thing standing between a typo and an empty table.
			Error *struct {
				Code string `json:"code"`
				Info string `json:"info"`
			} `json:"error"`
		}

		u := BucketBase + "?action=bucket&format=json&query=" + url.QueryEscape(q)
		key := fmt.Sprintf("bucket storeline@%d", offset)
		// No conditional request: the response carries no useful ETag and a paged read wants every page every time.
		if err := c.getURL(ctx, u, key, false, &page); err != nil {
			return nil, err
		}
		if page.Error != nil {
			return nil, fmt.Errorf("wiki: bucket storeline: %s: %s", page.Error.Code, page.Error.Info)
		}

		out = append(out, page.Bucket...)
		if len(page.Bucket) < bucketPageSize {
			return out, nil
		}
		if len(out) >= maxBucketRows {
			return nil, fmt.Errorf("wiki: bucket storeline: stopped at %d rows, which means paging is not terminating", len(out))
		}
	}
}
