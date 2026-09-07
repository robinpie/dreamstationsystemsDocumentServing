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
	"math"
	"strings"
	"time"
)

// sparkRunes are the eight block-drawing characters, low to high. They are the only chart the text protocols get, so they carry real weight: a whole gemtext price page is this plus the numbers.
var sparkRunes = []rune("▁▂▃▄▅▆▇█")

// Sparkline renders points as a Unicode block sparkline of at most width characters, resampling by averaging when there are more points than columns.
func Sparkline(pts []XY, width int) string {
	if len(pts) == 0 {
		return ""
	}
	if width <= 0 {
		width = 40
	}
	vals := resample(pts, width)
	lo, hi := math.Inf(1), math.Inf(-1)
	for _, v := range vals {
		if math.IsNaN(v) {
			continue
		}
		lo = math.Min(lo, v)
		hi = math.Max(hi, v)
	}
	if math.IsInf(lo, 1) {
		return ""
	}
	var b strings.Builder
	span := hi - lo
	for _, v := range vals {
		if math.IsNaN(v) {
			// A gap is a real fact about the data — the item did not trade — so it gets its own glyph rather than being interpolated over.
			b.WriteRune(' ')
			continue
		}
		idx := 0
		if span > 0 {
			idx = int(math.Round((v - lo) / span * float64(len(sparkRunes)-1)))
		}
		b.WriteRune(sparkRunes[clamp(idx, 0, len(sparkRunes)-1)])
	}
	return b.String()
}

// resample averages points into exactly n buckets, yielding NaN for empty ones.
func resample(pts []XY, n int) []float64 {
	if n >= len(pts) {
		out := make([]float64, len(pts))
		for i, p := range pts {
			out[i] = p.Y
		}
		return out
	}
	minX, maxX := pts[0].X, pts[len(pts)-1].X
	if maxX <= minX {
		maxX = minX + 1
	}
	sum := make([]float64, n)
	cnt := make([]int, n)
	for _, p := range pts {
		i := int(float64(p.X-minX) / float64(maxX-minX) * float64(n-1))
		i = clamp(i, 0, n-1)
		sum[i] += p.Y
		cnt[i]++
	}
	out := make([]float64, n)
	for i := range out {
		if cnt[i] == 0 {
			out[i] = math.NaN()
			continue
		}
		out[i] = sum[i] / float64(cnt[i])
	}
	return out
}

// chartRange reports the min and max Y across every series.
func chartRange(c Chart) (lo, hi float64, ok bool) {
	lo, hi = math.Inf(1), math.Inf(-1)
	for _, s := range c.Series {
		for _, p := range s.Points {
			lo = math.Min(lo, p.Y)
			hi = math.Max(hi, p.Y)
		}
	}
	if math.IsInf(lo, 1) {
		return 0, 0, false
	}
	return lo, hi, true
}

// SVG renders a chart as a self-contained inline SVG.
//
// Server-rendered rather than a JS charting library: it works with scripting off, costs the client nothing, needs no third-party bundle, and — the reason that actually matters here — a chart the server can draw is a chart the Gemini frontend can link to as an image.
func SVG(c Chart, width, height int) string {
	if width <= 0 {
		width = 720
	}
	if height <= 0 {
		height = c.Height
	}
	if height <= 0 {
		height = 260
	}
	const (
		padL = 62
		padR = 12
		padT = 12
		padB = 26
	)
	plotW := float64(width - padL - padR)
	plotH := float64(height - padT - padB)

	lo, hi, ok := chartRange(c)
	var b strings.Builder
	fmt.Fprintf(&b, `<svg class="chart" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="100%%" height="%d" role="img" aria-label="%s">`,
		width, height, height, escapeAttr(chartAria(c)))

	if !ok {
		fmt.Fprintf(&b, `<text x="%d" y="%d" class="chart-empty">no price history recorded yet</text></svg>`,
			width/2, height/2)
		return b.String()
	}
	// Pad the range by 5% so a flat line does not sit on the axis and a spike does not touch the top edge.
	if hi == lo {
		hi, lo = hi+1, lo-1
	}
	span := hi - lo
	lo -= span * 0.05
	hi += span * 0.05
	span = hi - lo

	var minX, maxX int64 = math.MaxInt64, math.MinInt64
	for _, s := range c.Series {
		for _, p := range s.Points {
			if p.X < minX {
				minX = p.X
			}
			if p.X > maxX {
				maxX = p.X
			}
		}
	}
	if maxX <= minX {
		maxX = minX + 1
	}
	x := func(t int64) float64 {
		return float64(padL) + float64(t-minX)/float64(maxX-minX)*plotW
	}
	y := func(v float64) float64 {
		return float64(padT) + (1-(v-lo)/span)*plotH
	}

	// Horizontal gridlines with gp labels.
	for i := 0; i <= 4; i++ {
		v := lo + span*float64(i)/4
		yy := y(v)
		fmt.Fprintf(&b, `<line class="grid" x1="%d" y1="%.1f" x2="%d" y2="%.1f"/>`,
			padL, yy, width-padR, yy)
		fmt.Fprintf(&b, `<text class="ylab" x="%d" y="%.1f">%s</text>`,
			padL-6, yy+4, escapeText(GPShort(int64(v))))
	}
	// A few date ticks along the bottom.
	for i := 0; i <= 3; i++ {
		t := minX + (maxX-minX)*int64(i)/3
		fmt.Fprintf(&b, `<text class="xlab" x="%.1f" y="%d">%s</text>`,
			x(t), height-8, escapeText(time.Unix(t, 0).UTC().Format("2 Jan")))
	}

	for i, s := range c.Series {
		if len(s.Points) == 0 {
			continue
		}
		colour := s.Colour
		if colour == "" {
			colour = "currentColor"
		}
		// Break the path wherever the gap between samples is much larger than the typical spacing, so a period with no trades reads as a gap rather than a straight line implying a price nobody paid.
		var path strings.Builder
		gapLimit := typicalGap(s.Points) * 4
		pen := false
		for i, p := range s.Points {
			if i > 0 && gapLimit > 0 && p.X-s.Points[i-1].X > gapLimit {
				pen = false
			}
			if !pen {
				fmt.Fprintf(&path, "M%.1f %.1f", x(p.X), y(p.Y))
				pen = true
				continue
			}
			fmt.Fprintf(&path, "L%.1f %.1f", x(p.X), y(p.Y))
		}
		// The series index goes on the element as a class so a stylesheet can recolour the line; Series.Colour stays as the stroke attribute for contexts with no stylesheet (the standalone /chart endpoint, an SVG saved to disk). See openget.txt, CHART COLOURS.
		fmt.Fprintf(&b, `<path class="series s%d" d="%s" fill="none" stroke="%s" stroke-width="1.6" stroke-linejoin="round"%s/>`,
			i, path.String(), escapeAttr(colour), dashAttr(s))
	}

	lx := padL + 4
	for i, s := range c.Series {
		if len(s.Points) == 0 {
			continue
		}
		colour := s.Colour
		if colour == "" {
			colour = "currentColor"
		}
		// The key is a sample of the line itself rather than a colour chip: matching a solid square to a dashed line is the colour-only judgement the dash exists to avoid.
		fmt.Fprintf(&b, `<line class="series s%d" x1="%d" y1="%d" x2="%d" y2="%d" stroke="%s" stroke-width="2.4"%s/>`,
			i, lx, padT+5, lx+16, padT+5, escapeAttr(colour), dashAttr(s))
		fmt.Fprintf(&b, `<text class="legend" x="%d" y="%d">%s</text>`, lx+21, padT+9, escapeText(s.Name))
		lx += 28 + 7*len(s.Name)
	}
	b.WriteString(`</svg>`)
	return b.String()
}

// typicalGap returns the median spacing between samples.
func typicalGap(pts []XY) int64 {
	if len(pts) < 3 {
		return 0
	}
	gaps := make([]int64, 0, len(pts)-1)
	for i := 1; i < len(pts); i++ {
		gaps = append(gaps, pts[i].X-pts[i-1].X)
	}
	// Partial selection is plenty for a median on data this small.
	for i := 0; i < len(gaps); i++ {
		for j := i + 1; j < len(gaps); j++ {
			if gaps[j] < gaps[i] {
				gaps[i], gaps[j] = gaps[j], gaps[i]
			}
		}
	}
	return gaps[len(gaps)/2]
}

// dashAttr renders a series' stroke-dasharray, empty for a solid line.
func dashAttr(s Series) string {
	if s.Dash == "" {
		return ""
	}
	return fmt.Sprintf(` stroke-dasharray="%s"`, escapeAttr(s.Dash))
}

func chartAria(c Chart) string {
	names := make([]string, 0, len(c.Series))
	for _, s := range c.Series {
		names = append(names, s.Name)
	}
	lo, hi, ok := chartRange(c)
	if !ok {
		return c.Title + ": no data"
	}
	return fmt.Sprintf("%s: %s, ranging from %s to %s gp",
		c.Title, strings.Join(names, " and "), GP(int64(lo)), GP(int64(hi)))
}

func clamp(v, lo, hi int) int {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}
