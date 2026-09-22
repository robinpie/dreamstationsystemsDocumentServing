# hansendiscountelectronics.com — a second name for the main site.
#
# Serves /srv/http, the apex's own docroot, with the apex's snippets: same
# content, same status page, same themed pages, under a different hostname.
# Not a redirect — the name is meant to answer with the site rather than bounce
# to it.
#
# WITHOUT THIS FILE the name does not reach the site at all. It resolves to
# this address (A record at Spaceship, the registrar), but a Host matching no
# server_name lands in 000-default-catchall and is dropped with 444 — which is
# that block's whole job, and was this name's behaviour until this file
# existed.
#
# NOINDEX. Every response carries X-Robots-Tag: noindex, nofollow, via the
# $server_name map in conf.d/robotsTag.conf and snippets/robotsTag.conf. Two
# names serving one docroot is duplicate content, and the apex is the one that
# should be found. The pages' own canonical links, their feeds and the
# /personal/ protocol switcher all point at dreamstation.systems regardless of
# which name served them, so nothing here needs to rewrite a URL — the alias is
# a doorway, not a second site.
#
# ITS OWN CERTIFICATE, for the reason fortunes, grandexchange and staging each
# have one: the dreamstation.systems cert also covers mta-sts, and re-issuing
# it for an unrelated name would put inbound mail's TLS in the blast radius of
# a web deploy.
#
# NO www. www.hansendiscountelectronics.com has no A record, so it is not in
# the certificate — Let's Encrypt validates every name on a request and one
# that does not resolve fails the whole issuance, renewals included. To add it:
# create the A record FIRST, then re-run certbot with both names (see
# nginx.txt), then add it to both server_name lines here.
#
# Port 80 is not redirected to 443, following the apex: this box's character is
# serving plain old protocols, and nothing here is sensitive. See nginx.txt.

server {
    include snippets/clacks.conf;
    include snippets/robotsTag.conf;
    include snippets/accessLog.conf;
    listen 80;
    listen [::]:80;
    server_name hansendiscountelectronics.com;

    root /srv/http;
    index index.html;

    include snippets/statusCgi.conf;
    include snippets/pgpKey.conf;
    include snippets/theme.conf;
    include snippets/feeds.conf;
}
