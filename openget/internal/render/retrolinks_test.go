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

package render

import (
	"strings"
	"testing"
)

// TestRetroLinksGeminiPageExt pins the capsule link shapes, since the generator
// writes "<slug>.gmi" while the view models link to extensionless web paths.
func TestRetroLinksGeminiPageExt(t *testing.T) {
	for _, tc := range []struct{ name, in, want string }{
		{"list page", "=> /ge/flips/margin Highest margins", "=> /ge/margin.gmi Highest margins"},
		{"plain page", "=> /ge/about About and credits", "=> /ge/about.gmi About and credits"},
		{"calculator", "=> /ge/calc/herblore Herblore", "=> /ge/calc-herblore.gmi Herblore"},
		{"query string", "=> /ge/store-profit?spell=low Low alch", "=> /ge/alch.gmi?spell=low Low alch"},
		{"fragment", "=> /ge/indices/gold Gold index", "=> /ge/indices.gmi#gold Gold index"},
		{"no label", "=> /ge/alch-low", "=> /ge/alch-low.gmi"},
		{"tree root untouched", "=> /ge/ Home", "=> /ge/ Home"},
		{"item goes to cgi, not a file", "=> /ge/item/4151 Abyssal whip", "=> /ge/cgi-bin/ge/item/4151 Abyssal whip"},
		{"search goes to cgi, not a file", "=> /ge/search Search", "=> /ge/cgi-bin/ge/search Search"},
		{"external link untouched", "=> https://runelite.net/ RuneLite", "=> https://runelite.net/ RuneLite"},
		{"mailto untouched", "=> mailto:robin@dreamstation.systems Email", "=> mailto:robin@dreamstation.systems Email"},
		{"non-link line untouched", "/ge/about is not a link line", "/ge/about is not a link line"},
		{"already suffixed", "=> /ge/about.gmi About", "=> /ge/about.gmi About"},
		{"svg chart keeps its own extension", "=> /ge/chart/4151.svg?w=1w Chart (SVG)", "=> /ge/chart/4151.svg?w=1w Chart (SVG)"},
		{"dotted slug still gets one", "=> /ge/alch-low Low alch", "=> /ge/alch-low.gmi Low alch"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := RetroLinks(tc.in, "/ge", "gemini"); got != tc.want {
				t.Errorf("RetroLinks(%q)\n got %q\nwant %q", tc.in, got, tc.want)
			}
		})
	}
}

// TestRetroLinksGopherNoExt guards the other half: gophermaps address pages as
// directories, so a ".gmi" leaking into a selector would break every link.
func TestRetroLinksGopherNoExt(t *testing.T) {
	in := "1Highest margins\t/ge/flips/margin\tdreamstation.systems\t70"
	want := "1Highest margins\t/ge/margin\tdreamstation.systems\t70"
	if got := RetroLinks(in, "/ge", "gopher"); got != want {
		t.Errorf("RetroLinks(gopher)\n got %q\nwant %q", got, want)
	}
}

// TestRetroLinksGopherFragment pins the fragment strip. Gopher has no notion of
// a fragment, so gophernicus looked for a file literally called "indices#bars".
func TestRetroLinksGopherFragment(t *testing.T) {
	in := "0Gold\t/ge/indices/gold\tdreamstation.systems\t70"
	want := "0Gold\t/ge/indices\tdreamstation.systems\t70"
	if got := RetroLinks(in, "/ge", "gopher"); got != want {
		t.Errorf("RetroLinks(gopher)\n got %q\nwant %q", got, want)
	}
	// Gemini keeps them: the fragment is what makes the link land on the section.
	gem := "=> /ge/indices/gold Gold index"
	if got, want := RetroLinks(gem, "/ge", "gemini"), "=> /ge/indices.gmi#gold Gold index"; got != want {
		t.Errorf("RetroLinks(gemini)\n got %q\nwant %q", got, want)
	}
}

// TestGophermapRowTypes pins the item type of a linked table row. A '0' aimed at
// one of our pages makes clients print a gophermap as raw tab-separated text.
func TestGophermapRowTypes(t *testing.T) {
	d := &Doc{Title: "Barrows repair"}
	d.Add(Table{
		Caption: "Methods",
		Columns: []Column{{Title: "Method"}, {Title: "Profit"}},
		Rows: [][]Cell{
			{CL("Repair Ahrim's robetop", "/calc/barrows/repair-ahrim-body"), C("-91,029")},
			{CL("Abyssal whip", "/item/4151"), C("3,393")},
		},
	})
	out := RetroLinks(Gophermap(d, GopherOptions{Host: "h", Port: 70, Prefix: "/ge", Width: 70}), "/ge", "gopher")

	var recipe, item string
	for _, ln := range strings.Split(out, "\n") {
		f := strings.Split(ln, "\t")
		if len(f) < 2 {
			continue
		}
		switch f[1] {
		case "/ge/calc-barrows/repair-ahrim-body":
			recipe = ln[:1]
		case "/ge/cgi-bin/item?4151":
			item = ln[:1]
		}
	}
	// A recipe page is written as a directory holding a gophermap: a menu.
	if recipe != "1" {
		t.Errorf("recipe row type = %q, want \"1\" (menu); output:\n%s", recipe, out)
	}
	// Item lookup is a CGI script that really does return text.
	if item != "0" {
		t.Errorf("item row type = %q, want \"0\" (text); output:\n%s", item, out)
	}
}
