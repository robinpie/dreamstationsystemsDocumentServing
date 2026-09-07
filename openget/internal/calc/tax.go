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

// Package calc holds the arithmetic that turns raw prices into the numbers people actually trade on. The API gives prices; every feature on the site is a derivation from them, so this is the package most worth getting right.
package calc

// Grand Exchange convenience fee ("GE tax"): 2% of the sale price, paid by the
// seller only, capped at 5,000,000 gp per item, rounded down. See openget.txt
// for the full rule set and sources; re-check after any GE-touching game update.
const (
	// TaxRateNum/TaxRateDen express the 2% rate as an exact rational so the floor is applied to integer arithmetic. Doing this in float64 and truncating would round the wrong way for some prices.
	TaxRateNum int64 = 2
	TaxRateDen int64 = 100

	// TaxCap is the per-item ceiling: 5,000,000 gp.
	TaxCap int64 = 5_000_000

	// TaxFreeBelow is the price at or under which the 2% floor lands on zero. Derived, not hardcoded policy: floor(49 * 0.02) == 0.
	TaxFreeBelow int64 = 50
)

// exempt is the canonical set of items that pay no convenience fee, mirrored from the wiki's "Exempt from tax" table on 2026-08-04 and resolved to item ids against that day's /mapping.
//
// Kept as literal ids rather than names because names change spelling across game updates far more often than ids change meaning.
var exempt = map[int]bool{
	// Bonds.
	13190: true, // Old school bond

	// Energy potion. The wiki lists "[[Energy potion]]" without a dose, and the linked page covers every dose, so all four are treated as exempt. If that turns out to be wrong it is wrong by 2% on a cheap potion.
	3008: true, // Energy potion(4)
	3010: true, // Energy potion(3)
	3012: true, // Energy potion(2)
	3014: true, // Energy potion(1)

	// Low level combat consumables.
	882: true, // Bronze arrow
	806: true, // Bronze dart
	884: true, // Iron arrow
	807: true, // Iron dart
	558: true, // Mind rune
	886: true, // Steel arrow
	808: true, // Steel dart

	// Low level food.
	365:  true, // Bass
	2309: true, // Bread
	1891: true, // Cake
	2140: true, // Cooked chicken
	2142: true, // Cooked meat
	347:  true, // Herring
	379:  true, // Lobster
	355:  true, // Mackerel
	2327: true, // Meat pie
	351:  true, // Pike
	329:  true, // Salmon
	315:  true, // Shrimps
	361:  true, // Tuna

	// Teleport items.
	8011:  true, // Ardougne teleport (tablet)
	8010:  true, // Camelot teleport (tablet)
	28824: true, // Civitas illa fortis teleport
	8009:  true, // Falador teleport (tablet)
	3853:  true, // Games necklace(8)
	28790: true, // Kourend castle teleport (tablet)
	8008:  true, // Lumbridge teleport (tablet)
	2552:  true, // Ring of dueling(8)
	8013:  true, // Teleport to house (tablet)
	8007:  true, // Varrock teleport (tablet)

	// Tools.
	1755: true, // Chisel
	5325: true, // Gardening trowel
	1785: true, // Glassblowing pipe
	2347: true, // Hammer
	1733: true, // Needle
	233:  true, // Pestle and mortar
	5341: true, // Rake
	8794: true, // Saw
	5329: true, // Secateurs
	5343: true, // Seed dibber
	1735: true, // Shears
	952:  true, // Spade
	5331: true, // Watering can
}

// IsExempt reports whether an item pays no GE tax.
func IsExempt(itemID int) bool { return exempt[itemID] }

// ExemptIDs returns the exempt item ids. Used by the /ge-tax-calculator page, which publishes the list rather than asking people to trust it.
func ExemptIDs() []int {
	out := make([]int, 0, len(exempt))
	for id := range exempt {
		out = append(out, id)
	}
	return out
}

// Tax is the convenience fee a seller pays on one item sold at price.
//
//	tax(p) = 0                                if exempt
//	       = min(floor(p * 2/100), 5_000_000) otherwise
func Tax(itemID int, price int64) int64 {
	if price <= 0 || exempt[itemID] {
		return 0
	}
	t := price * TaxRateNum / TaxRateDen // integer division == floor for p >= 0
	if t > TaxCap {
		return TaxCap
	}
	return t
}

// NetSale is what a seller actually receives for one item listed at price.
func NetSale(itemID int, price int64) int64 { return price - Tax(itemID, price) }

// Flip is the full flipping picture for one item at one moment.
//
// The convention throughout, matching the API: High is the instant-BUY price (what you pay to buy right now) and Low is the instant-SELL price (what you receive selling right now). Flipping means buying at Low and selling at High, so the profit is the post-tax High minus the Low.
type Flip struct {
	Buy       int64 // price you pay to acquire — the API's "low"
	Sell      int64 // price you list at        — the API's "high"
	Tax       int64 // fee on the sale
	Margin    int64 // profit per item, after tax
	MarginPc  float64
	ROI       float64 // margin as a percentage of capital tied up
	Limit     int     // 4-hour buy limit, 0 if unknown
	Potential int64   // margin * limit: profit per 4-hour window
}

// NewFlip computes the flip for an item. buy and sell are the raw instant-sell and instant-buy prices; either being zero means "not observed" and yields a zero-value Flip with prices filled in but no margin claim.
func NewFlip(itemID int, buy, sell int64, limit int) Flip {
	f := Flip{Buy: buy, Sell: sell, Limit: limit}
	if buy <= 0 || sell <= 0 {
		return f
	}
	f.Tax = Tax(itemID, sell)
	f.Margin = sell - f.Tax - buy
	f.MarginPc = pct(f.Margin, sell)
	f.ROI = pct(f.Margin, buy)
	if limit > 0 {
		f.Potential = f.Margin * int64(limit)
	}
	return f
}

// Rune reagents for the alchemy spells. Prices are looked up live rather than hardcoded — runes move.
const (
	// NatureRuneID is consumed by every alchemy cast and can never be avoided.
	NatureRuneID = 561
	// FireRuneID is the elemental reagent. Any fire staff, mystic fire staff, lava/steam/smoke battlestaff or tome of fire supplies these free, which is how nearly everyone alchs — so charging for them is opt-in.
	FireRuneID = 554
)

// AlchSpell is one of the two alchemy spells. The three names are three different jobs: Name labels the spell itself, Title heads the page, Short heads a table column.
type AlchSpell struct {
	Key       string // URL key: "high" or "low"
	Name      string // "High Level Alchemy"
	Title     string // "High alchemy"
	Short     string // "High alch"
	FireRunes int64  // fire runes per cast, staff-avoidable
}

// AlchSpells lists the spells in the order the UI offers them. High alchemy pays 60% of an item's value and low alchemy 40%, so the two rank items differently and neither list is a rescaling of the other.
var AlchSpells = []AlchSpell{
	{Key: "high", Name: "High Level Alchemy", Title: "High alchemy", Short: "High alch", FireRunes: 5},
	{Key: "low", Name: "Low Level Alchemy", Title: "Low alchemy", Short: "Low alch", FireRunes: 3},
}

// AlchSpellByKey resolves a URL key, falling back to high alchemy so a hand-typed query string cannot produce a page with no spell at all.
func AlchSpellByKey(key string) AlchSpell {
	for _, s := range AlchSpells {
		if s.Key == key {
			return s
		}
	}
	return AlchSpells[0]
}

// AlchRuneCost is what the reagents for one cast cost. The nature rune is always paid for; the fire runes only when chargeFire is set, i.e. when the caster is not holding something that supplies them.
func AlchRuneCost(s AlchSpell, nature, fire int64, chargeFire bool) int64 {
	if !chargeFire {
		return nature
	}
	return nature + s.FireRunes*fire
}

// AlchProfit is the profit from casting an alchemy spell on one item bought at buyPrice, where runeCost is what that cast's reagents cost (AlchRuneCost).
//
// The easy mistake here is applying GE tax. Alching is not a Grand Exchange sale — the coins come from the spell, not from another player — so no convenience fee is charged on the alch value. Tax applies only to the purchase side if you were the one selling, which you are not.
func AlchProfit(alchValue, runeCost, buyPrice int64) int64 {
	if alchValue <= 0 || buyPrice <= 0 {
		return 0
	}
	return alchValue - runeCost - buyPrice
}

// pct returns part/whole as a percentage, or 0 when whole is 0.
func pct(part, whole int64) float64 {
	if whole == 0 {
		return 0
	}
	return float64(part) / float64(whole) * 100
}
