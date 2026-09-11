<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{{title}}</title>
  <meta name="description" content="{{description}}">
  <meta name="author" content="robin">
  <link rel="canonical" href="{{url}}">

  <meta name="robots" content="index, follow, max-image-preview:large, max-snippet:-1, max-video-preview:-1">

  <!-- Follows the server-selected theme: nginx maps $theme to a colour and
       SSI stamps it in, the same way the stylesheet above it is chosen. Four
       of the five themes are fixed-appearance, so their two values are equal
       on purpose; only `plain` (browser defaults) really differs. The maps
       are in nginx/sites-available/dreamstation.systems. -->
  <meta name="theme-color" content="<!--# echo var="theme_color_light" -->" media="(prefers-color-scheme: light)">
  <meta name="theme-color" content="<!--# echo var="theme_color_dark" -->" media="(prefers-color-scheme: dark)">

  <link rel="icon" href="/favicon.svg" type="image/svg+xml">
  <link rel="icon" href="/favicon.ico" sizes="32x32">
  <link rel="apple-touch-icon" href="/apple-touch-icon.png">

  <meta property="og:type" content="article">
  <meta property="og:title" content="{{title}}">
  <meta property="og:description" content="{{description}}">
  <meta property="og:url" content="{{url}}">
  <meta property="og:site_name" content="robin’s page">
  <meta property="og:locale" content="en_US">
  <meta property="article:published_time" content="{{date}}">
  <meta property="article:modified_time" content="{{updated}}">
  <meta property="article:author" content="https://dreamstation.systems/professional/">
  <meta name="twitter:card" content="summary">

  <!-- JSON-LD. Every claim here mirrors something stated in the body below.
       Part of the site-wide graph rooted at /professional/index.html and
       joined to it by @id; nodes defined in full there appear here with
       identity only. See that file, and index.html in this directory. -->
  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "BlogPosting",
        "@id": "{{url}}#post",
        "mainEntityOfPage": "{{url}}",
        "url": "{{url}}",
        "headline": "{{title}}",
        "description": "{{description}}",
        "inLanguage": "en",
        "datePublished": "{{date}}",
        "dateModified": "{{updated}}",
        "author": { "@id": "https://dreamstation.systems/professional/#robin" },
        "publisher": { "@id": "https://dreamstation.systems/professional/#robin" },
        "isPartOf": { "@id": "https://dreamstation.systems/personal/blog.html#blog" }
      },
      {
        "@type": "Blog",
        "@id": "https://dreamstation.systems/personal/blog.html#blog",
        "name": "robin’s blog",
        "url": "https://dreamstation.systems/personal/blog.html"
      }
    ]
  }
  </script>

  <link rel="stylesheet" href="base.css">
  <link rel="stylesheet" href="themes/<!--# echo var="theme" -->.css">
{{?style}}  <style>
    {{indent:style}}
  </style>
{{/style}}</head>
<body>
  <!-- FIRST thing in the document, so it is the first tab stop under every
       theme. It used to live in chrome/top.html, which meant it existed only
       under ubuntu804 and the other four themes shipped no skip link at all —
       while the accessibilitySummary on the #website node in
       /professional/index.html claims one for the whole site. Being here it
       also precedes the chrome include below, so it stays ahead of the
       desktop's six menus and the nav row.

       base.css holds it off-screen until focus; ubuntu804.css restyles it to
       match the desktop. Geometry is unchanged by the move: it is absolutely
       positioned against the initial containing block either way, since
       neither .desktop nor body is positioned. -->
  <a class="skip" href="#content">Skip to page content</a>
  <!-- The ubuntu804 theme wraps this page in a picture of an Ubuntu 8.04
       desktop. The chrome is three fragments under chrome/, pulled in by
       nginx; every other theme expands these to nothing. chrome/top.html
       explains the split, and why the title and path are handed in by hand. -->
<!--# if expr="$theme = ubuntu804" --><!--# set var="wtitle" value="{{title}}" --><!--# set var="path" value="$document_uri" --><!--# include virtual="/personal/chrome/top.html" --><!--# endif -->
  <header class="site-header">
    <nav class="site-nav">
      <a href="index.html">🏠 home</a>
      <a href="blog.html">📓 blog</a>
      <a href="/professional">💼 my professional site</a>
      <a href="https://grandexchange.dreamstation.systems">📈 OpenGET</a>

    </nav>
    <div id="theme-switcher" class="theme-switcher">
      <!-- A GET form, so switching themes is a plain form submission to
           ?theme=<id> and needs no JavaScript. nginx reads the parameter and
           SSI stamps the choice back in below - see nginx/snippets/theme.conf. -->
      <form method="get">
        <select name="theme" aria-label="Theme">
          <option value="gtk2"<!--# if expr="$theme = gtk2" --> selected<!--# endif -->>GTK2</option>
          <option value="motif"<!--# if expr="$theme = motif" --> selected<!--# endif -->>Motif</option>
          <option value="skeuslop"<!--# if expr="$theme = skeuslop" --> selected<!--# endif -->>skeuslop</option>
          <option value="ubuntu804"<!--# if expr="$theme = ubuntu804" --> selected<!--# endif -->>Ubuntu 8.04</option>
          <option value="plain"<!--# if expr="$theme = plain" --> selected<!--# endif -->>Plain</option>
        </select>
        <button type="submit">Apply</button>
      </form>
    </div>
  </header>
<!--# if expr="$theme = ubuntu804" --><!--# include virtual="/personal/chrome/mid.html" --><!--# endif -->

  <main id="content">
    <h1 class="{{title_class}}"><span>{{title_h1}}</span><a href="{{pangram}}"><img src="pangramHumanBadge.webp" alt="Pangram 100% Human badge" width="88" height="31"></a></h1>
    <!-- The post's own dateline. Cross-checked against the list in
         blog.html by assetsBuild/makeMeta.py, along with the dates in
         the JSON-LD above. -->
    <p class="dateline"><time datetime="{{date}}">{{date}}</time>{{?edited}}, edited <time datetime="{{updated}}">{{updated}}</time>{{/edited}}</p>

    {{indent:body}}
  </main>
  <footer>
    <ul class="badges">
    {{badges}}
    </ul>
  </footer>
<!--# if expr="$theme = ubuntu804" --><!--# include virtual="/personal/chrome/bottom.html" --><!--# endif -->
</body>
</html>
