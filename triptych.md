# triptych — one source, three panels

`triptych.pl` renders one source file per page to all three protocols:

```
content/index.tri  ->  rootdomain/personal/index.html   (HTML, SSI, themes, JSON-LD)
                       gemini/index.gmi                 (gemtext; Spartan reads it too)
                       gopher/gophermap                 (gophermap)
```

It owns the main site as `rootdomain/personal/CLAUDE.md` defines it — index,
blog index, the six posts, ntpuserinfo — plus the two-target `services` page.
**29 files, from 10 sources.**

```
./triptych.pl                     render everything
./triptych.pl --check             render and diff against the committed tree
./triptych.pl gzipt index         restrict to those pages
./triptych.pl --list              what is written, from what
./triptych.pl --source-of <file>  the .tri a given output came from
```

`--check` is the load-bearing one: it is how you know a change to the renderer
did not quietly move 29 files. It exits non-zero on any difference.

---

## 1. Where things live

```
content/*.tri            THE SOURCE. Hand-edited.
content/post/*.tri       one per blog post; dropping one in adds it everywhere
templates/<target>/*.tpl page chrome: <head>, SSI, nav, footers, gophermap headers
triptych.conf            per-protocol conventions + the site-wide link table
triptych.pl              the renderer
```

Outputs stay committed, because `promoteSite.sh` is a plain rsync with no
build step on the server — anything served has to exist in a commit.

**Do not hand-edit the 29 outputs.** The next commit regenerates them. Edit
the `.tri`. (`--source-of` will tell you whether a file is generated.)

## 2. The format

Front matter, then blocks. `//` starts a comment that reaches no output.

```
---
id: lanfalsehoods
kind: post                 post | page | index | bloglist
title: Falsehoods Programmers Believe About LANs
date: 2026-09-05
updated: 2026-09-05
description: A list of things that are not reliably true about the local network.
pangram: https://www.pangram.com/history/…
html.style: |              per-page CSS, HTML only
  .lanfalsehoods-title { … }
---
```

A `target.key` is scoped to that target: `html.style` never reaches gemtext,
`gopher.title` overrides the title on gopher alone. Templates ask for these by
their bare name, so `templates/html/post.tpl` sees `{{style}}`.

### Blocks

| source | html | gemini | gopher |
|---|---|---|---|
| `# …` to `#### …` | `<h1>`–`<h4>` | `#`–`####` | underline `=`, `-`, `~`, `.` |
| `- item` / `1. item` | `<ul>`/`<ol>` | `*` / `1.` | `-` / `1.` |
| paragraph | `<p>` | as written | as written |
| ` ```lang ` | `<pre><code class="language-…">` | fenced, indented 4 | indented 4 |
| ` ``` ` (no lang) | `<pre>` | fenced, indented 4 | indented 4 |
| `> quote` | `<blockquote><p>` | `> ` | wrapped and indented |
| `>>> … >>>` | `<blockquote>` of `<br>` stanzas | fenced verbatim | verbatim |
| `\| a \| b \|` rows | `<table>` | aligned, fenced | aligned |
| `[^1]: text` | `<hr>` + `<aside role="doc-footnote">` | `[1] text` | `[1] text` |
| `----` | `<hr>` | `---` | 80 hyphens |
| `@postlist` | the post list, in each protocol's idiom | | |

Source lines are never rewrapped — one source line is one output line. The
exceptions are the two that must reflow: a gopher blockquote, and a table
column with `wrap=`.

### Inline

`*em*` → `<em>`, `**strong**` → `<strong>`, `_i_` → `<i>`, `~cite~` →
`<cite>`, `` `code` `` → `<code>`, `` `code`:lang `` → a language-tagged span,
`[^1]` → a footnote marker. On gemini and gopher, `*em*` and `~cite~` keep
their asterisks and everything else is plain words — which is what the retro
copies already did by hand.

No smart typography: the source carries the exact U+2019, U+2010, U+00A0 and
U+2014 that ship (see `unicodePedanticism.txt`). The renderer substitutes
exactly two things, both of them house rules that *differ by medium*:

- a parenthetical em dash becomes thin space + em dash + thin space on the web
  (`dash = thin` in `triptych.conf`), and stays plain-spaced in text/plain;
- `gemini.nbsp: strip` / `gopher.nbsp: strip` on a page turns U+00A0 back into
  a plain space for the text copies.

### Links

Write the link once; each protocol renders it the way that protocol does.

```
Do you have [the ability to accept inbound connections](@ntppost)?
```

- **html** — an inline `<a>`.
- **gemini** — the words stay in the prose and a `=> url  label` line follows
  the block, column-aligned across the group.
- **gopher** — `label: <url>` after the block (`mode=trail`, the default),
  or `<url>` alone (`bare`), or the URL inline right after the words
  (`after`). All three shapes exist on the site; the link row picks one.

`@id` resolves against the link table in `triptych.conf` or the page's own
`@links` block:

```
@links
ath  html=https://github.com/robinpie/ath \
     gemini=ftp://dreamstation.systems/robinsSoftware/ath \
     gopher=ftp://dreamstation.systems/robinsSoftware/ath
demo html=demo.html gopher=- \
     gemini=gzipt_css_demo.png \
     gemini.label="screenshot: a page styled entirely by gzipt-generated CSS"
@end
```

`gopher=-` means **no link on that target**: the anchor text stays as prose.
`label=` overrides the text of the `=>` / trailing line; `gopher.sel=` gives
the bare selector a gophermap row needs, as against the `/0/…` URL prose uses.

A block of standalone links is written with `=>` lines. Entries may be scoped
or given verbatim:

```
@ html.class=projects html.pair=1 gemini.col=58
=> [!~ATH | my Homestuck‐inspired esoteric programming language](@ath)
=> only=gemini,gopher [Oboe, a general‐purpose language …](@oboe)
=> only=gemini [Jade K.](@sushii)
=> raw=html   <li>…verbatim…</li>
```

## 3. Putting a piece in one place only

Five mechanisms, smallest first.

1. **Inline conditional** — `{html:…}` / `{!gopher:…}`. Everything after the
   colon is content, leading space included.
   ```
   it produced [this beauty](@demo){gopher: (screenshot served alongside this post: …)}
   ```
2. **Inline verbatim** — `[[html:<span class="sep">|</span>]]`, for markup one
   medium has no equivalent for.
3. **Block attributes** — an `@` line before a block:
   `@ only=html`, `@ skip=gemini`, `@ html.em`, `@ html.class=posts`,
   `@ gemini.level=3`, `@ gemini.col=32`, `@ gopher.indent=2`,
   `@ gopher.wrap=72`, `@ tight=1`, `@ gopher.blank=3`, `@ join=1`, `@ pair=1`.
4. **Region fences** — `::: only gemini gopher` … `:::` around many blocks.
5. **Raw passthrough** — `::: raw html` (or `::: raw html head`) emits its
   lines byte-for-byte into that one target. This is why the tree round-trips:
   anything not worth modelling is carried literally.

Plus target-scoped front matter (`html.style`, `gopher.gophermap_extra`, …).

## 4. Per-protocol conventions

`triptych.conf` holds what would otherwise be retyped on every page: output
directories, default link modes, the gemini gap, gopher's host and port, tab
expansion, `code_angle = strip` (`` `<div>` `` is a tag on the web and the word
"div" in text/plain), and the site-wide link table.

Page chrome is entirely in `templates/`, verbatim — every explanatory comment
and SSI conditional in the current pages lives there untouched. Two regions of
the HTML are owned by *other* generators and are carried through from the file
on disk rather than regenerated: the `badges:start/end` wall
(`badgeBuild.pl`) and blog.html's `blogld:start/end` JSON-LD (`makeMeta.py`).

## 5. Pipeline

`preCommit.sh` runs triptych **first**:

```
./triptych.pl                  render content/ -> the three trees
./datestampHook.pl             dateModified  (writes back to the .tri)
./ntpStatHook.pl               NTP figures on /professional
assetsBuild/makeFeed.py        Atom + RSS
assetsBuild/makeMeta.py        sitemap + blog JSON-LD (and its checks)
assetsBuild/makeFontSubset.py  DejaVu subsets
assetsBuild/badgeBuild.pl      the 88x31 wall
```

Order is load-bearing and benign: triptych renders, the later steps fill the
regions they own, and everything is staged. It has the feeds' unstaged guard —
a half-finished `.tri` means no re-render and a warning, not a page in the
commit that no committed source describes.

`datestampHook.pl` asks `--source-of` before stamping. For a generated page it
rewrites `updated:` in the front matter and re-renders, instead of writing a
date the next render would discard. A page with no `updated:` field is left
alone with a message. `promoteSite.sh` is untouched.

`makeMeta.py`'s "the dateline contradicts the JSON-LD" abort is now
structurally unreachable for these pages: both come from one `date:`.

## 6. What was frozen, and what was fixed

The tree round-trips byte-for-byte, which is what dragged its inconsistencies
into the open. Per the plan: freeze first, then fix.

**Frozen** — expressed in the source exactly as they stand:

| drift | how it is said now |
|---|---|
| gzipt's "Conclusion" is `<h4>`/gopher h4 but `###` on gemini | `@ gemini.level=3` |
| gopher's ntppool prints the ntpstats link as a parenthetical | `gopher=-` + `{gopher: …}` |
| gopher's gzipt has an 80-column rule the others lack | `@ skip=gemini` |
| gemini link groups hand-padded to 12, 14, 32, 58 | `@ gemini.col=…` |
| index: ntpstats linked on gemini/gopher, absent on the web | `::: only gemini gopher` |
| index: 🌠🏰🚀 on web and gemini, absent on the gophermap | `gopher.title:` |
| index: gemini lists "Jade K." under projects, others don't | `only=gemini` |
| index: projects point at GitHub (web) vs FTP (retro) | link table — deliberate |
| lanfalsehoods' intro is `<em>` on the web, plain elsewhere | `@ html.em` — deliberate |
| quoted filenames: `<code>x</code>` on the web, `"x"` in text | `{!html:"}` |
| the web's em dash / nbsp / `<i>` / `<strong>` conventions | `dash`, `nbsp`, markers |

**Fixed** — differences with no reason to exist, corrected in the outputs:

- ASCII hyphens in the retro copies where the web used U+2010 ("mini-language",
  "Shakespeare-ish", "general-purpose", "Homestuck-inspired", "clean-room",
  "co-creating", "hobbyist-operated", "IPv4-only", "safety-critical").
- ASCII apostrophes in `gemini/index.gmi`, `gopher/gophermap` and the
  ntpuserinfo copies where the web used U+2019.
- `<a href=…>` with an unquoted attribute in ntppost.html.
- `&nbsp;` entities in ntpuserinfo.html where every other page uses the
  character.
- A doubled space in hypnospace.html, three whitespace-only lines in
  index.html, a stray blank line before `</main>` in ntppool.html, and
  trailing blank lines in four gopher files.
- `gopher/services.txt` now follows `gemini/services.gmi`, which was the fuller
  of the two. They had drifted into different structures; both still say finger
  is "currently being set up" and promise an explainer "coming soon", which are
  now one edit to fix rather than two.

## 7. Known warts

- **One passage is written twice.** gzipt's "Context Text / gzip Samples" dump
  is a titled blockquote with a `<pre>` on the web and indented text in the
  retro copies; the two shapes share no structure, so the `.tri` carries a
  `::: raw html` and a `>>>` block with the same sample lines. It is marked
  with a comment in the source.
- The importer that produced the first drafts lives in the scratchpad, not the
  repo: it was a one-shot, and a second run would be a rewrite, not an import.
- `services` is a two-target page (`targets: gemini gopher`); nothing renders a
  services page for the web. If one is ever wanted, drop the `targets:` line.
