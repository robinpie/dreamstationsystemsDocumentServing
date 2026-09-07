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
	"html"
	"net/url"
	"strings"
	"time"
)

// HTMLOptions tunes HTML rendering.
type HTMLOptions struct {
	// SortBase is the path sortable column headers link to.
	SortBase string
	// CurrentSort and Desc mark the active sort for header arrows.
	CurrentSort string
	Desc        bool
}

// HTMLBody renders a Doc's blocks as HTML. The surrounding page chrome (head, nav, footer) lives in the web package's layout template; this produces only the main content, so the two concerns stay separable.
func HTMLBody(d *Doc, o HTMLOptions) string {
	var b strings.Builder
	// Column and fact hints are collected here and emitted once, hidden, at the end of the body, with each header or term pointing at its own by aria-describedby. The title attribute stays too, for the mouse tooltip; aria-describedby wins where both are present, so nothing is read twice.
	var hints hintSet

	for _, blk := range d.Blocks {
		switch v := blk.(type) {
		case Heading:
			lvl := clamp(v.Level, 2, 4)
			id := ""
			if v.Anchor != "" {
				id = fmt.Sprintf(` id="%s"`, escapeAttr(v.Anchor))
			}
			fmt.Fprintf(&b, "<h%d%s>%s</h%d>\n", lvl, id, escapeText(v.Text), lvl)

		case Para:
			cls := ""
			if v.Muted {
				cls = ` class="muted"`
			}
			fmt.Fprintf(&b, "<p%s>%s</p>\n", cls, escapeText(v.Text))

		case Pre:
			fmt.Fprintf(&b, "<pre>%s</pre>\n", escapeText(v.Text))

		case Facts:
			b.WriteString(`<div class="facts window">`)
			if v.Title != "" {
				lvl := headingLevel(v.Level)
				fmt.Fprintf(&b, `<h%d class="title-bar"><span class="title-bar-text">%s</span></h%d>`, lvl, escapeText(v.Title), lvl)
			}
			b.WriteString(`<dl class="window-body">`)
			for _, kv := range v.Pairs {
				title, desc := "", ""
				if kv.Hint != "" {
					title = fmt.Sprintf(` title="%s"`, escapeAttr(kv.Hint))
					desc = hints.ref(kv.Hint)
				}
				fmt.Fprintf(&b, "<dt%s%s>%s</dt>", title, desc, escapeText(kv.Key))
				val := timeWrap(escapeText(kv.Value), kv.At)
				if kv.Link != "" {
					val = fmt.Sprintf(`<a href="%s">%s</a>`, escapeAttr(kv.Link), val)
				}
				fmt.Fprintf(&b, `<dd%s>%s</dd>`, classAttr(toneClass(kv.Tone)), val)
			}
			b.WriteString("</dl></div>\n")

		case Table:
			htmlTable(&b, v, o, &hints)

		case Links:
			if v.NavLabel != "" {
				fmt.Fprintf(&b, `<nav aria-label="%s">`, escapeAttr(v.NavLabel))
			}
			if v.Title != "" {
				// .linkhead, not a bare heading: this is a label on a list, and at h2 it would otherwise take the section rule both skins draw under a bare h2 and the 24px that goes with it.
				lvl := headingLevel(v.Level)
				fmt.Fprintf(&b, `<h%d class="linkhead">%s</h%d>`+"\n", lvl, escapeText(v.Title), lvl)
			}
			b.WriteString(`<ul class="linklist">`)
			for _, it := range v.Items {
				cur := ""
				if it.Current {
					cur = ` aria-current="page"`
				}
				if it.Rel != "" {
					cur += fmt.Sprintf(` rel="%s"`, escapeAttr(it.Rel))
				}
				fmt.Fprintf(&b, `<li><a href="%s"%s>%s</a>`, escapeAttr(it.Href), cur, escapeText(it.Text))
				if it.Desc != "" {
					fmt.Fprintf(&b, ` <span class="muted">%s</span>`, escapeText(it.Desc))
				}
				b.WriteString("</li>")
			}
			b.WriteString("</ul>\n")
			if v.NavLabel != "" {
				b.WriteString("</nav>\n")
			}

		case Chart:
			b.WriteString(`<figure class="chartbox window">`)
			if v.Title != "" {
				fmt.Fprintf(&b, `<figcaption class="title-bar"><span class="title-bar-text">%s</span></figcaption>`, escapeText(v.Title))
			}
			// The .window-body is not decoration. 7.css's .window paints its frame with a ::before pseudo-element stretched over the whole box at z-index -1, on the assumption that an opaque body is stacked on top of it; a .window with no body shows that frame through its own contents as a sheet of glass.
			b.WriteString(`<div class="window-body">`)
			b.WriteString(SVG(v, 720, v.Height))
			b.WriteString("</div></figure>\n")

		case Form:
			method := v.Method
			if method == "" {
				method = "get"
			}
			// Deliberately NOT .window: the form is a flex container whose children are the fields themselves, with nowhere to put a .window-body.
			// The prompt also gives the form its accessible name, so it counts as a landmark. A fieldset/legend would name it too, but would draw a box every skin would then have to undraw.
			label := ""
			if v.Prompt != "" {
				label = fmt.Sprintf(` aria-label="%s"`, escapeAttr(v.Prompt))
			}
			fmt.Fprintf(&b, `<form class="ogform" method="%s" action="%s"%s>`,
				escapeAttr(method), escapeAttr(v.Action), label)
			if v.Prompt != "" {
				fmt.Fprintf(&b, `<p class="muted">%s</p>`, escapeText(v.Prompt))
			}
			for _, f := range v.Fields {
				htmlField(&b, f)
			}
			submit := v.Submit
			if submit == "" {
				submit = "Calculate"
			}
			fmt.Fprintf(&b, `<button type="submit">%s</button></form>`+"\n", escapeText(submit))

		case Raw:
			b.WriteString(v.HTML)
		}
	}

	if len(d.Footnotes) > 0 {
		b.WriteString(`<div class="notes window">` +
			`<h2 class="title-bar"><span class="title-bar-text">Notes</span></h2>` +
			`<ul class="window-body">`)
		for _, f := range d.Footnotes {
			fmt.Fprintf(&b, "<li>%s</li>", escapeText(f))
		}
		b.WriteString("</ul></div>\n")
	}
	hints.render(&b)
	return b.String()
}

// hintSet accumulates the hidden description elements for one page body. Hints are gathered rather than written in place because a span inside a <th> would join that header's accessible name, read out against every cell beneath it.
type hintSet []string

// ref records a hint and returns the attribute that points at it.
func (h *hintSet) ref(text string) string {
	if text == "" {
		return ""
	}
	*h = append(*h, text)
	return fmt.Sprintf(` aria-describedby="hint-%d"`, len(*h))
}

// render writes the collected hints into one visually-hidden block at the end of the body. .vh clips rather than display:none, since a describedby target needs to stay reachable to assistive tech.
func (h hintSet) render(b *strings.Builder) {
	if len(h) == 0 {
		return
	}
	b.WriteString(`<div class="vh">`)
	for i, t := range h {
		fmt.Fprintf(b, `<span id="hint-%d">%s</span>`, i+1, escapeText(t))
	}
	b.WriteString("</div>\n")
}

// headingLevel resolves a titled block's heading depth. Zero means 2: a panel with a title is a section of the page, and the page title is the h1 above it.
func headingLevel(l int) int {
	if l == 0 {
		return 2
	}
	return clamp(l, 2, 4)
}

// classAttr drops the attribute entirely when there is no class, rather than shipping class="" on every untoned value.
func classAttr(c string) string {
	if c == "" {
		return ""
	}
	return fmt.Sprintf(` class="%s"`, c)
}

// timeWrap pairs a rendered instant with the machine-readable one. escaped is already escaped; at is the instant it describes.
func timeWrap(escaped string, at time.Time) string {
	if at.IsZero() {
		return escaped
	}
	return fmt.Sprintf(`<time datetime="%s">%s</time>`, at.UTC().Format(time.RFC3339), escaped)
}

func htmlTable(b *strings.Builder, t Table, o HTMLOptions, hints *hintSet) {
	id := ""
	if t.ID != "" {
		id = fmt.Sprintf(` id="%s"`, escapeAttr(t.ID))
	}
	fmt.Fprintf(b, `<div class="tablewrap"%s>`, id)
	if len(t.Rows) == 0 {
		msg := t.Empty
		if msg == "" {
			msg = "Nothing to show."
		}
		fmt.Fprintf(b, `<p class="muted">%s</p></div>`+"\n", escapeText(msg))
		return
	}
	b.WriteString(`<table>`)
	// A <caption> rather than a paragraph after the table: it is the table's accessible name, which matters on pages carrying two of them, and it puts the text above the grid where the text and gemtext renderers have always printed it.
	if t.Caption != "" {
		fmt.Fprintf(b, `<caption>%s</caption>`, escapeText(t.Caption))
	}
	b.WriteString(`<thead><tr>`)
	for _, c := range t.Columns {
		cls := "l"
		if c.Align == AlignRight {
			cls = "r"
		}
		// hintRef, not desc: the sort branch below already owns that name for the sort DIRECTION, and a string quietly shadowed by a bool is exactly the kind of thing that ships.
		title, hintRef := "", ""
		if c.Hint != "" {
			title = fmt.Sprintf(` title="%s"`, escapeAttr(c.Hint))
			hintRef = hints.ref(c.Hint)
		}
		if c.SortKey != "" && o.SortBase != "" {
			// Clicking the active column flips direction; clicking a new one starts descending, which is what you want for every money column and harmless for the rest.
			desc := true
			arrow, sorted := "", ""
			if o.CurrentSort == c.SortKey {
				desc = !o.Desc
				// aria-sort carries the state programmatically; the glyph is decoration once it does, and left exposed it reads as "black down-pointing small triangle" after the column name.
				if o.Desc {
					arrow, sorted = ` <span aria-hidden="true">▾</span>`, ` aria-sort="descending"`
				} else {
					arrow, sorted = ` <span aria-hidden="true">▴</span>`, ` aria-sort="ascending"`
				}
			}
			href := addParams(o.SortBase, map[string]string{
				"sort": c.SortKey,
				"dir":  map[bool]string{true: "desc", false: "asc"}[desc],
			})
			fmt.Fprintf(b, `<th scope="col" class="%s"%s%s%s><a href="%s">%s%s</a></th>`,
				cls, title, hintRef, sorted, escapeAttr(href), escapeText(c.Title), arrow)
			continue
		}
		fmt.Fprintf(b, `<th scope="col" class="%s"%s%s>%s</th>`, cls, title, hintRef, escapeText(c.Title))
	}
	b.WriteString(`</tr></thead><tbody>`)
	for _, r := range t.Rows {
		b.WriteString("<tr>")
		for i, c := range r {
			cls, tag, scope := "l", "td", ""
			if i < len(t.Columns) {
				if t.Columns[i].Align == AlignRight {
					cls = "r"
				}
				// The cell that names its row is a header for it, not data in it.
				if t.Columns[i].RowHeader {
					tag, scope = "th", ` scope="row"`
				}
			}
			if tc := toneClass(c.Tone); tc != "" {
				cls += " " + tc
			}
			txt := timeWrap(escapeText(c.Text), c.At)
			if c.Link != "" {
				txt = fmt.Sprintf(`<a href="%s">%s</a>`, escapeAttr(c.Link), txt)
			}
			fmt.Fprintf(b, `<%s class="%s"%s>%s</%s>`, tag, cls, scope, txt, tag)
		}
		b.WriteString("</tr>")
	}
	b.WriteString("</tbody></table></div>\n")
}

func htmlField(b *strings.Builder, f Field) {
	id := "f_" + f.Name
	// A hidden field has no visible label and must not occupy a flex slot, or every form carrying one gains a mysterious empty column.
	if f.Kind == "hidden" {
		fmt.Fprintf(b, `<input type="hidden" name="%s" value="%s">`,
			escapeAttr(f.Name), escapeAttr(f.Value))
		return
	}
	// A checkbox is the one field whose label reads better beside the control than above it, so it gets a modifier class rather than the column layout every other field wants.
	cls := "field"
	if f.Kind == "checkbox" {
		cls = "field check"
	}
	// A <div> holding a <label for>, rather than a <label> wrapping the lot, so the hint stays out of the control's accessible name — see openget.txt, ACCESSIBILITY. The id/for pair keeps the label clickable regardless.
	fmt.Fprintf(b, `<div class="%s">`, cls)
	fmt.Fprintf(b, `<label for="%s">%s</label>`, escapeAttr(id), escapeText(f.Label))
	desc := ""
	if f.Hint != "" {
		desc = fmt.Sprintf(` aria-describedby="%s_hint"`, escapeAttr(id))
	}
	switch f.Kind {
	case "select":
		fmt.Fprintf(b, `<select id="%s" name="%s"%s>`, escapeAttr(id), escapeAttr(f.Name), desc)
		for _, op := range f.Options {
			sel := ""
			if op.Selected {
				sel = " selected"
			}
			fmt.Fprintf(b, `<option value="%s"%s>%s</option>`,
				escapeAttr(op.Value), sel, escapeText(op.Label))
		}
		b.WriteString("</select>")
	case "checkbox":
		checked := ""
		if f.Value == "1" || f.Value == "on" {
			checked = " checked"
		}
		fmt.Fprintf(b, `<input type="checkbox" id="%s" name="%s" value="1"%s%s>`,
			escapeAttr(id), escapeAttr(f.Name), checked, desc)
	default:
		kind := f.Kind
		if kind == "" {
			kind = "text"
		}
		fmt.Fprintf(b, `<input type="%s" id="%s" name="%s" value="%s"%s>`,
			escapeAttr(kind), escapeAttr(id), escapeAttr(f.Name), escapeAttr(f.Value), desc)
	}
	if f.Hint != "" {
		fmt.Fprintf(b, `<small class="muted" id="%s_hint">%s</small>`, escapeAttr(id), escapeText(f.Hint))
	}
	b.WriteString("</div>")
}

func toneClass(t int) string {
	switch {
	case t > 0:
		return "good"
	case t < 0:
		return "bad"
	}
	return ""
}

// addParams merges query parameters into a URL that may already have some.
func addParams(base string, params map[string]string) string {
	u, err := url.Parse(base)
	if err != nil {
		return base
	}
	q := u.Query()
	for k, v := range params {
		q.Set(k, v)
	}
	u.RawQuery = q.Encode()
	return u.String()
}

func escapeText(s string) string { return html.EscapeString(s) }
func escapeAttr(s string) string { return html.EscapeString(s) }
