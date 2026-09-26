# hansendiscountelectronics.com — its own small static site: a mock
# mid-2000s electronics storefront. Source is hansendiscountelectronics.com/site/
# in this repo, rsynced to /srv/hansendiscountelectronics.com by promoteSite.sh
# (not staged: like modernmotherfuckingwebsite/, it goes straight from the repo
# to live). The loose JPEGs beside site/ in that directory are reference
# screenshots and are NOT deployed.
#
# It used to be an alias of the main site (root /srv/http plus the apex's
# snippet list). It no longer is: no status page, no themes, no feeds, no PGP
# key — just the files under site/.
#
# WITHOUT THIS FILE the name does not reach anything. It resolves to this
# address (A record at Spaceship, the registrar), but a Host matching no
# server_name lands in 000-default-catchall and is dropped with 444 — which is
# that block's whole job.
#
# INDEXABLE. As an alias it sent X-Robots-Tag: noindex, nofollow (duplicate
# content); with its own site it has no reason to, so it no longer includes
# snippets/robotsTag.conf and has no row in conf.d/robotsTag.conf.
#
# ITS OWN CERTIFICATE, for the reason fortunes, grandexchange and staging each
# have one: the dreamstation.systems cert also covers mta-sts, and re-issuing
# it for an unrelated name would put inbound mail's TLS in the blast radius of
# a web deploy. The cert was issued with webroot /srv/http and its renewal
# config still says so, hence the acme-challenge location below.
#
# NO www. www.hansendiscountelectronics.com has no A record, so it is not in
# the certificate — Let's Encrypt validates every name on a request and one
# that does not resolve fails the whole issuance, renewals included. To add it:
# create the A record FIRST, then re-run certbot with both names (see
# nginx.txt), then add it to the server_name line here.
#
# One server block listening on both ports rather than the usual :80/:443
# pair, as modernmotherfuckingwebsite does: the content is identical on both,
# and one block cannot drift. Port 80 is not redirected, following the apex.

server {
    include snippets/clacks.conf;
    include snippets/accessLog.conf;
    listen 80;
    listen [::]:80;
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name hansendiscountelectronics.com;

    ssl_certificate     /etc/letsencrypt/live/hansendiscountelectronics.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/hansendiscountelectronics.com/privkey.pem;

    # certbot's webroot is the apex's live docroot, where this cert was issued
    # from and where renewals will look; promote protects acme-challenge/.
    location /.well-known/acme-challenge/ {
        root /srv/http;
    }

    root /srv/hansendiscountelectronics.com;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }
}
