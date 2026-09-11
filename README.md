# dreamstation.systems 🏰 document monorepo

Monorepo for content served on the W3, Gopher, and Gemini, as well as config, software, and tools.

mta-sts.dreamstation.systems and openpgpkey.dreamstation.systems are separate vhosts in `nginx/` sharing one docroot, so `.well-known/mta-sts.txt` and `.well-known/openpgpkey/` are in `rootdomain/` too.

The main site’s pages (`rootdomain/personal/`’s index, blog, and posts, plus `gopher`/`gemini`’s `services` page) are generated from one source per page under `content/`, rendered to HTML, Gopher, and Gemini by `triptych.pl`. 

`unicodePedanticism.txt` is the rules I try to follow for prose.

Some scripting and layout is AI-assisted, and there’s some AI‐slop documentation in various text files (i’ll try to clean the documentation up eventually). The served prose is mine, of course.

| Subtree          | Domain / destination                                       | License       |
|------------------|------------------------------------------------------------|---------------|
| `openget/`       | https://grandexchange.dreamstation.systems                 | GPL-2.0-only  |
| `rootdomain/`    | https://dreamstation.systems                               | mixed / messy |
| `cgi/`           | https://dreamstation.systems/professional/status           | mixed / messy |
| `gopher/`        | gopher://dreamstation.systems                              | mixed / messy |
| `gemini/`        | gemini://dreamstation.systems (+ `spartan://`)             | mixed / messy |
| `nginx/`         | `/etc/nginx`                                               | mixed / messy |
| `etc/`           | the rest of `/etc` (gophernicus, molly-brown, fail2ban, …) | mixed / messy |
| `statusSample/`  | `/usr/local/bin` + systemd                                 | mixed / messy |
| `assetsBuild/`   | build-time only, not served                                | mixed / messy |
| `content/`       | source for `triptych.pl`, not served directly              | mixed / messy |
| `templates/`     | page chrome for `triptych.pl`, not served directly         | mixed / messy |
