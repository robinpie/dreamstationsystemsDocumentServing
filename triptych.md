# triptych — one source, three panels

`triptych.pl` renders one source file per page to all three protocols at once:

```
content/post/gzipt.tri  ->  rootdomain/personal/gzipt.html   HTML, SSI, themes, JSON-LD
                            gemini/blog/gzipt.gmi            gemtext (Spartan reads it too)
                            gopher/blog/gzipt.txt            text/plain
```

It owns the main site as `rootdomain/personal/CLAUDE.md` defines it — index, blog index, the blog posts, ntpuserinfo — plus the gopher/gemini `services` page. Everything else under `rootdomain/` is still hand‐written HTML.

```
./triptych.pl                     render everything
./triptych.pl gzipt index         restrict to those page ids
./triptych.pl --check             render and diff against the tree; non-zero on any difference
./triptych.pl --list              what is written, from what
./triptych.pl --source-of <file>  the .tri an output came from; non-zero if it is not generated
```

**Do not hand‐edit a generated file.** The next commit regenerates it. Edit the `.tri`; `--source-of` tells you which files those are.

`--check` is the safety net: it is how you know a change to the renderer or a template did not quietly move every page. Run it after touching either.

---

## 1. Layout

```
content/*.tri             page sources
content/post/*.tri        one per blog post
templates/<target>/*.tpl  page chrome: <head>, SSI, nav, footers, gophermap headers
triptych.conf             per-protocol conventions + the site-wide link table
triptych.pl               the renderer
```

Outputs are committed, because `promoteSite.sh` is a plain rsync with no build step on the server: anything served has to exist in a commit.

A page’s `kind` picks its templates — `templates/<target>/<kind>.tpl`, falling back to `page.tpl`:

| kind | what it is | notes |
|---|---|---|
| `post` | a blog post | HTML template owns the `<h1>` (it carries the dateline and Pangram badge) |
| `page` | a standalone page | the `<h1>` comes from `title:` |
| `bloglist` | the blog index | `@postlist` expands to the posts |
| `index` | the site root | gophermap on gopher |

Adding a post is one file: drop it in `content/post/`, and all three blog indexes, the feeds, the sitemap and the JSON-LD follow.

## 2. Front matter

`key: value` lines between `---` markers. `|` opens an indented block. `//` starts a comment, here and in the body, that reaches no output.

```
---
id: lanfalsehoods
kind: post
title: Falsehoods Programmers Believe About LANs
date: 2026-09-05
updated: 2026-09-05
description: A list of things that are not reliably true about the local network.
pangram: https://www.pangram.com/history/…
---
```

| key | meaning |
|---|---|
| `id` | filename stem of every output |
| `kind` | template set (above) |
| `title` | plain text: `<title>`, og tags, index entries, injected `<h1>` |
| `title_markup` | the title with inline markup, for the `<h1>` only |
| `date`, `updated` | dateline, JSON-LD, index entries, feeds. `updated` shows as “edited …” when it differs |
| `description` | meta description, og:description |
| `targets` | which protocols render this page (default: all three) |
| `pangram` | the Pangram badge URL in a post’s `<h1>` (a `page` with this key gets the same badge row) |

Any key may be scoped with a target prefix, and templates ask for it by its bare name — `html.style` reaches `templates/html/*.tpl` as `{{style}}` and reaches no other target at all. Scoped keys the renderer itself acts on:

| key | effect |
|---|---|
| `<t>.title` | a different title on that target (the gophermap drops the emoji) |
| `<t>.notitle` | suppress the injected heading; the template supplies it |
| `<t>.template` | use a differently‐named template |
| `<t>.nbsp: strip` | U+00A0 becomes a plain space on that target |
| `html.tight` | `all` — no blank lines between blocks; `sections` — blanks only before a heading; `headings` — no blank after a heading |
| `gopher.map` | this output is a gophermap: non‐link lines become `i` rows |
| `gopher.gophermap_extra` | a verbatim row this page contributes to the blog gophermap |

## 3. Blocks

Blank‐line separated. Source lines are **never rewrapped** — one source line is one output line — except the two cases that must reflow: a gopher blockquote, and a table column with `wrap=`.

| source | html | gemini | gopher |
|---|---|---|---|
| `# …` … `#### …` | `<h1>`–`<h4>` | `#`–`####` | underline `=`, `-`, `~`, `.` |
| `- item` | `<ul><li>` | `* item` | `- item` |
| `1. item` | `<ol><li>` | `1. item` | `1. item` |
| paragraph | `<p>` | as written | as written |
| ` ```lang ` | `<pre><code class="language-…">` | fenced, indented | indented |
| ` ``` ` | `<pre>` | fenced, indented | indented |
| `> quote` | `<blockquote><p>` | `> ` | wrapped, indented |
| `>>> … >>>` | `<blockquote>` of `<br>`-joined stanzas | fenced verbatim | verbatim |
| `\| a \| b \|` | `<table>` | column‐aligned, fenced | column‐aligned |
| `[^1]: text` | `<hr>` + `<aside role="doc-footnote">` | `[1] text` | `[1] text` |
| `----` | `<hr>` | `---` | 80 hyphens |
| `=> [label](ref)` | `<ul>` of anchors | `=>` lines | link lines, or gophermap rows |
| `@postlist` | the post set, in each protocol’s idiom | | |

A list item may carry blocks of its own, indented three spaces — a paragraph, a table, a code block — which is how numbered walkthroughs are written.

Preformatted source is held **unindented**: HTML prints it flush inside `<pre>`, and both retro targets indent it (4 by default, `indent=`).

Tables: a `| --- |` row marks the row above it as a header. Escape a literal pipe in a cell as `\|`.

## 4. Inline

| source | html | gemini and gopher |
|---|---|---|
| `*em*` | `<em>` | `*em*` |
| `~cite~` | `<cite>` | `*cite*` |
| `**strong**` | `<strong>` | plain words |
| `_i_` | `<i>` | plain words |
| `` `code` `` | `<code>` | plain words |
| `` `code`:lang `` | `<code class="language-…">` | plain words |
| `[^1]` | `<sup><a href="#footnote-1">` | `[1]` |
| `[text](ref)` | see below | see below |
| `\x` | a literal `x` | a literal `x` |

Emphasis can contain a link; the asterisks survive into the retro copies and the anchor inside them does not.

**No smart typography.** The source carries the exact U+2019, U+2010, U+00A0 and U+2014 that ship (see `unicodePedanticism.txt`). The renderer substitutes only what genuinely differs by medium, and each is a switch in `triptych.conf` or the front matter:

- `dash = thin` — a parenthetical em dash becomes thin space + em dash + thin space on the web, and stays plain‐spaced in text/plain.
- `code_angle = strip` — `` `<div>` `` is a tag on the web and the word “div” in text/plain, where angle brackets mean a bare URL.
- `tabs = 4` — a leading tab inside preformatted text becomes four columns.
- `<t>.nbsp: strip` — per page, for the text copies.

## 5. Links

Write the link once. Each protocol renders it the way that protocol does.

```
Do you have [the ability to accept inbound connections](@ntppost)?
```

| target | default | what it does |
|---|---|---|
| html | `inline` | a real `<a>` |
| gemini | `defer` | the words stay in the prose; a `=> url  label` line follows the block, column‐aligned across the group |
| gopher | `trail` | `label: <url>` after the block |

Other gopher modes: `bare` (just `<url>` on its own line, tight against the paragraph) and `after` (the URL inline, right after the words). Set one per link with `gopher.mode=`.

`@id` resolves against `[links]` in `triptych.conf` or a page’s own `@links` block, which shadows it. Rows continue with a trailing `\`.

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

| field | meaning |
|---|---|
| `url=` | the same URL everywhere |
| `<t>=` | the URL on that target |
| `<t>=-` | **no link there**: the anchor text stays as prose |
| `<t>.label=` | text of the `=>` or trailing line, when the anchor reads badly alone |
| `<t>.mode=` | override the target’s default mode |
| `<t>.col=` | pin this one gemini line’s label column |
| `gopher.sel=` | the bare selector a gophermap row needs, as against the `/0/…` URL prose uses |

`@post:<id>` is defined automatically for every post, so no page ever spells out another page’s three URLs.

A block of `=>` lines is a link list. On html it is a `<ul>`; `html.as=p` makes it a run of `<p>`s and `html.pair=1` reads each label as `term | gloss` and links only the term. Entries may be scoped or given verbatim:

```
=> only=gemini,gopher [Oboe, a general-purpose language …](@oboe)
=> raw=html   <li>…verbatim…</li>
```

In a gophermap, link rows are typed automatically: `h` with a `URL:` selector for an absolute URL, `0` for a `.txt` selector, `1` otherwise.

## 6. Putting a piece in one place only

Five mechanisms, smallest first.

1. **Inline conditional** — `{html:…}`, `{!gopher:…}`, `{gemini gopher:…}`. Everything after the colon is content, leading space included.
   ```
   it produced [this beauty](@demo){gopher: (screenshot served alongside this post: …)}
   ```
2. **Inline verbatim** — `[[html:<span class="sep">|</span>]]`, for markup one medium has no equivalent for.
3. **Block attributes** — an `@` line immediately before a block. Bare keys apply everywhere, `target.key` narrows.
4. **Region fences** — `::: only gemini gopher` … `:::`, or `::: skip html`, around any number of blocks.
5. **Raw passthrough** — `::: raw html` … `:::` emits its lines byte‐for‐byte into that one target; `::: raw html head` puts them in the template’s `{{head_extra}}` instead of the body. This is the escape hatch that lets anything be expressed: what is not worth modelling is carried literally.

### Block attributes

| attribute | applies to | effect |
|---|---|---|
| `only=`, `skip=` | any | space‐separated target list |
| `tight=1` | any | no blank line before this block |
| `blank=N` | any | N blank lines before this block |
| `level=` | heading | override the level |
| `class=` | paragraph, list, table, links, pre | an HTML class |
| `html.em` | paragraph | wrap it in `<em>` |
| `html.as=p` | links | render as `<p>`s, not a `<ul>` |
| `html.pair=1` | links | label is `term \| gloss`; link only the term |
| `html.pair=1` | list | `term \| gloss` → em dash on the web, parenthesis in text |
| `pair=labels` | list | a contact block: `<span class="label">` on the web, an aligned column in text |
| `html.rowheader=1` | table | first cell of each row is `<th scope="row">` |
| `gap=`, `wrap=` | table | column gap; wrap width for the last column |
| `indent=` | pre, table, list, quote | leading spaces on the retro targets |
| `join=1` | pre | merge with the next `pre` on the retro targets (a command and its output are two `<pre>`s on the web, one block in text) |
| `gemini.col=`, `gemini.gap=` | links | label column, or the gap when it is computed |
| `gemini.align=line` | links | each line gets its own gap instead of a shared column |
| `gopher.wrap=` | paragraph, quote | reflow to this width |

## 7. Templates

`templates/<target>/<kind>.tpl` holds everything that is page chrome, verbatim — `<head>`, SSI conditionals, nav, theme switcher, badge markers, gemtext footers, gophermap headers, and every explanatory comment. A `.tri` contains content and metadata, never chrome.

- `{{key}}` substitutes; `{{?key}}…{{/key}}` keeps its contents only when the key is non‐empty; `{{indent:key}}` re‐indents a multi‐line value to the column the placeholder sits at.
- Available: every front‐matter key, every `<t>.`‐scoped key by its bare name, plus `url`, `body`, `head_extra`, `title_esc`, `title_h1`, `title_class`, `edited`, `year`, and on HTML `badges` and `blogld`.
- A line of preformatted content is flagged so the indenter leaves it flush; raw blocks are never re‐indented, so they carry their own indentation.
- Runs of blank lines left by an absent `{{?key}}` section are collapsed before content is substituted, so a deliberate run of blank lines inside a preformatted block survives.

Two regions of the HTML belong to *other* generators and are carried through from the file on disk rather than regenerated: the `badges:start/end` wall (`badgeBuild.pl`) and blog.html’s `blogld:start/end` JSON-LD (`makeMeta.py`). Anything similar added later should follow that pattern.

## 8. The commit chain

`preCommit.sh` runs triptych **first**:

```
./triptych.pl                  render content/ -> the three trees
./datestampHook.pl             dateModified  (writes back into the .tri)
./ntpStatHook.pl               NTP figures on /professional
assetsBuild/makeFeed.py        Atom + RSS
assetsBuild/makeMeta.py        sitemap + blog JSON-LD, and its cross-checks
assetsBuild/makeFontSubset.py  DejaVu subsets
assetsBuild/badgeBuild.pl      the 88x31 wall
```

The order is load‐bearing: triptych renders, the later steps fill the regions they own, and everything is staged together. It carries the feeds’ unstaged guard — a half‐finished `.tri` means no re‐render and a warning, rather than a page in the commit that no committed source describes.

`datestampHook.pl` asks `--source-of` before stamping. For a generated page it rewrites `updated:` in the front matter and re‐renders, instead of writing a date the next render would discard; a page with no `updated:` field is left alone with a message. `promoteSite.sh` is untouched.

`makeMeta.py`’s “the dateline contradicts the JSON-LD” abort is structurally unreachable for these pages: both come from one `date:`.

## 9. Translations

A translation is a second `.tri` with the same `id`, under `content/<lang>/`:

```
content/post/gzipt.tri      ->  rootdomain/personal/gzipt.html       gemini/blog/gzipt.gmi      gopher/blog/gzipt.txt
content/tok/post/gzipt.tri  ->  rootdomain/personal/gzipt.tok.html   gemini/tok/blog/gzipt.gmi  gopher/tok/blog/gzipt.txt
```

Languages are the rows of `[langs]` in `triptych.conf`; the id is the BCP 47 tag (`tok`, toki pona’s ISO 639‐3 code) and is what lands in `<html lang>`, `hreflang` and the paths. Adding a language is a row there, a directory here, and one more alternative in the two regexes in `nginx/snippets/theme.conf`.

**Distinct URLs, not negotiation.** A language is content, not presentation, so it is not a cookie the way the theme is: each version has its own address, can be linked, cached and indexed, and works identically over the onion service. Nothing reads `Accept-Language`.

**A suffix on the web, a directory on the retro protocols.** `gzipt.tok.html` sits *beside* `gzipt.html`, so every relative path the templates and the posts already use — `base.css`, `themes/`, `badges/`, a post’s images — resolves unchanged, `badgeBuild.pl`’s flat `*.html` glob finds it, and the theme cookie’s `Path=/personal/` covers it. (`<base href>` would have rescued a `/personal/tok/` directory, and broken every `#fragment` link.) Gopher cannot do the same, because a gophermap is found by being *named* `gophermap`; and nothing there is relative, so a `tok/` directory costs nothing.

**A translation states only what is language.** Front matter it omits is inherited from the page it translates — `kind`, `date`, `html.style`, the gophermap switches — and so is that page’s `@links` table. Not inherited, because each would be a false claim on the translation: the titles (`title` is required), `updated`, `draft`, and `pangram`, which attests to the English text.

**Links are written once, as ever.** A translation links `[…](@blog)` or `[…](@post:gzipt)` exactly as the source does. If the page it names has a translation in the same language the link goes there; if not, it goes to the source‐language page. So translating the site one page at a time never leaves a dead link and never needs a link revisited. The templates’ own nav (`{{nav_home}}`, `{{nav_blog}}`) and `@postlist` follow the same rule — a translated blog index lists the posts that exist in its language.

**Every version announces the others.** Pages with more than one version get reciprocal `hreflang` lines (self‐inclusive, `x-default` on the source) and a **language switcher**: a third GET form in the `#theme-switcher` corner, before the protocol and theme ones, with one `<option>` per version that exists, each named in its own language. Like its neighbours it needs no JavaScript — it submits `?lang=<id>` to `/personal/lang/personal/<this page>`, and nginx (`snippets/theme.conf`, with the `$lang_suffix` map beside the theme maps) redirects to the same page with its suffix swapped, falling back to English if that version does not exist. On Gemini and Gopher the switcher is a link line (or gophermap row) per other version. A page with no translation gets none of this, and is byte‐identical to what it was before any of it existed.

**`draft: 1`** is how a translation is worked on. A draft

- renders to **html only** — the web is the one protocol with a staging tree, so a gopher or gemini draft would be live the moment it was promoted;
- is `noindex, nofollow`;
- is linked from nothing published. The source page’s switcher link and `hreflang` line are wrapped in `<!--# if expr="$drafts" -->`, an nginx map that is true on the staging vhost only — so staging previews the switcher exactly as it will ship and the live site says nothing. Drafts do link to each other, so a half‐translated site can be walked on staging.

A promote does carry the draft *file* to the live docroot, where it is reachable by URL, unlinked and unindexed — the standing `lawa.html` has. Publishing is deleting the `draft:` line.

**Chrome strings** are `[strings]` in `triptych.conf`, overridden key by key in `[strings.<lang>]`; templates ask for `{{s_<key>}}`. A missing translation falls back to English rather than shipping empty. Template variables: `lang`, `og_locale`, `canonical`, `robots`, `alternates`, `langswitch`, `nav_home`, `nav_blog` (and `_p`, padded for gemtext’s aligned columns), and `original` — set on a source page and empty on a translation, which is how `index.tpl` keeps its hand‐written JSON-LD off the translations.

**The language itself** has its own guide: `content/tok/README.md` fixes the vocabulary (nimi ku suli + `linluwi`), the names rule and a shared glossary, and `assetsBuild/nimiCheck.pl <file>` checks a `.tri` or a hand‐written `.html` against that vocabulary — a spell‐checker for stray English and nimi sin, not a judge of the toki pona. It is not part of the commit chain.

**Not done yet**, deliberately — none of it blocks translating:

- JSON-LD for translated `index`/`blog` (posts have it; `inLanguage` follows the page). Needs a decision about `@id`s, and `makeMeta.py` only knows `blog.html`.
- The sitemap and the feeds are English‐only.
- `chrome/*.html` (the ubuntu804 desktop’s menus) is English. (The generated body of `lawa.tok.html` is not: `lawaPage.pl` renders a toki pona fragment, `lawa-data.tok.html`, from the translations in its own `__DATA__` — see `~/configNotes/lawa.txt`.)
- `ntpuserinfo`’s hand‐written JSON-LD head block is left off its translation, for the same `@id` reason.
- Label text in the site‐wide `[links]` table is English; `content/tok/index.tri` restates the three rows it needs. A `[links.<lang>]` section would be the tidy version.
- `/professional/` is hand‐written, so its translation is too: `index.tok.html` beside `index.html`, same suffix convention, the same `$drafts` gate written by hand, and a two‐link language `<nav>` under the protocol one. The stub’s leading comment says how to fill it in.

## 10. Notes for later

- **Two protocols, one page.** `targets: gemini gopher` in the front matter renders only those; `services` uses it. Dropping the line adds the web.
- **A passage with no shared structure** is the one thing that has to be written twice — a raw block for one target and an ordinary block for the others. It is worth a `//` comment saying why, so the duplication reads as a decision rather than an oversight. gzipt’s sample dump is the example.
- **Where a quirk lives tells you what it is.** A convention that holds for a protocol belongs in `triptych.conf`; one that holds for a page belongs in its front matter; one that holds for a block belongs in an `@` line. If a rule is being retyped, it is in the wrong one of the three.
