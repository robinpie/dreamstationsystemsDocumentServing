<!DOCTYPE html>
<html lang="{{lang}}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{{title}}</title>
  <meta name="description" content="{{description}}">
  <meta name="author" content="robin">
  <link rel="canonical" href="{{canonical}}">
{{?alternates}}  {{indent:alternates}}
{{/alternates}}
  <meta name="robots" content="{{robots}}">

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
  <meta property="og:locale" content="{{og_locale}}">
  <meta name="twitter:card" content="summary">

{{head_extra}}

  <link rel="stylesheet" href="base.css">
  <link rel="stylesheet" href="themes/<!--# echo var="theme" -->.css">
</head>
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
  <a class="skip" href="#content">{{s_skip}}</a>
  <!-- The ubuntu804 theme wraps this page in a picture of an Ubuntu 8.04
       desktop. The chrome is three fragments under chrome/, pulled in by
       nginx; every other theme expands these to nothing. chrome/top.html
       explains the split, and why the title and path are handed in by hand. -->
<!--# if expr="$theme = ubuntu804" --><!--# set var="wtitle" value="{{title}}" --><!--# set var="path" value="$document_uri" --><!--# include virtual="/personal/chrome/top.html" --><!--# endif -->
  <header class="site-header">
    <nav class="site-nav">
      <a href="{{nav_home}}">{{s_home}}</a>
      <a href="{{nav_blog}}">{{s_blog}}</a>
      <a href="/professional">{{s_professional}}</a>
      <a href="https://grandexchange.dreamstation.systems">{{s_openget}}</a>

    </nav>
    <div id="theme-switcher" class="theme-switcher">
{{?langswitch}}      <!-- Language switcher. Only on a page that exists in more than one
           language, and only listing the languages it exists in. A plain GET
           form like the two after it; see lang_vars in triptych.pl. -->
      {{indent:langswitch}}
{{/langswitch}}      <!-- Protocol switcher: the same page over HTTP, HTTPS or the onion
           service. Also a plain GET form with no JavaScript; nginx answers it
           with a redirect (the /personal/proto/ location in
           nginx/snippets/theme.conf). The hidden field carries the current
           theme across, since the cookie does not follow to another origin. -->
      <form method="get" action="/personal/proto<!--# echo var="document_uri" -->">
        <input type="hidden" name="theme" value="<!--# echo var="theme" -->">
        <select name="to" aria-label="{{s_protocol}}">
          <option value="https"<!--# if expr="$proto_now = https" --> selected<!--# endif -->>HTTPS</option>
          <option value="http"<!--# if expr="$proto_now = http" --> selected<!--# endif -->>HTTP</option>
          <option value="onion"<!--# if expr="$proto_now = onion" --> selected<!--# endif -->>.onion (Tor)</option>
        </select>
        <button type="submit">{{s_go}}</button>
      </form>
      <!-- A GET form, so switching themes is a plain form submission to
           ?theme=<id> and needs no JavaScript. nginx reads the parameter and
           SSI stamps the choice back in below - see nginx/snippets/theme.conf. -->
      <form method="get">
        <select name="theme" aria-label="{{s_theme}}">
          <option value="gtk2"<!--# if expr="$theme = gtk2" --> selected<!--# endif -->>GTK2</option>
          <option value="motif"<!--# if expr="$theme = motif" --> selected<!--# endif -->>Motif</option>
          <option value="skeuslop"<!--# if expr="$theme = skeuslop" --> selected<!--# endif -->>skeuslop</option>
          <option value="ubuntu804"<!--# if expr="$theme = ubuntu804" --> selected<!--# endif -->>Ubuntu 8.04</option>
          <option value="plain"<!--# if expr="$theme = plain" --> selected<!--# endif -->>Plain</option>
        </select>
        <button type="submit">{{s_apply}}</button>
      </form>
    </div>
  </header>
<!--# if expr="$theme = ubuntu804" --><!--# include virtual="/personal/chrome/mid.html" --><!--# endif -->

  <main id="content">
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
