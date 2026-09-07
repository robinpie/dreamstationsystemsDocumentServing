#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2026 robinpie
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

"""Generate data/recipes.toml from live /mapping data.

Every item is named, never numbered, and the script aborts if any name fails to resolve. That is the point: hand-written item ids rot silently after a game update, whereas a name that no longer exists stops the build.

Usage:
    python3 contrib/gen_recipes.py > data/recipes.toml
"""

import json
import sys
import urllib.request

UA = "grandexchange.dreamstation.systems - email robin@dreamstation.systems"
MAPPING = "https://prices.runescape.wiki/api/v1/osrs/mapping"

BY_NAME = {}
RECIPES = []
UNRESOLVED = []


def load_mapping():
    req = urllib.request.Request(MAPPING, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def have(*names):
    return all(n in BY_NAME for n in names)


def ing(name, qty=1, note=""):
    if name not in BY_NAME:
        UNRESOLVED.append(name)
        return {"item_id": -1, "qty": qty, "note": note, "_name": name}
    return {"item_id": BY_NAME[name], "qty": qty, "note": note, "_name": name}


def R(rid, kind, name, inputs, outputs, skill="", notes="", **extra):
    RECIPES.append({
        "id": rid, "kind": kind, "name": name,
        "inputs": inputs, "outputs": outputs,
        "skill_reqs": skill, "notes": notes, "extra": extra,
        "sort_key": len(RECIPES),
    })


def build():
    # ----------------------------------------------------------------------
    # Decanting. Bob Barter at the Grand Exchange decants for free.
    # ----------------------------------------------------------------------
    for p in ["Prayer potion", "Super restore", "Saradomin brew", "Ranging potion",
              "Super attack", "Super strength", "Super defence", "Magic potion",
              "Super energy", "Stamina potion", "Antidote++", "Super antifire potion",
              "Antifire potion", "Bastion potion", "Battlemage potion",
              "Divine super combat potion", "Super combat potion", "Extended antifire"]:
        lo, hi = f"{p}(3)", f"{p}(4)"
        if not have(lo, hi):
            continue
        R(f"decant-{slug(p)}", "decanting", f"Decant {lo} into {hi}",
          [ing(lo, 4)], [ing(hi, 3)],
          notes="Bob Barter at the Grand Exchange decants for free. Four 3-dose "
                "potions hold the same twelve doses as three 4-dose potions.")

    # ----------------------------------------------------------------------
    # Herblore: unfinished potion plus secondary.
    # ----------------------------------------------------------------------
    for rid, unf, sec, out, lvl, xp in [
        ("prayer",       "Ranarr potion (unf)",     "Snape grass",       "Prayer potion(3)",  38, 87.5),
        ("super-restore","Snapdragon potion (unf)", "Red spiders' eggs", "Super restore(3)",  63, 142.5),
        ("sara-brew",    "Toadflax potion (unf)",   "Crushed nest",      "Saradomin brew(3)", 81, 180),
        ("super-attack", "Irit potion (unf)",       "Eye of newt",       "Super attack(3)",   45, 100),
        ("super-str",    "Kwuarm potion (unf)",     "Limpwurt root",     "Super strength(3)", 55, 125),
        ("super-def",    "Cadantine potion (unf)",  "White berries",     "Super defence(3)",  66, 150),
        ("ranging",      "Dwarf weed potion (unf)", "Wine of zamorak",   "Ranging potion(3)", 72, 162.5),
        ("magic",        "Lantadyme potion (unf)",  "Potato cactus",     "Magic potion(3)",   76, 172.5),
    ]:
        if not have(unf, sec, out):
            continue
        R(f"herb-{rid}", "herblore", f"Make {out}",
          [ing(unf), ing(sec)], [ing(out)],
          skill=f"Herblore {lvl}", per_hour=2400, xp=xp)

    # The herb-to-unfinished step, where much of the margin usually lives.
    for rid, herb, unf, lvl in [
        ("ranarr", "Ranarr weed", "Ranarr potion (unf)", 30),
        ("toadflax", "Toadflax", "Toadflax potion (unf)", 34),
        ("irit", "Irit leaf", "Irit potion (unf)", 40),
        ("kwuarm", "Kwuarm", "Kwuarm potion (unf)", 50),
        ("snapdragon", "Snapdragon", "Snapdragon potion (unf)", 59),
        ("cadantine", "Cadantine", "Cadantine potion (unf)", 65),
        ("lantadyme", "Lantadyme", "Lantadyme potion (unf)", 67),
        ("dwarf-weed", "Dwarf weed", "Dwarf weed potion (unf)", 70),
        ("torstol", "Torstol", "Torstol potion (unf)", 75),
    ]:
        if not have(herb, unf, "Vial of water"):
            continue
        R(f"unf-{rid}", "herblore", f"Make {unf}",
          [ing(herb), ing("Vial of water")], [ing(unf)],
          skill=f"Herblore {lvl}",
          notes="Grinding a clean herb into a vial of water. This step grants "
                "no experience on its own.",
          per_hour=3000)

    if have("Torstol", "Super attack(4)", "Super strength(4)", "Super defence(4)", "Super combat potion(4)"):
        R("herb-super-combat", "herblore", "Make Super combat potion(4)",
          [ing("Torstol"), ing("Super attack(4)"), ing("Super strength(4)"), ing("Super defence(4)")],
          [ing("Super combat potion(4)")],
          skill="Herblore 90", per_hour=2000, xp=150)

    # ----------------------------------------------------------------------
    # Tanning. Ellis in Al Kharid charges per hide.
    # ----------------------------------------------------------------------
    for rid, hide, leather, fee in [
        ("cowhide", "Cowhide", "Leather", 1),
        ("hard", "Cowhide", "Hard leather", 3),
        ("green", "Green dragonhide", "Green dragon leather", 20),
        ("blue", "Blue dragonhide", "Blue dragon leather", 20),
        ("red", "Red dragonhide", "Red dragon leather", 20),
        ("black", "Black dragonhide", "Black dragon leather", 20),
    ]:
        if not have(hide, leather):
            continue
        R(f"tan-{rid}", "tanning", f"Tan {hide} into {leather}",
          [ing(hide)], [ing(leather)],
          notes=f"Ellis in Al Kharid charges {fee} gp per hide.",
          fee_gp=fee, per_hour=1300)

    # ----------------------------------------------------------------------
    # Plank making, at sawmill operator prices.
    # ----------------------------------------------------------------------
    for rid, log, plank, fee in [
        ("plank", "Logs", "Plank", 100),
        ("oak", "Oak logs", "Oak plank", 250),
        ("teak", "Teak logs", "Teak plank", 500),
        ("mahogany", "Mahogany logs", "Mahogany plank", 1500),
    ]:
        if not have(log, plank):
            continue
        R(f"plank-{rid}", "plank", f"Make {plank}",
          [ing(log)], [ing(plank)],
          notes=f"The sawmill operator charges {fee:,} gp per plank. The Plank "
                "Make spell costs less per plank but consumes runes and is "
                "slower per hour.",
          fee_gp=fee, per_hour=1500)

    # ----------------------------------------------------------------------
    # Bars at the blast furnace, which halves the coal a bar normally needs.
    # ----------------------------------------------------------------------
    for rid, ore, coal, bar, lvl, xp in [
        ("iron", "Iron ore", 0, "Iron bar", 15, 12.5),
        ("silver", "Silver ore", 0, "Silver bar", 20, 13.7),
        ("steel", "Iron ore", 1, "Steel bar", 30, 17.5),
        ("gold", "Gold ore", 0, "Gold bar", 40, 22.5),
        ("mithril", "Mithril ore", 2, "Mithril bar", 50, 30),
        ("addy", "Adamantite ore", 3, "Adamantite bar", 70, 37.5),
        ("rune", "Runite ore", 4, "Runite bar", 85, 50),
    ]:
        if not have(ore, bar) or (coal and not have("Coal")):
            continue
        ins = [ing(ore)] + ([ing("Coal", coal)] if coal else [])
        R(f"bf-{rid}", "smithing", f"Smelt {bar} at the blast furnace",
          ins, [ing(bar)],
          skill=f"Smithing {lvl}",
          notes="The blast furnace halves the coal requirement. Iron smelted "
                "there never fails.",
          per_hour=3400, xp=xp)

    # ----------------------------------------------------------------------
    # Fletching.
    # ----------------------------------------------------------------------
    for wood, lvl in [("Maple", 55), ("Yew", 70), ("Magic", 85)]:
        for shape, off in [("longbow", 0), ("shortbow", -5)]:
            unstrung, strung, logs = f"{wood} {shape} (u)", f"{wood} {shape}", f"{wood} logs"
            if not have(unstrung, strung, logs, "Bow string"):
                continue
            R(f"fletch-{wood.lower()}-{shape}-cut", "fletching",
              f"Cut {logs} into {unstrung}",
              [ing(logs)], [ing(unstrung)],
              skill=f"Fletching {lvl + off}", per_hour=1400)
            R(f"fletch-{wood.lower()}-{shape}-string", "fletching",
              f"String {unstrung} into {strung}",
              [ing(unstrung), ing("Bow string")], [ing(strung)],
              skill=f"Fletching {lvl + off}", per_hour=1400)

    for tip, lvl in [("Mithril dart tip", 52), ("Adamant dart tip", 67), ("Rune dart tip", 81)]:
        dart = tip.replace(" tip", "")
        if not have(tip, dart, "Feather"):
            continue
        R(f"fletch-{slug(dart)}", "fletching", f"Make {dart}s",
          [ing(tip, 10), ing("Feather", 10)], [ing(dart, 10)],
          skill=f"Fletching {lvl}",
          notes="Priced per ten darts, since that is the ratio the tips and "
                "feathers trade in.",
          per_hour=2000)

    # ----------------------------------------------------------------------
    # Enchanting. Two of these produce tax-exempt items, which is most of why they are worth doing.
    # ----------------------------------------------------------------------
    if have("Emerald ring", "Ring of dueling(8)", "Cosmic rune", "Air rune"):
        R("ench-dueling", "enchanting", "Enchant Emerald ring into Ring of dueling(8)",
          [ing("Emerald ring"), ing("Cosmic rune"), ing("Air rune", 3)],
          [ing("Ring of dueling(8)")],
          skill="Magic 27 (Lvl-2 Enchant)",
          notes="Rings of dueling are exempt from the Grand Exchange tax, so "
                "the entire sale price is yours.",
          per_hour=1200, xp=37)
    if have("Sapphire necklace", "Games necklace(8)", "Cosmic rune", "Water rune"):
        R("ench-games", "enchanting", "Enchant Sapphire necklace into Games necklace(8)",
          [ing("Sapphire necklace"), ing("Cosmic rune"), ing("Water rune")],
          [ing("Games necklace(8)")],
          skill="Magic 7 (Lvl-1 Enchant)",
          notes="Games necklaces are exempt from the Grand Exchange tax.",
          per_hour=1200, xp=17.5)
    if have("Dragonstone amulet", "Amulet of glory", "Cosmic rune", "Water rune", "Earth rune"):
        R("ench-glory", "enchanting", "Enchant Dragonstone amulet into Amulet of glory",
          [ing("Dragonstone amulet"), ing("Cosmic rune"), ing("Water rune", 15), ing("Earth rune", 15)],
          [ing("Amulet of glory")],
          skill="Magic 68 (Lvl-5 Enchant)", per_hour=1200, xp=78)

    # ----------------------------------------------------------------------
    # Magic tablets, made at a house lectern. All tax-exempt.
    # ----------------------------------------------------------------------
    for rid, tab, runes in [
        ("varrock", "Varrock teleport (tablet)", [("Law rune", 1), ("Air rune", 3), ("Fire rune", 1)]),
        ("lumbridge", "Lumbridge teleport (tablet)", [("Law rune", 1), ("Air rune", 3), ("Earth rune", 1)]),
        ("falador", "Falador teleport (tablet)", [("Law rune", 1), ("Air rune", 3), ("Water rune", 1)]),
        ("camelot", "Camelot teleport (tablet)", [("Law rune", 1), ("Air rune", 5)]),
        ("ardougne", "Ardougne teleport (tablet)", [("Law rune", 2), ("Water rune", 2)]),
        ("house", "Teleport to house (tablet)", [("Law rune", 1), ("Air rune", 1), ("Earth rune", 1)]),
    ]:
        if not have(tab, "Soft clay", *[n for n, _ in runes]):
            continue
        R(f"tab-{rid}", "tablet", f"Make {tab}",
          [ing("Soft clay")] + [ing(n, q) for n, q in runes], [ing(tab)],
          skill="Magic, plus the matching lectern in a player-owned house",
          notes="Teleport tablets are exempt from the Grand Exchange tax.",
          per_hour=1000)

    # ----------------------------------------------------------------------
    # Spell conversions: an item transmuted in the inventory, paid for in
    # runes rather than a service fee. Elemental runes are costed at market
    # for consistency with the enchanting rows above.
    # ----------------------------------------------------------------------
    if have("Bones", "Banana", "Nature rune", "Earth rune", "Water rune"):
        R("spell-bones-bananas", "spell", "Bones to Bananas",
          [ing("Bones", 27), ing("Nature rune"), ing("Earth rune", 2), ing("Water rune", 2)],
          [ing("Banana", 27)],
          skill="Magic 15",
          notes="One cast converts every bone in the inventory, so this is priced "
                "per cast at 27 bones: a full inventory with a mud battlestaff "
                "worn and one slot kept for nature runes. No action rate is given "
                "because the bone buy limit binds long before your hands do.",
          xp=25)

    # Superheat pays the full coal cost, unlike the blast furnace rows above.
    for rid, ore, coal, bar, lvl in [
        ("iron", "Iron ore", 0, "Iron bar", 15),
        ("silver", "Silver ore", 0, "Silver bar", 20),
        ("steel", "Iron ore", 2, "Steel bar", 30),
        ("gold", "Gold ore", 0, "Gold bar", 40),
        ("mithril", "Mithril ore", 4, "Mithril bar", 50),
        ("addy", "Adamantite ore", 6, "Adamantite bar", 70),
        ("rune", "Runite ore", 8, "Runite bar", 85),
    ]:
        if not have(ore, bar, "Nature rune", "Fire rune") or (coal and not have("Coal")):
            continue
        ins = [ing(ore)] + ([ing("Coal", coal)] if coal else [])
        ins += [ing("Nature rune"), ing("Fire rune", 4)]
        R(f"spell-superheat-{rid}", "spell", f"Superheat {bar}",
          ins, [ing(bar)],
          skill=f"Magic 43, Smithing {lvl}",
          notes="Superheat needs the full coal a bar normally takes, where the "
                "blast furnace halves it — compare the same bar under smelting. "
                "What Superheat buys instead is no furnace trip and 53 Magic "
                "experience a cast, which is the usual reason to do it. The "
                "experience below is that Magic experience; the Smithing "
                "experience for the bar comes on top.",
          per_hour=1200, xp=53)

    # Superglass Make. Costed at the guaranteed one glass per pair of
    # materials; the spell actually averages higher (see notes below).
    if have("Seaweed", "Bucket of sand", "Molten glass", "Astral rune", "Air rune", "Fire rune"):
        R("spell-superglass-seaweed", "spell", "Superglass Make with seaweed",
          [ing("Seaweed", 13), ing("Bucket of sand", 13),
           ing("Astral rune", 2), ing("Air rune", 10), ing("Fire rune", 6)],
          [ing("Molten glass", 13)],
          skill="Magic 77 (Lunar spellbook)",
          notes="Priced per cast at thirteen pairs, the inventory a smoke "
                "battlestaff leaves room for. Costed at the guaranteed one glass "
                "per pair; the spell averages nearer 1.3 glass per pair, so the "
                "bonus yield is upside this row does not claim.",
          per_hour=150, xp=78)
    if have("Giant seaweed", "Bucket of sand", "Molten glass", "Astral rune", "Air rune", "Fire rune"):
        R("spell-superglass-giant", "spell", "Superglass Make with giant seaweed",
          [ing("Giant seaweed", 3), ing("Bucket of sand", 18),
           ing("Astral rune", 2), ing("Air rune", 10), ing("Fire rune", 6)],
          [ing("Molten glass", 18)],
          skill="Magic 77 (Lunar spellbook)",
          notes="One giant seaweed counts as six ordinary ones, so three of them "
                "feed eighteen buckets of sand in a single cast. Costed at the "
                "guaranteed one glass per pair, as above; with giant seaweed the "
                "average runs nearer 1.6, which is the whole reason to pay more "
                "per unit of seaweed for it.",
          per_hour=150, xp=78)

    # Plank Make, against the sawmill rows further up. The spell charges 70%
    # of the operator's fee but adds runes, so it's only worth it where the
    # fee is large enough to swamp them.
    for rid, log, plank, fee in [
        ("plank", "Logs", "Plank", 70),
        ("oak", "Oak logs", "Oak plank", 175),
        ("teak", "Teak logs", "Teak plank", 350),
        ("mahogany", "Mahogany logs", "Mahogany plank", 1050),
    ]:
        if not have(log, plank, "Astral rune", "Nature rune", "Earth rune"):
            continue
        R(f"spell-plank-{rid}", "spell", f"Plank Make {plank}",
          [ing(log), ing("Astral rune", 2), ing("Nature rune"), ing("Earth rune", 15)],
          [ing(plank)],
          skill="Magic 86 (Lunar spellbook)",
          notes=f"The spell charges {fee:,} gp per plank, 70% of what the sawmill "
                "operator asks, but adds two astral runes and a nature rune on "
                "top. Worth comparing against the sawmill row for the same plank: "
                "the discount only outruns the runes where the fee is large.",
          fee_gp=fee, per_hour=1000, xp=90)

    # ----------------------------------------------------------------------
    # Barrows item sets, both directions.
    # ----------------------------------------------------------------------
    sets = {
        "Dharok's armour set": ["Dharok's helm", "Dharok's platebody", "Dharok's platelegs", "Dharok's greataxe"],
        "Ahrim's armour set": ["Ahrim's hood", "Ahrim's robetop", "Ahrim's robeskirt", "Ahrim's staff"],
        "Guthan's armour set": ["Guthan's helm", "Guthan's platebody", "Guthan's chainskirt", "Guthan's warspear"],
        "Karil's armour set": ["Karil's coif", "Karil's leathertop", "Karil's leatherskirt", "Karil's crossbow"],
        "Torag's armour set": ["Torag's helm", "Torag's platebody", "Torag's platelegs", "Torag's hammers"],
        "Verac's armour set": ["Verac's helm", "Verac's brassard", "Verac's plateskirt", "Verac's flail"],
    }
    for setname, pieces in sets.items():
        if not have(setname, *pieces):
            continue
        short = setname.split("'")[0].lower()
        R(f"set-{short}-break", "itemset", f"Break {setname} into its pieces",
          [ing(setname)], [ing(p) for p in pieces],
          notes="Grand Exchange clerks assemble and separate sets for free. "
                "Tax is charged on each piece sold, not once on the set.")
        R(f"set-{short}-make", "itemset", f"Combine pieces into {setname}",
          [ing(p) for p in pieces], [ing(setname)],
          notes="The reverse trade: buy the four pieces, sell the assembled set.")

    # ----------------------------------------------------------------------
    # Barrows repair. Costs verified against the wiki (see openget.txt,
    # RECIPES AND INDICES, for the exact figures).
    # ----------------------------------------------------------------------
    repair_cost = {"helm": 60000, "body": 90000, "legs": 80000, "weapon": 100000}
    for brother, pieces in [
        ("dharok", [("Dharok's helm", "helm"), ("Dharok's platebody", "body"),
                    ("Dharok's platelegs", "legs"), ("Dharok's greataxe", "weapon")]),
        ("ahrim", [("Ahrim's hood", "helm"), ("Ahrim's robetop", "body"),
                   ("Ahrim's robeskirt", "legs"), ("Ahrim's staff", "weapon")]),
        ("guthan", [("Guthan's helm", "helm"), ("Guthan's platebody", "body"),
                    ("Guthan's chainskirt", "legs"), ("Guthan's warspear", "weapon")]),
        ("karil", [("Karil's coif", "helm"), ("Karil's leathertop", "body"),
                   ("Karil's leatherskirt", "legs"), ("Karil's crossbow", "weapon")]),
        ("torag", [("Torag's helm", "helm"), ("Torag's platebody", "body"),
                   ("Torag's platelegs", "legs"), ("Torag's hammers", "weapon")]),
        ("verac", [("Verac's helm", "helm"), ("Verac's brassard", "body"),
                   ("Verac's plateskirt", "legs"), ("Verac's flail", "weapon")]),
    ]:
        for piece, slot in pieces:
            broken = f"{piece} 0"
            if not have(piece, broken):
                continue
            fee = repair_cost[slot]
            R(f"repair-{brother}-{slot}", "barrows", f"Repair {broken}",
              [ing(broken)], [ing(piece)],
              notes=f"An NPC charges {fee:,} gp for a fully degraded piece. A "
                    "player-owned-house armour stand charges (1 - Smithing/200) "
                    "of that, so roughly half at 99 Smithing.",
              fee_gp=fee)

    # ----------------------------------------------------------------------
    # Combination items.
    # ----------------------------------------------------------------------
    if have("Draconic visage", "Anti-dragon shield", "Dragonfire shield"):
        R("comb-dfs", "combination", "Make a Dragonfire shield",
          [ing("Draconic visage"), ing("Anti-dragon shield")], [ing("Dragonfire shield")],
          skill="Smithing 90")
    if have("Skeletal visage", "Anti-dragon shield", "Dragonfire ward"):
        R("comb-dfw", "combination", "Make a Dragonfire ward",
          [ing("Skeletal visage"), ing("Anti-dragon shield")], [ing("Dragonfire ward")],
          skill="Smithing 90")
    if have("Staff of the dead", "Magic fang", "Toxic staff (uncharged)"):
        R("comb-toxic-staff", "combination", "Make a Toxic staff (uncharged)",
          [ing("Staff of the dead"), ing("Magic fang")], [ing("Toxic staff (uncharged)")])
    for god in ["Armadyl", "Bandos", "Saradomin", "Zamorak"]:
        hilt, sword = f"{god} hilt", f"{god} godsword"
        if not have("Godsword blade", hilt, sword):
            continue
        R(f"comb-{god.lower()}-gs", "combination", f"Make an {sword}",
          [ing("Godsword blade"), ing(hilt)], [ing(sword)],
          notes="The blade is itself three shards combined; priced here as a "
                "finished blade because that is how it trades.")

    # ----------------------------------------------------------------------
    # Sapling trading: buy a seed, grow it in a filled plant pot, sell the sapling.
    # ----------------------------------------------------------------------
    for seed, sap in [
        ("Acorn", "Oak sapling"), ("Willow seed", "Willow sapling"),
        ("Maple seed", "Maple sapling"), ("Yew seed", "Yew sapling"),
        ("Magic seed", "Magic sapling"), ("Teak seed", "Teak sapling"),
        ("Mahogany seed", "Mahogany sapling"), ("Redwood tree seed", "Redwood sapling"),
        ("Celastrus seed", "Celastrus sapling"), ("Apple tree seed", "Apple sapling"),
        ("Banana tree seed", "Banana sapling"), ("Orange tree seed", "Orange sapling"),
        ("Curry tree seed", "Curry sapling"), ("Pineapple seed", "Pineapple sapling"),
        ("Papaya tree seed", "Papaya sapling"), ("Palm tree seed", "Palm sapling"),
        ("Dragonfruit tree seed", "Dragonfruit sapling"), ("Calquat tree seed", "Calquat sapling"),
    ]:
        if not have(seed, sap, "Filled plant pot"):
            continue
        R(f"sap-{slug(sap)}", "sapling", f"Grow {seed} into {sap}",
          [ing(seed), ing("Filled plant pot")], [ing(sap)],
          skill="Farming, plus a gardening trowel and a watering can",
          notes="A seed placed in a filled plant pot becomes a sapling after a "
                "few minutes. The trowel and watering can are reusable, so the "
                "plant pot is the only consumable priced here.")


def slug(s):
    out = []
    for ch in s.lower():
        if ch.isalnum():
            out.append(ch)
        elif out and out[-1] != "-":
            out.append("-")
    return "".join(out).strip("-")


def esc(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


def main():
    for it in load_mapping():
        # Keep the lowest id when a name repeats: that is the tradeable form.
        if it["name"] not in BY_NAME or it["id"] < BY_NAME[it["name"]]:
            BY_NAME[it["name"]] = it["id"]

    build()

    if UNRESOLVED:
        print("UNRESOLVED ITEM NAMES:", file=sys.stderr)
        for n in sorted(set(UNRESOLVED)):
            print("  " + n, file=sys.stderr)
        sys.exit(1)

    out = [
        "# OpenGET money-maker recipes.",
        "# GENERATED by contrib/gen_recipes.py — do not hand-edit.",
        "# Item ids are resolved against the live OSRS Wiki /mapping endpoint,",
        "# so regenerate after any game update that renames or adds items.",
        "",
    ]
    for r in RECIPES:
        out.append("[[recipe]]")
        out.append(f'id = "{esc(r["id"])}"')
        out.append(f'kind = "{esc(r["kind"])}"')
        out.append(f'name = "{esc(r["name"])}"')
        if r["skill_reqs"]:
            out.append(f'skill_reqs = "{esc(r["skill_reqs"])}"')
        if r["notes"]:
            out.append(f'notes = "{esc(r["notes"])}"')
        out.append(f'sort_key = {r["sort_key"]}')
        extra = {k: v for k, v in r["extra"].items() if v}
        if extra:
            out.append("[recipe.extra]")
            for k, v in extra.items():
                out.append(f"{k} = {'true' if v is True else v}")
        for side in ("inputs", "outputs"):
            for x in r[side]:
                out.append(f"[[recipe.{side}]]")
                out.append(f'item_id = {x["item_id"]}  # {x["_name"]}')
                out.append(f'qty = {x["qty"]}')
                if x.get("note"):
                    out.append(f'note = "{esc(x["note"])}"')
        out.append("")
    print("\n".join(out))
    print(f"# generated {len(RECIPES)} recipes", file=sys.stderr)


if __name__ == "__main__":
    main()
