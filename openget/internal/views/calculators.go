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

package views

import (
	"context"
	"fmt"
	"net/url"
	"sort"
	"strings"
	"time"

	"dreamstation.systems/openget/internal/calc"
	"dreamstation.systems/openget/internal/render"
	"dreamstation.systems/openget/internal/store"
)

// f2pRecipes drops every recipe that touches a members' item.
//
// A method counts as free-to-play only if all of it is: half a plank run is not a money maker, so one members-only input disqualifies the whole row rather than merely annotating it.
func (b *Builder) f2pRecipes(ctx context.Context, rs []calc.Recipe) ([]calc.Recipe, error) {
	if !b.F2POnly {
		return rs, nil
	}
	members, err := b.DB.MembersItems(ctx, store.RecipeItemIDs(rs))
	if err != nil {
		return nil, err
	}
	out := make([]calc.Recipe, 0, len(rs))
	for _, r := range rs {
		f2p := true
		for _, id := range store.RecipeItemIDs([]calc.Recipe{r}) {
			if members[id] {
				f2p = false
				break
			}
		}
		if f2p {
			out = append(out, r)
		}
	}
	return out, nil
}

// recipeCounts is how many methods each family offers, after the free-to-play filter. The cheap grouped count only answers the unfiltered question, so under the toggle the recipes are loaded and counted in Go instead — 138 rows with their ingredient lists, once, on a page that already reads the whole catalogue elsewhere.
func (b *Builder) recipeCounts(ctx context.Context) (map[string]int, error) {
	if !b.F2POnly {
		return b.DB.RecipeKinds(ctx)
	}
	all, err := b.DB.Recipes(ctx, "")
	if err != nil {
		return nil, err
	}
	all, err = b.f2pRecipes(ctx, all)
	if err != nil {
		return nil, err
	}
	counts := map[string]int{}
	for _, r := range all {
		counts[r.Kind]++
	}
	return counts, nil
}

// CalcIndex lists the money-maker calculator families.
func (b *Builder) CalcIndex(ctx context.Context) (*render.Doc, error) {
	counts, err := b.recipeCounts(ctx)
	if err != nil {
		return nil, err
	}
	d := &render.Doc{
		Title:    "Money makers",
		Subtitle: "Money-making methods priced at the current market.",
		Path:     "/calc",
	}
	var items []render.Link
	for _, k := range calc.Kinds {
		n := counts[k.Kind]
		if n == 0 {
			continue
		}
		items = append(items, render.Link{
			Text: k.Title,
			Href: "/calc/" + k.Kind,
			Desc: fmt.Sprintf("%s (%d)", k.Blurb, n),
		})
	}
	if len(items) == 0 {
		d.Add(render.Para{Muted: true, Text: "No calculator family has a method that stays entirely free-to-play."})
	} else {
		d.Add(render.Links{Items: items})
	}
	d.Add(render.Links{Title: "Whole-catalogue calculators", Items: []render.Link{
		{Text: "High alchemy", Href: "/alch", Desc: "every item, alch value against market price"},
		{Text: "Low alchemy", Href: "/alch?spell=low", Desc: "the level 21 spell, 40% of the item's value"},
		{Text: "Store profit", Href: "/store-profit", Desc: "shop shelf against market price"},
		{Text: "GE tax calculator", Href: "/ge-tax-calculator", Desc: "what a sale actually pays out"},
	}})
	d.Add(render.Para{Muted: true, Text: "Inputs are costed at the price you would pay to buy them right now, " +
		"and outputs at the price you would receive selling right now, minus tax."})
	b.f2pMethodNote(d)
	b.addFreshness(ctx, d)
	return d, nil
}

// f2pMethodNote is the recipe-page counterpart of f2pNote: the toggle is worded in terms of items, so a page that has quietly dropped whole methods owes the reader the rule it used.
func (b *Builder) f2pMethodNote(d *render.Doc) {
	if b.F2POnly {
		d.Note("Methods needing a members' item at any step are hidden. " +
			"That is an item test and not a skill or location one: a method whose items are all " +
			"free-to-play may still need members access to actually perform, the blast furnace being the " +
			"obvious case. Untick \"Free-to-play only\" in the header to show everything.")
	}
}

// CalcKind builds the table for one calculator family.
func (b *Builder) CalcKind(ctx context.Context, kind string) (*render.Doc, error) {
	recipes, err := b.DB.Recipes(ctx, kind)
	if err != nil {
		return nil, err
	}
	if len(recipes) == 0 {
		return nil, store.ErrNotFound
	}
	// Filtered after the not-found check, so a family with no free-to-play method renders as an empty table saying why rather than as a 404 that claims the calculator does not exist.
	if recipes, err = b.f2pRecipes(ctx, recipes); err != nil {
		return nil, err
	}
	pb, err := b.DB.PriceBookFor(ctx, store.RecipeItemIDs(recipes))
	if err != nil {
		return nil, err
	}
	results := calc.EvaluateAll(recipes, pb)

	title := calc.KindTitle(kind)
	blurb := ""
	for _, k := range calc.Kinds {
		if k.Kind == kind {
			blurb = k.Blurb
		}
	}
	d := &render.Doc{Title: title, Subtitle: blurb, Path: "/calc/" + kind}

	// "No recipes configured" would be a plain untruth on a family the toggle has just emptied — the recipes are configured, they are being withheld.
	empty := "No recipes configured for this family."
	if b.F2POnly && len(results) == 0 {
		empty = "Every method in this family needs a members' item."
	}
	t := render.Table{
		Empty: empty,
		Columns: []render.Column{
			{Title: "Method", Retro: true, RowHeader: true},
			{Title: "Cost", Align: render.AlignRight, Retro: true},
			{Title: "Revenue", Align: render.AlignRight, Hint: "After the 2% GE tax on each item sold"},
			{Title: "Tax", Align: render.AlignRight},
			{Title: "Profit", Align: render.AlignRight, Retro: true},
			{Title: "ROI", Align: render.AlignRight, Retro: true},
			{Title: "gp/hour", Align: render.AlignRight, Hint: "Profit times a typical action rate"},
		},
	}
	anyRate := false
	for _, r := range results {
		if r.Recipe.Extra.PerHour > 0 {
			anyRate = true
		}
		profit := render.Cell{Text: render.GP(r.Profit), Tone: render.Tone(r.Profit)}
		roi := render.Cell{Text: render.PctPlain(r.ROI), Tone: render.ToneF(r.ROI)}
		perHour := render.C(render.Dash)
		if r.PerHour != 0 {
			perHour = render.Cell{Text: render.GPShort(r.PerHour), Tone: render.Tone(r.PerHour)}
		}
		if r.Incomplete {
			// Never print a profit computed from a price we do not have.
			profit = render.C("no price")
			roi = render.C(render.Dash)
			perHour = render.C(render.Dash)
		}
		t.Rows = append(t.Rows, []render.Cell{
			render.CL(r.Recipe.Name, "/calc/"+kind+"/"+r.Recipe.ID),
			render.C(render.GP(r.Cost)),
			render.C(render.GP(r.Revenue)),
			render.C(render.GP(r.Tax)),
			profit, roi, perHour,
		})
	}
	d.Add(t)
	if anyRate {
		d.Note("gp/hour uses a typical action rate for the method and assumes you never wait on a buy offer. " +
			"Treat it as an upper bound.")
	}
	d.Note("Rows marked \"no price\" reference an item nobody has traded recently, so no profit can be computed for them honestly.")
	b.f2pMethodNote(d)
	b.addFreshness(ctx, d)
	return d, nil
}

// CalcRecipe builds the breakdown for a single recipe.
func (b *Builder) CalcRecipe(ctx context.Context, id string) (*render.Doc, error) {
	r, err := b.DB.Recipe(ctx, id)
	if err != nil {
		return nil, err
	}
	pb, err := b.DB.PriceBookFor(ctx, store.RecipeItemIDs([]calc.Recipe{*r}))
	if err != nil {
		return nil, err
	}
	d := b.CalcRecipeDoc(*r, pb)
	b.addFreshness(ctx, d)
	return d, nil
}

// CalcRecipeDoc renders one recipe against an already-loaded price book.
//
// Split out of CalcRecipe so a caller holding many recipes can fetch ONE price book for the lot, rather than a separate price book query per recipe. See openget.txt, "NOTE ON THE TWO TREE LAYOUTS".
func (b *Builder) CalcRecipeDoc(r calc.Recipe, pb *store.PriceBook) *render.Doc {
	res := calc.Evaluate(r, pb)

	d := &render.Doc{Title: r.Name, Subtitle: calc.KindTitle(r.Kind), Path: "/calc/" + r.Kind + "/" + r.ID}

	lines := render.Table{
		Caption: "Breakdown",
		Columns: []render.Column{
			{Title: "Side", Retro: true},
			{Title: "Item", Retro: true},
			{Title: "Qty", Align: render.AlignRight, Retro: true},
			{Title: "Unit", Align: render.AlignRight, Retro: true},
			{Title: "Tax", Align: render.AlignRight},
			{Title: "Total", Align: render.AlignRight, Retro: true},
		},
	}
	add := func(side string, l calc.Line, sign int64) {
		unit := render.GP(l.Unit)
		if l.Missing {
			unit = "not observed"
		}
		lines.Rows = append(lines.Rows, []render.Cell{
			render.C(side),
			render.CL(l.Name, ItemPath(l.ItemID)),
			render.C(trimQty(l.Qty)),
			render.C(unit),
			render.C(render.GP(l.Tax)),
			render.Cell{Text: render.GP(l.Total * sign), Tone: int(sign)},
		})
	}
	for _, l := range res.Inputs {
		add("buy", l, -1)
	}
	if r.Extra.FeeGP > 0 {
		lines.Rows = append(lines.Rows, []render.Cell{
			render.C("fee"), render.C("service charge"), render.C("1"),
			render.C(render.GP(r.Extra.FeeGP)), render.C("0"),
			render.Cell{Text: render.GP(-r.Extra.FeeGP), Tone: -1},
		})
	}
	for _, l := range res.Outputs {
		add("sell", l, 1)
	}
	d.Add(lines)

	f := render.Facts{Title: "Result", Pairs: []render.KV{
		{Key: "Total cost", Value: render.GP(res.Cost)},
		{Key: "Total revenue", Value: render.GP(res.Revenue), Hint: "After GE tax"},
		{Key: "GE tax paid", Value: render.GP(res.Tax)},
		{Key: "Profit per action", Value: render.GP(res.Profit), Tone: render.Tone(res.Profit)},
		{Key: "ROI", Value: render.PctPlain(res.ROI), Tone: render.ToneF(res.ROI)},
	}}
	if res.PerHour != 0 {
		f.Pairs = append(f.Pairs, render.KV{
			Key: "Profit per hour", Value: render.GP(res.PerHour), Tone: render.Tone(res.PerHour),
			Hint: fmt.Sprintf("At %d actions per hour", r.Extra.PerHour)})
	}
	if res.GPPerXP != 0 {
		f.Pairs = append(f.Pairs, render.KV{
			Key: "gp per xp", Value: fmt.Sprintf("%.2f", res.GPPerXP),
			Hint: fmt.Sprintf("%.1f xp per action", r.Extra.XP)})
	}
	if res.Limiting != "" {
		f.Pairs = append(f.Pairs, render.KV{Key: "Binding buy limit", Value: res.Limiting})
	}
	if r.SkillReqs != "" {
		f.Pairs = append(f.Pairs, render.KV{Key: "Requirements", Value: r.SkillReqs})
	}
	d.Add(f)

	if res.Incomplete {
		d.Add(render.Para{Muted: true, Text: "At least one item in this recipe has no recently observed price, " +
			"so the totals above are incomplete and should not be traded on."})
	}
	if r.Notes != "" {
		d.Add(render.Para{Text: r.Notes})
	}
	if r.Extra.Untaxed {
		d.Note("The output of this method is not sold on the Grand Exchange, so no convenience fee applies.")
	}
	d.Add(render.Links{Items: []render.Link{
		{Text: "All " + strings.ToLower(calc.KindTitle(r.Kind)) + " methods", Href: "/calc/" + r.Kind},
		{Text: "All money makers", Href: "/calc"},
	}})
	return d
}

func trimQty(q float64) string {
	if q == float64(int64(q)) {
		return fmt.Sprintf("%d", int64(q))
	}
	return fmt.Sprintf("%.2f", q)
}

// ---------------------------------------------------------------------------
// GE tax calculator
// ---------------------------------------------------------------------------

// TaxCalc builds the standalone tax calculator, optionally for a given price and item.
func (b *Builder) TaxCalc(ctx context.Context, price int64, qty int64, itemID int) (*render.Doc, error) {
	d := &render.Doc{
		Title:    "Grand Exchange tax calculator",
		Subtitle: "What a sale actually pays out after the 2% convenience fee.",
		Path:     "/ge-tax-calculator",
	}
	if qty <= 0 {
		qty = 1
	}

	itemName := "a taxed item"
	if itemID > 0 {
		if it, err := b.DB.GetItem(ctx, itemID); err == nil {
			itemName = it.Name
		}
	}

	d.Add(render.Form{
		Action: "/ge-tax-calculator", Method: "get", Prompt: "Sale price per item",
		Fields: []render.Field{
			{Name: "price", Label: "Price per item (gp)", Kind: "number", Value: fmt.Sprint(price)},
			{Name: "qty", Label: "Quantity", Kind: "number", Value: fmt.Sprint(qty)},
			{Name: "item", Label: "Item ID (optional, to check the exempt list)", Kind: "number",
				Value: optInt(itemID), Hint: "Leave blank to assume the item is taxable"},
		},
		Submit: "Work it out",
	})

	if price > 0 {
		unitTax := calc.Tax(itemID, price)
		net := price - unitTax
		d.Add(render.Facts{Title: "Result", Pairs: []render.KV{
			{Key: "Item", Value: itemName},
			{Key: "Listed price", Value: render.GP(price) + " gp each"},
			{Key: "Tax per item", Value: render.GP(unitTax) + " gp"},
			{Key: "You receive", Value: render.GP(net) + " gp each", Tone: 1},
			{Key: "Quantity", Value: render.GP(qty)},
			{Key: "Total tax", Value: render.GP(unitTax*qty) + " gp"},
			{Key: "Total received", Value: render.GP(net*qty) + " gp", Tone: 1},
		}})
		if itemID > 0 && calc.IsExempt(itemID) {
			d.Add(render.Para{Text: itemName + " is on the exemption list, so no convenience fee is charged at all."})
		}
		if price >= 50 && price%50 == 0 {
			d.Add(render.Para{Muted: true, Text: fmt.Sprintf(
				"Because the tax rounds down, listing at %s gp and at %s gp both pay out %s gp. "+
					"Undercutting a sell offer priced at an exact multiple of 50 is effectively free.",
				render.GP(price), render.GP(price-1), render.GP(net))})
		}
	}

	d.Add(render.Heading{Level: 2, Text: "The rules"})
	d.Add(render.Facts{Pairs: []render.KV{
		{Key: "Rate", Value: "2% of the sale price"},
		{Key: "Paid by", Value: "the seller (buyer's listed price is post-tax)"},
		{Key: "Cap", Value: "5,000,000 gp per item, reached at a price of 250,000,000 gp"},
		{Key: "Rounding", Value: "down to the nearest whole coin, so anything under 50 gp is untaxed"},
	}})

	d.Add(render.Heading{Level: 2, Text: "Exempt items", Anchor: "exempt"})
	d.Add(render.Para{Text: "These items pay no convenience fee. The list is mirrored from the OSRS Wiki and " +
		"was last checked on 2026-08-04."})

	ids := calc.ExemptIDs()
	names := make([]string, 0, len(ids))
	for _, id := range ids {
		if it, err := b.DB.GetItem(ctx, id); err == nil {
			names = append(names, it.Name)
			continue
		}
		names = append(names, fmt.Sprintf("item %d", id))
	}
	sort.Strings(names)
	et := render.Table{Columns: []render.Column{{Title: "Exempt item", Retro: true}}}
	for _, n := range names {
		et.Rows = append(et.Rows, []render.Cell{render.C(n)})
	}
	d.Add(et)
	return d, nil
}

func optInt(v int) string {
	if v <= 0 {
		return ""
	}
	return fmt.Sprint(v)
}

// ---------------------------------------------------------------------------
// Alchemy
// ---------------------------------------------------------------------------

// AlchOptions selects which alchemy spell to price and how to cost its runes.
type AlchOptions struct {
	// Spell is a calc.AlchSpell key: "high" (the default) or "low".
	Spell string
	// ChargeFire includes the spell's fire runes in the cast cost. Off by default, because any fire staff or tome of fire supplies them and that is how nearly everyone alchs — charging for them by default would understate the profit on every row of the page.
	ChargeFire bool
	Limit      int
}

// AlchPath is the canonical URL for one set of alchemy options.
func AlchPath(o AlchOptions) string {
	q := url.Values{}
	if s := calc.AlchSpellByKey(o.Spell); s.Key != calc.AlchSpells[0].Key {
		q.Set("spell", s.Key)
	}
	if o.ChargeFire {
		q.Set("firerunes", "1")
	}
	if len(q) == 0 {
		return "/alch"
	}
	return "/alch?" + q.Encode()
}

// AlchList builds the alchemy profit table across the whole catalogue.
func (b *Builder) AlchList(ctx context.Context, o AlchOptions) (*render.Doc, error) {
	spell := calc.AlchSpellByKey(o.Spell)
	nature := b.buyPrice(ctx, calc.NatureRuneID)
	fire := b.buyPrice(ctx, calc.FireRuneID)
	runeCost := calc.AlchRuneCost(spell, nature, fire, o.ChargeFire)

	sortKey := "alch"
	if spell.Key == "low" {
		sortKey = "alch_low"
	}
	items, _, err := b.DB.ListItems(ctx, b.filter(store.ListOptions{
		Sort: sortKey, Desc: true, Limit: o.Limit, Tradeable: true, MinVolume: 10,
	}))
	if err != nil {
		return nil, err
	}

	d := &render.Doc{
		Title:    spell.Title + " profit",
		Subtitle: "Cast " + spell.Name + " on an item bought at the market price.",
		Path:     AlchPath(o),
	}

	// On a checkbox, Field.Value carries the checked state rather than the submitted value, which htmlField hardcodes to 1.
	checked := ""
	if o.ChargeFire {
		checked = "1"
	}
	d.Add(render.Form{
		Action: "/alch", Method: "get", Submit: "Update", WebOnly: true,
		Fields: []render.Field{
			{Name: "spell", Label: "Spell", Kind: "select", Options: alchSpellOptions(spell)},
			{Name: "firerunes", Label: "Pay for fire runes", Kind: "checkbox", Value: checked,
				Hint: "Tick if you are not casting with a fire staff"},
		},
	})

	runes := render.Facts{Pairs: []render.KV{
		{Key: "Nature rune", Value: render.GP(nature) + " gp", Link: ItemPath(calc.NatureRuneID)},
	}}
	if o.ChargeFire {
		runes.Pairs = append(runes.Pairs, render.KV{
			Key: "Fire rune", Value: render.GP(fire) + " gp", Link: ItemPath(calc.FireRuneID)})
	}
	runes.Pairs = append(runes.Pairs,
		render.KV{Key: "Cost per cast", Value: render.GP(runeCost) + " gp", Hint: runeHint(spell, o.ChargeFire)},
		render.KV{Key: "Formula", Value: strings.ToLower(spell.Short) + " value − cost per cast − buy price"})
	d.Add(runes)

	t := render.Table{
		Caption: spell.Title + " profit",
		Columns: []render.Column{
			{Title: "Item", Retro: true, RowHeader: true},
			{Title: "Buy at", Align: render.AlignRight, Retro: true},
			{Title: spell.Short, Align: render.AlignRight, Retro: true},
			{Title: "Profit", Align: render.AlignRight, Retro: true},
			{Title: "Limit", Align: render.AlignRight},
			{Title: "Vol 24h", Align: render.AlignRight, Retro: true},
		},
	}
	for _, it := range items {
		value := AlchValue(it, spell)
		// An item with no alch value at all is not a zero-profit alch, it is a row with no answer — and the sort puts those last, so skipping them only ever trims the tail.
		if value == nil || *value <= 0 || it.High == nil {
			continue
		}
		profit := calc.AlchProfit(*value, runeCost, *it.High)
		t.Rows = append(t.Rows, []render.Cell{
			render.CL(it.Name, ItemPath(it.ID)),
			render.C(render.GPOpt(it.High)),
			render.C(render.GP(*value)),
			render.Cell{Text: render.GP(profit), Tone: render.Tone(profit)},
			render.C(limitText(it)),
			render.C(render.GPShort(it.AvgVol24h)),
		})
	}
	d.Add(t)

	// A footnote rather than only the "Cost per cast" hint: hints are a title attribute on the web and nothing at all on Gopher and Gemini, and this is the assumption the whole page's numbers rest on.
	if o.ChargeFire {
		d.Note("%s burns %d fire runes per cast, charged here at the market price.", spell.Name, spell.FireRunes)
	} else {
		d.Note("Fire runes are not charged for: %s burns %d of them and any fire staff or tome of fire "+
			"supplies them free.", spell.Name, spell.FireRunes)
	}
	d.Note("The item is costed at its instant-buy price, on the assumption you want it now rather than after a wait.")
	b.f2pNote(d)
	b.addFreshness(ctx, d)
	return d, nil
}

// AlchValue is an item's alch value for one spell, nil when the mapping does not publish one. The item page and the /alch table both need this mapping and must not each carry their own copy of it.
func AlchValue(it *store.Item, s calc.AlchSpell) *int64 {
	if s.Key == "low" {
		return it.LowAlch
	}
	return it.HighAlch
}

// alchSpellOptions builds the spell picker with sel marked selected.
func alchSpellOptions(sel calc.AlchSpell) []render.Option {
	out := make([]render.Option, 0, len(calc.AlchSpells))
	for _, s := range calc.AlchSpells {
		out = append(out, render.Option{Value: s.Key, Label: s.Name, Selected: s.Key == sel.Key})
	}
	return out
}

// runeHint spells out what "cost per cast" is made of.
func runeHint(s calc.AlchSpell, chargeFire bool) string {
	if chargeFire {
		return fmt.Sprintf("1 nature rune and %d fire runes", s.FireRunes)
	}
	return fmt.Sprintf("1 nature rune; a staff supplies the %d fire runes", s.FireRunes)
}

// buyPrice is what one of an item costs to buy right now, or 0 when the API has not reported a price for it.
func (b *Builder) buyPrice(ctx context.Context, id int) int64 {
	it, err := b.DB.GetItem(ctx, id)
	if err != nil || it == nil || it.High == nil {
		return 0
	}
	return *it.High
}

// StoreMinVolume is the 24-hour volume a shop item must trade before it earns a row.
//
// Shop stock is small and slow. Without a floor the page fills with novelty cosmetics that a shop sells five of and the market absorbs three of per day: a genuine margin on a thing you cannot repeat is not a money-making method, and it crowds out the ones that are.
const StoreMinVolume = 100

// StoreProfit lists items a shop sells for less than the Grand Exchange pays.
//
// Not a recipe family: the shop inventories cover a thousand items across five hundred shops, so it is a whole-catalogue query rather than a hand-listed set.
//
// The shop price here is a real shop's real price, from the wiki's storeline bucket by way of shop_offers — not items.value, the item's base value. See openget.txt, SHOP INVENTORIES.
func (b *Builder) StoreProfit(ctx context.Context, limit int) (*render.Doc, error) {
	// Hand-written SQL rather than ListItems, so the site-wide toggle is spelt out here instead of arriving through b.filter.
	members := ""
	if b.F2POnly {
		members = " AND i.members = 0"
	}
	// One row per item, at its cheapest shelf: an item on sale in nine shops is one method, not nine. min(price) picks the shelf, and the window function carries the matching shop and stock along with it.
	rows, err := b.DB.Reader().QueryContext(ctx, `
		WITH cheapest AS (
			SELECT item_id, shop, price, stock,
			       row_number() OVER (PARTITION BY item_id ORDER BY price, shop) AS rn
			  FROM shop_offers
		)
		SELECT i.id, i.name, c.shop, c.price, c.stock,
		       s.high, s.tax, COALESCE(s.avg_vol_24h,0)
		  FROM cheapest c
		  JOIN items i      ON i.id = c.item_id
		  JOIN item_stats s ON s.item_id = c.item_id
		 WHERE c.rn = 1 AND i.removed = 0
		   AND s.high IS NOT NULL AND s.avg_vol_24h >= ?
		   AND (s.high - COALESCE(s.tax,0) - c.price) > 0`+members+`
		 ORDER BY (s.high - COALESCE(s.tax,0) - c.price) DESC
		 LIMIT ?`, StoreMinVolume, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	d := &render.Doc{
		Title:    "Store profit",
		Subtitle: "Items a shop sells for less than the Grand Exchange pays.",
		Path:     "/store-profit",
	}
	t := render.Table{
		Columns: []render.Column{
			{Title: "Item", Retro: true, RowHeader: true},
			{Title: "Shop", Retro: true},
			{Title: "Shop price", Align: render.AlignRight, Retro: true},
			{Title: "Sells for", Align: render.AlignRight, Retro: true},
			{Title: "Tax", Align: render.AlignRight},
			{Title: "Profit", Align: render.AlignRight, Retro: true},
			{Title: "Stock", Align: render.AlignRight},
			{Title: "Vol 24h", Align: render.AlignRight, Retro: true},
		},
	}
	n := 0
	for rows.Next() {
		var id int
		var name, shop string
		var price, stock, high, tax, vol int64
		if err := rows.Scan(&id, &name, &shop, &price, &stock, &high, &tax, &vol); err != nil {
			return nil, err
		}
		st := render.GP(stock)
		if stock == store.StockUnlimited {
			st = "unlimited"
		}
		profit := high - tax - price
		t.Rows = append(t.Rows, []render.Cell{
			render.CL(name, ItemPath(id)),
			render.C(shop),
			render.C(render.GP(price)),
			render.C(render.GP(high)),
			render.C(render.GP(tax)),
			render.Cell{Text: render.GP(profit), Tone: render.Tone(profit)},
			render.C(st),
			render.C(render.GPShort(vol)),
		})
		n++
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if n == 0 {
		// Distinguishable from "no item is profitable today": the table is populated by a separate daily job against a separate upstream, and an empty one usually means that job has not run.
		cnt, _ := b.DB.ShopOfferCount(ctx)
		if cnt == 0 {
			d.Note("Shop inventories have not been fetched yet, so this page has nothing to rank.")
			return d, nil
		}
	}
	d.Add(t)
	d.Note("Shop prices rise as you buy the shelf down and fall back as it restocks, so the price shown is what the " +
		"first one costs, not the hundredth. Stock is what the shop holds when full.")
	d.Note("Items trading under %s a day are left out.", render.GPShort(StoreMinVolume))
	b.f2pNote(d)
	b.addFreshness(ctx, d)
	return d, nil
}

// ---------------------------------------------------------------------------
// Market indices
// ---------------------------------------------------------------------------

// IndicesPage lists every index with its current level.
func (b *Builder) IndicesPage(ctx context.Context) (*render.Doc, error) {
	idx, err := b.DB.Indices(ctx)
	if err != nil {
		return nil, err
	}
	d := &render.Doc{
		Title:    "Market indices",
		Subtitle: "Weighted baskets of related items, each rebased to 100 when tracking began.",
		Path:     "/indices",
	}
	t := render.Table{
		Columns: []render.Column{
			{Title: "Index", Retro: true, RowHeader: true},
			{Title: "Items", Align: render.AlignRight, Retro: true},
			{Title: "Level", Align: render.AlignRight, Retro: true},
			{Title: "Change", Align: render.AlignRight, Retro: true},
		},
		Empty: "No index history recorded yet — indices start accumulating from the first poll.",
	}
	for _, i := range idx {
		pts, err := b.DB.IndexSeries(ctx, i.ID, 0)
		if err != nil {
			return nil, err
		}
		level, change := render.Dash, render.Dash
		tone := 0
		if n := len(pts); n > 0 {
			level = fmt.Sprintf("%.1f", pts[n-1].Value)
			if n > 1 {
				delta := pts[n-1].Value - pts[0].Value
				change = render.Pct(delta)
				tone = render.ToneF(delta)
			}
		}
		t.Rows = append(t.Rows, []render.Cell{
			render.CL(i.Name, "/indices/"+i.ID),
			render.C(fmt.Sprint(len(i.Members))),
			render.C(level),
			render.Cell{Text: change, Tone: tone},
		})
	}
	d.Add(t)
	d.Add(render.Para{Muted: true, Text: "Constituents are equally weighted unless stated otherwise. " +
		"Equal weighting is used because it can be checked by hand against the published list."})
	b.addFreshness(ctx, d)
	return d, nil
}

// IndexPage builds one index's page, including its full constituent list.
func (b *Builder) IndexPage(ctx context.Context, id string) (*render.Doc, error) {
	i, err := b.DB.IndexByID(ctx, id)
	if err != nil {
		return nil, err
	}
	d := &render.Doc{Title: i.Name + " index", Subtitle: i.Blurb, Path: "/indices/" + i.ID}

	pts, err := b.DB.IndexSeries(ctx, i.ID, 0)
	if err != nil {
		return nil, err
	}
	if len(pts) > 0 {
		var xy []render.XY
		for _, p := range pts {
			xy = append(xy, render.XY{X: p.TS, Y: p.Value})
		}
		d.Add(render.Chart{
			Title:  i.Name + " index (100 = first reading)",
			Height: 240,
			Series: []render.Series{{Name: i.Name, Points: xy, Colour: "#ffbb22"}},
		})
		d.Add(render.Facts{Pairs: []render.KV{
			{Key: "Current level", Value: fmt.Sprintf("%.2f", pts[len(pts)-1].Value)},
			{Key: "Readings", Value: fmt.Sprint(len(pts))},
			{Key: "Tracking since", Value: time.Unix(pts[0].TS, 0).UTC().Format("2006-01-02 15:04 UTC")},
		}})
	} else {
		d.Add(render.Para{Muted: true, Text: "No readings recorded yet. Indices are sampled on each price poll."})
	}

	ids := make([]int, 0, len(i.Members))
	for _, m := range i.Members {
		ids = append(ids, m.ItemID)
	}
	pb, err := b.DB.PriceBookFor(ctx, ids)
	if err != nil {
		return nil, err
	}
	t := render.Table{
		Caption: "Constituents",
		Columns: []render.Column{
			{Title: "Item", Retro: true, RowHeader: true},
			{Title: "Weight", Align: render.AlignRight, Retro: true},
			{Title: "Price", Align: render.AlignRight, Retro: true},
		},
	}
	for _, m := range i.Members {
		price := render.Dash
		if p, ok := pb.Sell(m.ItemID); ok {
			price = render.GP(p)
		}
		t.Rows = append(t.Rows, []render.Cell{
			render.CL(pb.Name(m.ItemID), ItemPath(m.ItemID)),
			render.C(fmt.Sprintf("%.2f", m.Weight)),
			render.C(price),
		})
	}
	d.Add(t)
	d.Add(render.Links{Items: []render.Link{{Text: "All indices", Href: "/indices"}}})
	b.addFreshness(ctx, d)
	return d, nil
}
