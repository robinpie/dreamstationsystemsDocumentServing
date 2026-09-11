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

package calc

import (
	"encoding/json"
	"fmt"
	"sort"
)

// A Recipe turns some items (and possibly coins) into other items (and possibly coins). Every money-maker calculator on the site is one of these.
//
// Modelling them as data rather than one Go function per calculator is what makes the long tail tractable: adding "magic tablets" is a config entry, not a code change, and every frontend — web, Gemini, Gopher, finger — gets the new calculator at the same moment with no extra work.
type Recipe struct {
	ID        string       `json:"id" toml:"id"`
	Kind      string       `json:"kind" toml:"kind"`
	Name      string       `json:"name" toml:"name"`
	Inputs    []Ingredient `json:"inputs" toml:"inputs"`
	Outputs   []Ingredient `json:"outputs" toml:"outputs"`
	SkillReqs string       `json:"skill_reqs" toml:"skill_reqs"`
	Notes     string       `json:"notes" toml:"notes"`
	Extra     Extra        `json:"extra" toml:"extra"`
	SortKey   int          `json:"sort_key" toml:"sort_key"`
}

// Ingredient is one item on either side of a recipe.
type Ingredient struct {
	ItemID int     `json:"item_id" toml:"item_id"`
	Qty    float64 `json:"qty" toml:"qty"`
	Note   string  `json:"note,omitempty" toml:"note"`
}

// Extra holds the per-kind knobs that do not fit the item lists.
type Extra struct {
	// FeeGP is a flat coin cost per action: the sawmill's plank fee, a tanner's charge, the cost of repairing barrows gear at an armour stand.
	FeeGP int64 `json:"fee_gp,omitempty" toml:"fee_gp"`
	// OutputGP is flat coin revenue per action. High alchemy pays in coins, not in an item.
	OutputGP int64 `json:"output_gp,omitempty" toml:"output_gp"`
	// Untaxed marks outputs that are not sold on the Grand Exchange, so no convenience fee applies. High alchemy is the important case.
	Untaxed bool `json:"untaxed,omitempty" toml:"untaxed"`
	// PerHour is a typical action rate, for the gp/hour column. Zero hides it.
	PerHour int `json:"per_hour,omitempty" toml:"per_hour"`
	// XP is experience per action, for the gp-per-xp column.
	XP float64 `json:"xp,omitempty" toml:"xp"`
}

// Kinds are the calculator families, in the order they appear in the menu.
//
// High alchemy and store profit are deliberately absent. Alchemy applies uniformly to every item in the game; store profit applies to whatever the wiki says shops currently stock, which is a thousand items across five hundred shops and changes on game updates. Neither is a hand-listed set, so both are computed as whole-catalogue pages (/alch and /store-profit) instead of as several thousand near-identical recipe rows.
var Kinds = []struct {
	Kind, Title, Blurb string
}{
	{"decanting", "Potion decanting", "Buy potions at one dose count, decant, sell at another."},
	{"herblore", "Herblore", "Unfinished potions plus secondaries into finished potions."},
	{"tanning", "Tanning", "Hides into leather at a tanner."},
	{"plank", "Plank making", "Logs into planks at a sawmill."},
	{"smithing", "Smelting and the blast furnace", "Ore and coal into bars."},
	{"fletching", "Fletching", "Logs into bows, and bows into strung bows."},
	{"enchanting", "Enchanting", "Jewellery plus runes into enchanted jewellery."},
	{"tablet", "Magic tablets", "Soft clay plus runes into teleport tablets."},
	{"spell", "Spell conversions", "Items transmuted in the inventory, paid for in runes."},
	{"itemset", "Item sets", "Barrows and armour sets against their component pieces."},
	{"barrows", "Barrows repair", "Degraded barrows gear repaired and resold."},
	{"combination", "Combination items", "Components combined into a single higher-value item."},
	{"sapling", "Sapling trading", "Seeds grown into saplings."},
}

// KindTitle returns the display title for a kind.
func KindTitle(kind string) string {
	for _, k := range Kinds {
		if k.Kind == kind {
			return k.Title
		}
	}
	return kind
}

// Prices supplies market prices to the evaluator.
type Prices interface {
	// Buy is the price to acquire one unit now (the API's instant-buy side). ok is false when the item has never been observed.
	Buy(itemID int) (int64, bool)
	// Sell is what one unit fetches now, before tax.
	Sell(itemID int) (int64, bool)
	// Name is for display and error messages.
	Name(itemID int) string
	// Limit is the 4-hour buy limit, 0 if unknown.
	Limit(itemID int) int
}

// Line is one costed row of an evaluated recipe.
type Line struct {
	ItemID  int
	Name    string
	Qty     float64
	Unit    int64 // unit price used
	Total   int64 // Qty * Unit, with tax already applied on output lines
	Tax     int64 // tax attributed to this line (outputs only)
	Note    string
	Missing bool // no observed price
}

// Result is a fully costed recipe.
type Result struct {
	Recipe   Recipe
	Inputs   []Line
	Outputs  []Line
	Cost     int64 // total to buy the inputs, including FeeGP
	Revenue  int64 // total received for the outputs, after tax
	Tax      int64
	Profit   int64
	MarginPc float64
	ROI      float64
	// PerHour is Profit * Extra.PerHour, zero when no rate is configured.
	PerHour int64
	// GPPerXP is Profit / XP when both are known.
	GPPerXP float64
	// Limiting is the input whose buy limit caps throughput hardest.
	Limiting string
	// Incomplete is true when any leg had no observed price, in which case Profit is not trustworthy and must be presented as unknown rather than as a number.
	Incomplete bool
}

// Evaluate costs a recipe at current prices.
//
// Inputs are bought at the instant-buy price (you want them now) and outputs are sold at the instant-sell price with the convenience fee deducted, unless the recipe is marked Untaxed. That is the pessimistic reading in both directions, which is the correct bias for a tool people spend real capital on: a calculator that flatters a marginal method is worse than useless.
func Evaluate(r Recipe, p Prices) Result {
	res := Result{Recipe: r}

	for _, in := range r.Inputs {
		unit, ok := p.Buy(in.ItemID)
		l := Line{ItemID: in.ItemID, Name: p.Name(in.ItemID), Qty: in.Qty, Unit: unit, Note: in.Note}
		if !ok {
			l.Missing = true
			res.Incomplete = true
		}
		l.Total = int64(in.Qty * float64(unit))
		res.Cost += l.Total
		res.Inputs = append(res.Inputs, l)
	}
	res.Cost += r.Extra.FeeGP

	for _, out := range r.Outputs {
		unit, ok := p.Sell(out.ItemID)
		l := Line{ItemID: out.ItemID, Name: p.Name(out.ItemID), Qty: out.Qty, Unit: unit, Note: out.Note}
		if !ok {
			l.Missing = true
			res.Incomplete = true
		}
		gross := int64(out.Qty * float64(unit))
		if !r.Extra.Untaxed {
			// Tax is charged per item sold, so it is computed on the unit price and multiplied — not on the total. On an item near the 5,000,000 cap those two are very different numbers.
			l.Tax = int64(out.Qty * float64(Tax(out.ItemID, unit)))
		}
		l.Total = gross - l.Tax
		res.Tax += l.Tax
		res.Revenue += l.Total
		res.Outputs = append(res.Outputs, l)
	}
	res.Revenue += r.Extra.OutputGP

	res.Profit = res.Revenue - res.Cost
	if res.Cost > 0 {
		res.ROI = float64(res.Profit) / float64(res.Cost) * 100
	}
	if res.Revenue > 0 {
		res.MarginPc = float64(res.Profit) / float64(res.Revenue) * 100
	}
	if r.Extra.PerHour > 0 {
		res.PerHour = res.Profit * int64(r.Extra.PerHour)
	}
	if r.Extra.XP > 0 {
		res.GPPerXP = float64(res.Profit) / r.Extra.XP
	}

	// Report which input's buy limit binds first, since that is the real ceiling on any of these methods.
	best := -1.0
	for _, in := range r.Inputs {
		lim := p.Limit(in.ItemID)
		if lim <= 0 || in.Qty <= 0 {
			continue
		}
		actions := float64(lim) / in.Qty
		if best < 0 || actions < best {
			best = actions
			res.Limiting = fmt.Sprintf("%s (%d per 4h → %.0f actions)", p.Name(in.ItemID), lim, actions)
		}
	}
	return res
}

// EvaluateAll costs every recipe and sorts most profitable first.
func EvaluateAll(rs []Recipe, p Prices) []Result {
	out := make([]Result, 0, len(rs))
	for _, r := range rs {
		out = append(out, Evaluate(r, p))
	}
	sort.SliceStable(out, func(i, j int) bool {
		// Recipes we could not price sink to the bottom rather than sorting as zero, which would put them in the middle of the table looking like real, merely-unprofitable methods.
		if out[i].Incomplete != out[j].Incomplete {
			return !out[i].Incomplete
		}
		return out[i].Profit > out[j].Profit
	})
	return out
}

// MarshalIngredients encodes an ingredient list for storage.
func MarshalIngredients(in []Ingredient) (string, error) {
	b, err := json.Marshal(in)
	return string(b), err
}

// UnmarshalIngredients decodes a stored ingredient list.
func UnmarshalIngredients(s string) ([]Ingredient, error) {
	var out []Ingredient
	if s == "" {
		return nil, nil
	}
	err := json.Unmarshal([]byte(s), &out)
	return out, err
}

// MarshalExtra encodes recipe extras for storage.
func MarshalExtra(e Extra) (string, error) {
	b, err := json.Marshal(e)
	return string(b), err
}

// UnmarshalExtra decodes stored recipe extras.
func UnmarshalExtra(s string) (Extra, error) {
	var e Extra
	if s == "" || s == "{}" {
		return e, nil
	}
	err := json.Unmarshal([]byte(s), &e)
	return e, err
}
