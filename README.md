# dreamstation.systems 🏰 web monorepo

Monorepo for everything the web server serves and the config for it, plus the Gopher hole and the Gemini capsule.

`gopher/` and `gemini/` are hand-ports of `rootdomain/personal/` — the same prose, minus the HTML chrome, rendered for two protocols that predate and postdate the web respectively. They lived in their own repos until 2026-09-07; keeping all three renderings of a post in one tree is the point of moving them here, since a post edited in one place has to be edited in three.

mta-sts.dreamstation.systems and openpgpkey.dreamstation.systems are separate vhosts in `nginx/` sharing one docroot, so `.well-known/mta-sts.txt` and `.well-known/openpgpkey/` are in `rootdomain/` too.

`unicodePedanticism.txt` is the rules I try to follow for prose.

Some scripting and layout is AI-assisted, and there’s some AI‐slop documentation at `nginx.txt`, `site-assets.txt`, `githooks.txt`, and `ubuntu804theme.txt` (i’ll try to clean the documentation up eventually). The served prose is mine, of course.

| Subtree          | Domain / destination                             | License        |
|------------------|--------------------------------------------------|----------------|
| `openget/`       | https://grandexchange.dreamstation.systems       | GPL-2.0-only   |
| `rootdomain/`    | https://dreamstation.systems                     | mixed / messy  |
| `cgi/`           | https://dreamstation.systems/professional/status | mixed / messy  |
| `gopher/`        | gopher://dreamstation.systems                    | mixed / messy  |
| `gemini/`        | gemini://dreamstation.systems (+ `spartan://`)   | mixed / messy  |
| `nginx/`         | `/etc/nginx`                                     | mixed / messy  |
| `status-sample/` | `/usr/local/bin` + systemd                       | mixed / messy  |
| `assets-build/`  | build-time only, not served                      | mixed / messy  |