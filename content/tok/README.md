# nasin pi toki pona lon lipu ni — translation style guide

For whoever (human or model) translates a page of dreamstation.systems into
toki pona. `triptych.md` §9 covers the mechanics; this file covers the language.
`assetsBuild/nimiCheck.pl <file>` enforces the vocabulary rule mechanically.

## Vocabulary: nimi ku suli + linluwi, nothing else

The 120 pu words (with `ali` as a spelling of `ale`), the 17 nimi ku suli, and
`linluwi`:

    a akesi ala alasa ale ali anpa ante anu awen e en esun ijo ike ilo insa
    jaki jan jelo jo kala kalama kama kasi ken kepeken kili kiwen ko kon kule
    kulupu kute la lape laso lawa len lete li lili linja lipu loje lon luka
    lukin lupa ma mama mani meli mi mije moku moli monsi mu mun musi mute
    nanpa nasa nasin nena ni nimi noka o olin ona open pakala pali palisa pan
    pana pi pilin pimeja pini pipi poka poki pona pu sama seli selo seme sewi
    sijelo sike sin sina sinpin sitelen sona soweli suli suno supa suwi tan
    taso tawa telo tenpo toki tomo tu unpa uta utala walo wan waso wawa weka
    wile

    epiku jasima kijetesantakalu kin kipisi kokosila ku lanpan leko meso
    misikeke monsuta n namako oko soko tonsi

    linluwi

No other nimi sin (no `kiki`, `majuna`, `apeja`, `pake`, `powe`, `isipin`,
`usawi`, `wa`, `yupekosi`, …). If a thought will not fit, say it another way
or say less. toki pona is allowed to be vaguer than the English; it is not
allowed to be wrong.

## Names

- robin is **jan Apen**. (On /professional/, where a reader needs the legal
  name to act on it: `jan Apen (Robin Reel)` once, then jan Apen.)
- Every other person keeps their name as written, after `jan`: `jan Jade K.`
  Do not invent a tokiponisation of anybody's name.
- Technical and product names stay in their real spelling, because a reader
  has to be able to type them: NTP, NTS, gzip, Gopher, Gemini, Spartan, DICT,
  QOTD, nginx, chrony, Tesla, Hypnospace Outlaw, OpenGET, GitHub, ThinkPad.
  Give each a toki pona head noun the first time, and whenever the grammar
  wants one: `nasin NTP`, `ilo gzip`, `kulupu Tesla`, `musi Hypnospace Outlaw`,
  `ilo nginx`, `lipu GitHub`.
- Countries and languages with an established toki pona name use it:
  `ma Mewika`, `toki Inli`. Otherwise keep the real spelling after `ma`/`toki`.
- The crawler is called lawa already. Write `ilo lawa`.
- Commands, code, config, file names, URLs, addresses, sample output, header
  names, error strings: verbatim, never translated, never tokiponised.

## Numbers, dates, units

- Digits, not `luka luka tu`, grouped the way the English source groups them
  (`743,000,000`). `ilo 4000`, `tenpo suno 30`, `nanpa 20`.
  Ordinals: `nanpa 3`. Big round figures may become `mute` when the exact
  number is not the point.
- Dates stay ISO (`2026-09-05`). Years: `tenpo sike 2008`.
- Units stay as symbols after the digits: `45 kB`, `5 ms`.

## Glossary — use these so the pages agree with each other

| English | toki pona |
|---|---|
| web page / document | lipu (where it must not be mistaken for email: `lipu W3`) |
| the Web | linluwi W3; the real Web, as against a game’s: `linluwi lon` |
| web server | ilo pana W3 |
| this website | lipu mi, kulupu lipu ni |
| home page | lipu open |
| blog | lipu toki (mi) |
| blog post | toki (lon lipu toki), lipu |
| my professional site | lipu pali mi |
| the internet / a network | linluwi |
| a LAN | linluwi lili, linluwi tomo |
| protocol | nasin toki (pi ilo sona) → `nasin NTP`, `nasin Gopher` |
| computer | ilo sona |
| server (machine or daemon) | ilo pana |
| client | ilo kute (it asks and listens) |
| program, software, tool | ilo |
| code / programming language | toki ilo |
| to program | pali e ilo, sitelen e toki ilo |
| bug / vulnerability | pakala / lupa ike |
| security | awen, nasin awen |
| clock / time server | ilo tenpo / ilo pana tenpo |
| email | lipu linluwi (address: `nimi pi lipu linluwi`) |
| link | nimi tawa, linja |
| file | lipu |
| directory | poki lipu |
| data | sona, nanpa |
| user / visitor | jan kepeken / jan lukin |
| theme (of the site) | selo |
| status page | lipu pi pilin ilo |
| game | musi |
| friend | jan pona |
| project | pali |
| open source | ilo pi toki ilo open |
| request / response | wile / pana |
| packet | poki lili |
| IP address | nanpa IP |
| port | lupa (`lupa 123/UDP`) |
| router | ilo nasin |
| firewall | sinpin awen |
| hostname | nimi ilo |
| the NTP Pool | kulupu NTP Pool |
| VPS / virtual machine | ilo VPS / ilo sona lon insa pi ilo sona ante |
| logs | lipu sona |
| crawler | ilo alasa |
| header (HTTP) | nimi sewi (keep the real header names verbatim) |
| compression | lili e lipu, pali lili |
| font | sitelen nimi, nasin sitelen |

Anything not here: pick the plainest phrase, and reuse it within the page.

## Voice

robin writes lowercase, casual, funny, first person. Keep that. Keep the
jokes if they survive; if a joke depends on English wordplay, translate the
point and let the pun go rather than explaining it. Do not add content, do
not drop content (code, tables, lists and links all stay), do not soften.

Long English sentences become several short toki pona ones. Prefer `la`
context phrases and separate sentences to stacked `pi`. Never two `pi` in a
row where a second sentence would do.

## Typography

toki pona prose here is ASCII apart from what is carried over verbatim: no
apostrophes or curly quotes are needed. Quoted speech and titles take `“…”`
(U+201C/U+201D) as in the English pages. Sentences start lowercase; only
proper names are capitalised. A parenthetical dash is written ` — ` exactly as
the English source writes it (the renderer thins the spaces). Do not retypeset
quoted text from somebody else: a quotation in English stays in English,
followed by a toki pona gloss if the sentence needs one.

## Mechanics (the short version)

- The file is `content/tok/<same path as the English .tri>`, same `id`.
- Front matter: `id`, `draft: 1`, `title`, `description`. Everything else is
  inherited; restate a key only to change it. Title keys are NOT inherited, so
  a page with `html.page_title`, `gopher.title` or `title_markup` restates those.
- Keep every piece of triptych syntax exactly: block attribute lines (`@ …`),
  region fences (`:::`), conditional spans (`{html:…}`, `{!gopher:…}`),
  `[[html:…]]`, footnotes, link refs (`[words](@ref)` — translate the words,
  never the ref), table pipes. Translate the human text inside raw HTML blocks
  and leave the markup.
- The page's `@links` table is inherited; do not copy it. Restate a row (the
  WHOLE row) only when it carries English label text (`gemini.label=`,
  `gopher.label=`) that needs translating.
- Validate: `./triptych.pl --check <id>` must not die, and
  `./assetsBuild/nimiCheck.pl content/tok/<file>.tri` must print no unknown words.
- A lowercase proper name (a project called `xcaca`, say) is vouched for with a
  source comment, `// nimiCheck: allow xcaca viewpoint` (in hand-written HTML,
  `<!-- nimiCheck: allow … -->`). Do not backtick a name just to get it past
  the checker: backticks are `<code>` on the web.
