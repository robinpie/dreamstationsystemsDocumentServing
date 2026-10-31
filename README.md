# dreamstation.systems 🏰 document monorepo

Monorepo for content served on the W3, Gopher, and Gemini, as well as config, software, and tools.

This probably won’t be very useful for anyone but me, I’m publishing this for transparency.

mta-sts.dreamstation.systems and openpgpkey.dreamstation.systems are separate vhosts in `fhs/etc/nginx/` sharing one docroot, so `.well-known/mta-sts.txt` and `.well-known/openpgpkey/` are in `staticish/http/dreamstation.systems/` too.

The main site’s pages (`staticish/http/dreamstation.systems/personal/`’s index, blog, and posts, plus the Gopher hole’s and Gemini capsule’s `services` page) are generated from one source per page under `unbuiltContent/triptychContent/`, rendered to HTML, Gopher, and Gemini by `triptych.pl`. 

`docs/unicodePedanticism.txt` is the rules I try to follow for prose.

Some scripting and layout is AI-assisted, and there’s some AI‐slop documentation in various text files (i’ll try to clean the documentation up eventually). The served prose is mine, of course.

| Subtree                                                           | Domain / destination                                                        | License       |
|-------------------------------------------------------------------|-----------------------------------------------------------------------------|---------------|
| `openget/`                                                        | https://grandexchange.dreamstation.systems                                  | GPL-2.0-only  |
| `staticish/http/dreamstation.systems/`                            | https://dreamstation.systems                                                | mixed / messy |
| `cgi/`                                                            | https://dreamstation.systems/professional/status                            | mixed / messy |
| `staticish/gopher/dreamstation.systems/`                          | gopher://dreamstation.systems                                               | mixed / messy |
| `staticish/gemini/dreamstation.systems/`                          | gemini://dreamstation.systems (+ `spartan://`)                              | mixed / messy |
| `fhs/etc/nginx/`                                                  | `/etc/nginx`                                                                | mixed / messy |
| `fhs/etc/`                                                        | the rest of `/etc` (gophernicus, molly-brown, fail2ban, …)                  | mixed / messy |
| `statusSample/`                                                   | `/usr/local/bin` + systemd                                                  | mixed / messy |
| `buildTimeTools/assetsBuild/`                                     | build-time only, not served                                                 | mixed / messy |
| `buildTimeTools/lawaPage/`                                        | builds the lawa stats page                                                  | mixed / messy |
| `buildTimeTools/triptych/`                                        | `triptych.pl` + `triptych.conf`: renders one source to HTML, Gopher, Gemini | mixed / messy |
| `unbuiltContent/triptychContent/`                                 | source for `triptych.pl`, not served directly                               | mixed / messy |
| `unbuiltContent/triptychTemplates/`                               | page chrome for `triptych.pl`, not served directly                          | mixed / messy |
| `gitHooks/`                                                       | pre-commit chain and the post-commit staging hook                           | mixed / messy |
| `deploy/`                                                         | helpers for `stageSite.sh` / `promoteSite.sh`                               | mixed / messy |
| `docs/`                                                           | notes on how all of the above fits together                                 | mixed / messy |
| `staticish/http/modernmotherfuckingwebsite.dreamstation.systems/` | https://modernmotherfuckingwebsite.dreamstation.systems                     | CC0-1.0       |
| `staticish/http/hansendiscountelectronics.com/site/`              | https://hansendiscountelectronics.com                                       | mixed / messy |
