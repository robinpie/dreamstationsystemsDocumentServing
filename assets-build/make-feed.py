#!/usr/bin/env python3
"""Generate Atom and RSS 2.0 feeds for /personal/blog.html.

    make-feed.py            write rootdomain/personal/{feed.xml,rss.xml}
    make-feed.py --check    exit 1 if either file is out of date, write nothing

Source of truth is the <ul class="posts"> list in blog.html (hrefs, titles,
<time datetime> values) plus each post's og:description. Output is
deterministic — no "generated at" timestamp — since the pre-commit hook
regenerates and re-stages these files on every commit. See feeds.txt.
"""

import html
import re
import sys
from pathlib import Path
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

    Deliberately a summary and not the full article. Post bodies are threaded
    with SSI conditionals and theme chrome includes that mean nothing outside
    nginx, so shipping them raw would put <!--# if expr= --> in every reader.
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
            "  </entry>",
        ]
    out += ["</feed>", ""]
    return "\n".join(out)


def rss(posts):
    latest = max(p["updated"] for p in posts)
    out = [
        '<?xml version="1.0" encoding="utf-8"?>',
        '<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">',
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
    except (PostError, OSError) as exc:
        print(f"make-feed: {exc}", file=sys.stderr)
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
            print(f"make-feed: wrote {path.relative_to(ROOT)} "
                  f"({len(posts)} posts)")

    if stale:
        print(f"make-feed: out of date: {', '.join(stale)} "
              f"— run assets-build/make-feed.py", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
