#!/usr/bin/env python3
"""Generate Atom and RSS 2.0 feeds for /personal/blog.html.

    makeFeed.py            write rootdomain/personal/{feed.xml,rss.xml}
    makeFeed.py --check    exit 1 if either file is out of date, write nothing

Source of truth is the <ul class="posts"> list in blog.html (hrefs, titles,
<time datetime> values) plus each post's og:description (the summary) and
its <main id="content"> (the full text). Output is
deterministic — no "generated at" timestamp — since the pre-commit hook
regenerates and re-stages these files on every commit. See feeds.txt.
"""

import html
import re
import sys
from pathlib import Path
from urllib.parse import urljoin
from xml.sax.saxutils import escape, quoteattr

ROOT = Path(__file__).resolve().parent.parent
BLOG = ROOT / "rootdomain" / "personal" / "blog.html"
OUT_ATOM = ROOT / "rootdomain" / "personal" / "feed.xml"
OUT_RSS = ROOT / "rootdomain" / "personal" / "rss.xml"

SITE = "https://dreamstation.systems"
BASE = f"{SITE}/personal/"
BLOG_URL = f"{BASE}blog.html"
ATOM_URL = f"{BASE}feed.xml"
RSS_URL = f"{BASE}rss.xml"

FEED_TITLE = "robin’s blog"
# These strings are served markup, not plaintext, so unicodePedanticism.txt
# applies to anything added here: U+2019 for apostrophes, and a real em dash
# (thin space + U+2014 + thin space) for a parenthetical.
FEED_SUBTITLE = "the least consistent blog on the W3"
AUTHOR_NAME = "robin"
AUTHOR_EMAIL = "robin@dreamstation.systems"

# Feed ids must never change once a reader has seen them, or every entry
# reappears as new. Both are permanent URLs on a domain that is not going
# anywhere, so they serve as ids directly rather than as tag: URIs.
FEED_ID = BLOG_URL

DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
          "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


class PostError(Exception):
    pass


def strip_tags(markup):
    """Plain text from a title that may carry markup.

    One post's title really does contain an <em> ("a really slow QOTD
    server"). Atom <title> defaults to type="text" and RSS titles have no
    markup at all, so tags come out and entities are unescaped to real
    characters — the XML escaper puts back whatever still needs escaping.
    """
    return html.unescape(re.sub(r"<[^>]+>", "", markup)).strip()


def rfc3339(date):
    """YYYY-MM-DD -> Atom date. The list carries days, not times."""
    return f"{date}T00:00:00Z"


def rfc822(date):
    """YYYY-MM-DD -> RSS date, built by hand.

    strftime's %a and %b are locale-dependent and RFC 822 is not; a box
    running under a non-English locale would otherwise emit day and month
    names no reader can parse.
    """
    from datetime import date as _date

    y, m, d = (int(p) for p in date.split("-"))
    dt = _date(y, m, d)
    return (f"{DAYS[dt.weekday()]}, {d:02d} {MONTHS[m - 1]} {y} "
            f"00:00:00 +0000")


def parse_posts(blog_html):
    """Pull the post list out of blog.html.

    Each <li> looks like:

        <li><a href="X">Title</a> <span class="sep">|</span>
            <time datetime="2026-09-05">2026-09-05</time>
            [<span class="sep">|</span> edited <time datetime="...">...</time>]

    The first datetime is the publication date and the last is the update
    date; where a post has never been edited they are the same value, which
    is exactly what both formats want.
    """
    block = re.search(r'<ul class="posts">(.*?)</ul>', blog_html, re.S)
    if not block:
        raise PostError('no <ul class="posts"> in blog.html')

    posts = []
    for item in re.findall(r"<li>(.*?)</li>", block.group(1), re.S):
        href = re.search(r'<a href="([^"]+)"', item)
        title = re.search(r"<a [^>]*>(.*?)</a>", item, re.S)
        dates = re.findall(r'datetime="(\d{4}-\d{2}-\d{2})"', item)
        if not (href and title and dates):
            raise PostError(f"unparsable <li>: {' '.join(item.split())[:90]}")
        posts.append({
            "href": href.group(1),
            "url": BASE + href.group(1),
            "title": strip_tags(title.group(1)),
            "published": dates[0],
            "updated": dates[-1],
        })

    if not posts:
        raise PostError("post list is empty")
    return posts


def summarize(post):
    """The entry summary: each post's own og:description.

    Shipped alongside the full text (see body()), not instead of it: readers
    use it for list previews, and Atom wants one when content is present.
    """
    path = BLOG.parent / post["href"]
    if not path.exists():
        raise PostError(f'{post["href"]} is linked from blog.html but missing')

    meta = re.search(
        r'<meta property="og:description" content="([^"]*)"',
        path.read_text(encoding="utf-8"))
    if not meta:
        raise PostError(f'{post["href"]} has no og:description')
    return html.unescape(meta.group(1)).strip()


# URL-bearing attributes in post bodies. Plenty of readers ignore Atom's
# xml:base and RSS has no base at all, so every relative reference is made
# absolute against the post's own URL.
URL_ATTR = re.compile(r'\b(href|src|poster)="([^"]*)"')
SRCSET_ATTR = re.compile(r'\bsrcset="([^"]*)"')


def body(post):
    """The entry's full text: the inside of the post's <main id="content">.

    What comes out, and why:
      - the <h1 class="post-title"> -- the reader already shows the entry
        title, and the h1 also carries the Pangram badge, which would be
        a stray image at the top of every entry;
      - HTML comments (the dateline cross-check note, any future ones) --
        stripComments.pl drops them from the served page too;
      - SSI. <main> carries none today; the theme chrome and every
        <!--# if --> sit outside it. If one ever appears inside, this
        refuses rather than ship a directive no reader can evaluate.
    Relative href/src/poster/srcset are rewritten to absolute URLs.
    """
    path = BLOG.parent / post["href"]
    text = path.read_text(encoding="utf-8")
    m = re.search(r'<main id="content">(.*?)</main>', text, re.S)
    if not m:
        raise PostError(f'{post["href"]} has no <main id="content">')
    inner = m.group(1)

    if "<!--#" in inner:
        raise PostError(f'{post["href"]}: SSI inside <main>; the feed '
                        f'cannot carry it (see feeds.txt)')

    inner = re.sub(r'<h1 class="post-title">.*?</h1>', "", inner, count=1,
                   flags=re.S)
    inner = re.sub(r"<!--.*?-->", "", inner, flags=re.S)

    base = post["url"]
    inner = URL_ATTR.sub(
        lambda u: f'{u.group(1)}="{urljoin(base, html.unescape(u.group(2))).replace("&", "&amp;")}"',
        inner)
    inner = SRCSET_ATTR.sub(
        lambda u: 'srcset="' + ", ".join(
            " ".join([urljoin(base, c.split()[0])] + c.split()[1:])
            for c in u.group(1).split(",") if c.strip()) + '"',
        inner)

    # Tidy the blank lines the removals leave behind.
    inner = re.sub(r"\n\s*\n(\s*\n)+", "\n\n", inner).strip()
    return inner


def atom(posts):
    latest = max(p["updated"] for p in posts)
    out = [
        '<?xml version="1.0" encoding="utf-8"?>',
        '<feed xmlns="http://www.w3.org/2005/Atom">',
        f"  <title>{escape(FEED_TITLE)}</title>",
        f"  <subtitle>{escape(FEED_SUBTITLE)}</subtitle>",
        f"  <id>{escape(FEED_ID)}</id>",
        f"  <updated>{rfc3339(latest)}</updated>",
        f'  <link rel="alternate" type="text/html" href={quoteattr(BLOG_URL)}/>',
        f'  <link rel="self" type="application/atom+xml" href={quoteattr(ATOM_URL)}/>',
        "  <author>",
        f"    <name>{escape(AUTHOR_NAME)}</name>",
        f"    <email>{escape(AUTHOR_EMAIL)}</email>",
        "  </author>",
    ]
    for post in posts:
        out += [
            "  <entry>",
            f'    <title>{escape(post["title"])}</title>',
            f'    <id>{escape(post["url"])}</id>',
            f'    <link rel="alternate" type="text/html" href={quoteattr(post["url"])}/>',
            f'    <published>{rfc3339(post["published"])}</published>',
            f'    <updated>{rfc3339(post["updated"])}</updated>',
            f'    <summary type="text">{escape(post["summary"])}</summary>',
            f'    <content type="html">{escape(post["body"])}</content>',
            "  </entry>",
        ]
    out += ["</feed>", ""]
    return "\n".join(out)


def rss(posts):
    latest = max(p["updated"] for p in posts)
    out = [
        '<?xml version="1.0" encoding="utf-8"?>',
        ('<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom" '
        'xmlns:content="http://purl.org/rss/1.0/modules/content/">'),
        "  <channel>",
        f"    <title>{escape(FEED_TITLE)}</title>",
        f"    <link>{escape(BLOG_URL)}</link>",
        f"    <description>{escape(FEED_SUBTITLE)}</description>",
        "    <language>en</language>",
        f"    <lastBuildDate>{rfc822(latest)}</lastBuildDate>",
        # RSS 2.0 has no self-link of its own; the Atom namespace supplies
        # one, which is what validators and most readers look for.
        f'    <atom:link rel="self" type="application/rss+xml" href={quoteattr(RSS_URL)}/>',
    ]
    for post in posts:
        out += [
            "    <item>",
            f'      <title>{escape(post["title"])}</title>',
            f'      <link>{escape(post["url"])}</link>',
            # RSS has one date per item, so an edited post shows its edit
            # date. Atom carries the distinction properly; this is the
            # format's limit, not a choice.
            f'      <pubDate>{rfc822(post["updated"])}</pubDate>',
            f'      <guid isPermaLink="true">{escape(post["url"])}</guid>',
            f'      <description>{escape(post["summary"])}</description>',
            # Full text the RSS way: description stays the summary, the
            # content module carries the article.
            f'      <content:encoded>{escape(post["body"])}</content:encoded>',
            "    </item>",
        ]
    out += ["  </channel>", "</rss>", ""]
    return "\n".join(out)


def main():
    check = "--check" in sys.argv[1:]

    try:
        posts = parse_posts(BLOG.read_text(encoding="utf-8"))
        for post in posts:
            post["summary"] = summarize(post)
            post["body"] = body(post)
    except (PostError, OSError) as exc:
        print(f"makeFeed: {exc}", file=sys.stderr)
        return 1

    stale = []
    for path, text in ((OUT_ATOM, atom(posts)), (OUT_RSS, rss(posts))):
        current = path.read_text(encoding="utf-8") if path.exists() else None
        if current == text:
            continue
        if check:
            stale.append(path.name)
        else:
            path.write_text(text, encoding="utf-8")
            print(f"makeFeed: wrote {path.relative_to(ROOT)} "
                  f"({len(posts)} posts)")

    if stale:
        print(f"makeFeed: out of date: {', '.join(stale)} "
              f"— run assetsBuild/makeFeed.py", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
