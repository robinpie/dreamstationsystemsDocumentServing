# dreamstation.systems 🏰 web monorepo

Monorepo for everything the web server serves and the config for it.

mta-sts.dreamstation.systems and openpgpkey.dreamstation.systems are separate vhosts in `nginx/` sharing one docroot, so `.well-known/mta-sts.txt` and `.well-known/openpgpkey/` are in `rootdomain/` too.

`unicodePedanticism.txt` is the rules I try to follow for prose.

Some scripting and layout is AI-assisted, and there’s some AI‐slop documentation at `nginx.txt`, `site-assets.txt`, `githooks.txt`, and `ubuntu804theme.txt` (i’ll try to clean the documentation up eventually). The served prose is mine, of course.

| Subtree          | Domain / destination                             | License        |
|------------------|--------------------------------------------------|----------------|
| `openget/`       | https://grandexchange.dreamstation.systems       | GPL-2.0-only   |
| `rootdomain/`    | https://dreamstation.systems                     | mixed / messy  |
| `cgi/`           | https://dreamstation.systems/professional/status | mixed / messy  |
| `nginx/`         | `/etc/nginx`                                     | mixed / messy  |
| `status-sample/` | `/usr/local/bin` + systemd                       | mixed / messy  |
| `assets-build/`  | build-time only, not served                      | mixed / messy  |