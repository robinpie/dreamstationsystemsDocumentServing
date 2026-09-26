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
	"fmt"
	"strings"
)

// GemtextOptions tunes gemtext rendering.
type GemtextOptions struct {
	// Prefix is prepended to relative links, e.g. "/ge".
	Prefix string
	// Width for preformatted tables. Gemini clients reflow prose themselves, so only preformatted blocks need a width.
	Width int
	// WebBase, when set, adds a link back to the HTTP version.
	WebBase string
}

// Gemtext renders a Doc as text/gemini.
//
// Gemtext has no tables and no inline images, so tables become preformatted blocks with an alt-text label (which conforming clients announce), and charts become Unicode sparklines with an optional link to a real image for clients that will fetch one.
func Gemtext(d *Doc, o GemtextOptions) string {
	if o.Width <= 0 {
		o.Width = 72
	}
	var b strings.Builder
	p := func(format string, args ...any) {
		fmt.Fprintf(&b, format+"\n", args...)
	}

	if d.Title != "" {
		p("# %s", d.Title)
	}
	if d.Subtitle != "" {
		p("%s", d.Subtitle)
	}
	b.WriteString("\n")

	for _, blk := range d.Blocks {
		switch v := blk.(type) {
		case Heading:
			lvl := v.Level
			if lvl < 2 {
				lvl = 2
			}
			if lvl > 3 {
				lvl = 3
			}
			p("%s %s", strings.Repeat("#", lvl), v.Text)
			b.WriteString("\n")

		case Para:
			p("%s", v.Text)
			b.WriteString("\n")

		case Pre:
			alt := v.Alt
			p("```%s", alt)
			p("%s", strings.TrimRight(v.Text, "\n"))
			p("```")
			b.WriteString("\n")

		case Facts:
			if v.Title != "" {
				p("## %s", v.Title)
			}
			for _, kv := range v.Pairs {
				if kv.Link != "" {
					p("=> %s %s: %s", withPrefix(o.Prefix, kv.Link), kv.Key, kv.Value)
					continue
				}
				p("* %s: %s", kv.Key, kv.Value)
			}
			b.WriteString("\n")

		case Table:
			// The caption becomes the block's alt text, which conforming clients announce, so it must not also be printed as the first line inside the block — that reads the table's name out twice.
			alt, body := v.Caption, v
			if alt == "" {
				alt = "table"
			}
			body.Caption = ""
			lines := textTable(body, o.Width)
			if len(lines) == 0 {
				continue
			}
			p("```%s", alt)
			for _, l := range lines {
				p("%s", l)
			}
			p("```")
			// Gemtext cannot link inside a preformatted block, so every linked cell in the first column is re-emitted as a real link line — otherwise the capsule would be a dead end where the web version is navigable.
			for _, r := range v.Rows {
				for _, c := range r {
					if c.Link != "" {
						p("=> %s %s", withPrefix(o.Prefix, c.Link), c.Text)
						break
					}
				}
			}
			b.WriteString("\n")

		case Links:
			if v.Title != "" {
				p("## %s", v.Title)
			}
			for _, it := range v.Items {
				if it.Desc != "" {
					p("=> %s %s — %s", withPrefix(o.Prefix, it.Href), it.Text, it.Desc)
				} else {
					p("=> %s %s", withPrefix(o.Prefix, it.Href), it.Text)
				}
			}
			b.WriteString("\n")

		case Chart:
			if v.Title != "" {
				p("## %s", v.Title)
			}
			p("```%s", "price chart as a text sparkline")
			for _, s := range v.Series {
				if len(s.Points) == 0 {
					continue
				}
				p("%-6s %s", s.Name, Sparkline(s.Points, 56))
			}
			if lo, hi, ok := chartRange(v); ok {
				p("%-6s low %s   high %s", "", GPShort(int64(lo)), GPShort(int64(hi)))
			}
			p("```")
			if v.AltLink != "" {
				p("=> %s %s (SVG)", withPrefix(o.Prefix, v.AltLink), v.Title)
			}
			b.WriteString("\n")

		case Form:
			if v.WebOnly {
				continue
			}
			// Gemini's input mechanism is a status-10 response on the target URL, so a form is simply a link the client will prompt for.
			if v.Prompt != "" {
				p("=> %s %s", withPrefix(o.Prefix, v.Action), v.Prompt)
			}
			b.WriteString("\n")

		case Raw:
			// HTML-only.
		}
	}

	if len(d.Footnotes) > 0 {
		p("## Notes")
		for _, f := range d.Footnotes {
			p("* %s", f)
		}
		b.WriteString("\n")
	}
	if o.WebBase != "" && d.Path != "" && !d.NoIndex {
		p("=> %s%s This page on the web", o.WebBase, d.Path)
	}
	return b.String()
}

// withPrefix prepends the retro tree prefix to a relative link and leaves an absolute one alone.
//
// Concatenating unconditionally is a silent failure: it produces targets like "/gehttps://runelite.net/" that nothing errors on and no link check catches, so every external link on a capsule page simply goes nowhere.
func withPrefix(prefix, href string) string {
	if isAbsoluteURL(href) {
		return href
	}
	return prefix + href
}

// gopherRowType picks the item type for a link sitting in a table row.
//
// Type '0' promises a text file and type '1' a menu, and clients honour that promise: a '0' pointing at one of our pages makes a client render a gophermap as plain text, tabs and all. Item lookup and search are CGI scripts that really do return text; every other target in the tree is written as a directory holding a gophermap (see retro.writeGopher), so it is a menu.
func gopherRowType(href string) byte {
	if strings.HasPrefix(href, "/item/") || strings.HasPrefix(href, "/search") {
		return '0'
	}
	return '1'
}

// isAbsoluteURL reports whether href already carries a scheme.
//
// Testing for "://" is not enough: mailto: and news: have no authority component.
func isAbsoluteURL(href string) bool {
	if strings.HasPrefix(href, "//") { // protocol-relative
		return true
	}
	i := strings.IndexByte(href, ':')
	if i <= 0 {
		return false
	}
	for j := 0; j < i; j++ {
		c := href[j]
		alnum := c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9'
		if !alnum && c != '+' && c != '-' && c != '.' {
			return false
		}
	}
	// RFC 3986: a scheme must begin with a letter, which also stops a bare "4151:something" from being mistaken for one.
	c := href[0]
	return c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z'
}

// ---------------------------------------------------------------------------
// Gophermap
// ---------------------------------------------------------------------------

// GopherOptions tunes gophermap rendering.
type GopherOptions struct {
	Host   string
	Port   int
	Prefix string // selector prefix, e.g. "/ge"
	Width  int
	// SearchSelector, when set, adds a type-7 search entry.
	SearchSelector string
}

// Gophermap renders a Doc as a gophermap (RFC 1436 menu).
//
// Information lines are type 'i' with a dummy selector and host; links become type '0' (text) or '1' (menu) entries. Fields are tab-separated and the map terminates with a "." line.
func Gophermap(d *Doc, o GopherOptions) string {
	if o.Width <= 0 {
		o.Width = 70
	}
	if o.Port == 0 {
		o.Port = 70
	}
	var b strings.Builder

	info := func(s string) {
		// A literal tab inside an info line would be read as a field separator and split the entry, so expand tabs first.
		s = strings.ReplaceAll(s, "\t", "    ")
		fmt.Fprintf(&b, "i%s\tfake\t(NULL)\t0\r\n", s)
	}
	link := func(typ byte, text, selector string) {
		text = strings.ReplaceAll(text, "\t", " ")
		fmt.Fprintf(&b, "%c%s\t%s\t%s\t%d\r\n", typ, text, selector, o.Host, o.Port)
	}

	if d.Title != "" {
		info(d.Title)
		info(strings.Repeat("=", min(len(d.Title), o.Width)))
	}
	if d.Subtitle != "" {
		info(d.Subtitle)
	}
	info("")

	for _, blk := range d.Blocks {
		switch v := blk.(type) {
		case Heading:
			info(strings.ToUpper(v.Text))
			info(strings.Repeat("-", min(len(v.Text), o.Width)))
		case Para:
			for _, l := range wrap(v.Text, o.Width) {
				info(l)
			}
			info("")
		case Pre:
			for _, l := range strings.Split(strings.TrimRight(v.Text, "\n"), "\n") {
				info(l)
			}
			info("")
		case Facts:
			if v.Title != "" {
				info(v.Title)
			}
			keyW := 0
			for _, kv := range v.Pairs {
				keyW = max(keyW, len(kv.Key))
			}
			for _, kv := range v.Pairs {
				info("  " + pad(kv.Key+":", keyW+1, AlignLeft) + " " + kv.Value)
			}
			info("")
		case Table:
			cols, rows := retroColumns(v)
			lines := textTable(Table{Columns: cols, Rows: rows, Caption: v.Caption, Empty: v.Empty}, o.Width)
			// The header and rule are informational; each data row becomes a selectable entry when it carries a link, so a gopher client can actually drill into an item rather than just read about it.
			hdr := 0
			if v.Caption != "" {
				hdr++
			}
			for i, l := range lines {
				if i < hdr+2 || len(rows) == 0 {
					info(l)
					continue
				}
				ri := i - hdr - 2
				sel := ""
				if ri < len(rows) {
					for _, c := range rows[ri] {
						if c.Link != "" {
							sel = c.Link
							break
						}
					}
				}
				switch {
				case sel == "":
					info(l)
				case isAbsoluteURL(sel):
					link('h', l, "URL:"+sel)
				default:
					link(gopherRowType(sel), l, withPrefix(o.Prefix, sel))
				}
			}
			info("")
		case Links:
			if v.Title != "" {
				info(v.Title)
			}
			for _, it := range v.Items {
				txt := it.Text
				if it.Desc != "" {
					txt += " — " + it.Desc
				}
				// A target outside gopherspace is item type 'h' with a "URL:" selector — the convention every client and gophernicus itself understand. As a type '1' menu it would point at a selector on our own host that does not exist.
				if isAbsoluteURL(it.Href) {
					link('h', txt, "URL:"+it.Href)
					continue
				}
				link('1', txt, o.Prefix+it.Href)
			}
			info("")
		case Chart:
			if v.Title != "" {
				info(v.Title)
			}
			for _, s := range v.Series {
				if len(s.Points) == 0 {
					continue
				}
				info(fmt.Sprintf("  %-6s %s", s.Name, Sparkline(s.Points, 48)))
			}
			if lo, hi, ok := chartRange(v); ok {
				info(fmt.Sprintf("         low %s  high %s", GPShort(int64(lo)), GPShort(int64(hi))))
			}
			info("")
		case Form:
			if o.SearchSelector != "" && !v.WebOnly {
				link('7', v.Prompt, o.SearchSelector)
				info("")
			}
		case Raw:
		}
	}

	if len(d.Footnotes) > 0 {
		info(strings.Repeat("-", min(40, o.Width)))
		for _, f := range d.Footnotes {
			for i, l := range wrap(f, o.Width-2) {
				if i == 0 {
					info("* " + l)
				} else {
					info("  " + l)
				}
			}
		}
	}
	b.WriteString(".\r\n")
	return b.String()
}
