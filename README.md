# dreamstation.systems 🏰 document monorepo

Monorepo for content served on the W3, Gopher, and Gemini, as well as config, software, and tools.

This probably won’t be very useful for anyone but me, I’m publishing this for transparency.

mta-sts.dreamstation.systems and openpgpkey.dreamstation.systems are separate vhosts in `fhs/etc/nginx/` sharing one docroot, so `.well-known/mta-sts.txt` and `.well-known/openpgpkey/` are in `staticish/http/dreamstation.systems/` too.

The main site’s pages (`staticish/http/dreamstation.systems/personal/`’s index, blog, and posts, plus the Gopher hole’s and Gemini capsule’s `services` page) are generated from one source per page under `unbuiltContent/triptychContent/`, rendered to HTML, Gopher, and Gemini by `triptych.pl`. 

`docs/unicodePedanticism.txt` is the rules I try to follow for prose.

Some scripting and layout is AI-assisted, and there’s some AI‐slop documentation in various text files (i’ll try to clean the documentation up eventually). The served prose is mine, of course.

```
.
├── staticish/
│   ├── http/
│   │   ├── dreamstation.systems/
│   │   ├── modernmotherfuckingwebsite.dreamstation.systems/                                                                               [CC0-1.0]
│   │   └── hansendiscountelectronics.com/
│   ├── gopher/
│   │   └── dreamstation.systems/
│   └── gemini/
│       └── dreamstation.systems/           also served on spartan
├── cgi/                                    http(s)://dreamstation.systems/professional/status, http(s)://fortunes.dreamstation.systems
├── openget/                                http(s)://grandexchange.dreamstation.systems                                                   [GPL-2.0-only]
├── fhs/
│   └── etc/
│       ├── nginx/
│       │   ├── conf.d/
│       │   ├── sites-available/
│       │   └── snippets/
│       ├── molly-brown/
│       ├── default/
│       ├── fail2ban/
│       │   └── filter.d/
│       └── logrotate.d/
├── statusSample/                           /usr/local/bin + systemd: the status page's sampler
├── buildTimeTools/
│   ├── assetsBuild/                        feeds, sitemap, font subsets, badges
│   ├── lawaPage/                           renders the lawa stats page (a timer on the box)
│   └── triptych/                           triptych.pl + triptych.conf: a little hack I made to convert one document into HTML, gemtext, and Gopher plaintext
├── unbuiltContent/
│   ├── triptychContent/
│   ├── triptychTemplates/                  page chrome per protocol
│   └── webBadges.csv
├── gitHooks/
├── deploy/                                 helpers for stageSite.sh / promoteSite.sh
├── docs/
├── stageSite.sh                            commit hook: repo → staging
├── promoteSite.sh                          staging → live
└── dangerouslyDeployImmediately.sh         commit, promote, and push all at once
```