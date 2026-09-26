# pool-ntp.tesla.com — a notice served to Tesla's attack-surface scanner.
#
# Tesla points pool-ntp.tesla.com at the NTP pool by CNAME:
#
#     pool-ntp.tesla.com  ->  pool.ntp.org  ->  ~thousands of volunteer servers
#
# and then lists that hostname as an asset in their bug-bounty tooling. Their
# scanner (Assetnote ExposureScan, from 54.165.75.96 and 35.168.63.24) resolves
# it, gets whichever pool member DNS handed back that minute, and scans that
# machine as if it were Tesla's. It picks us over and over: WordPress,
# Confluence, log4shell, webshell uploads, the lot. Nothing
# has landed — this box serves static files and has no application to exploit —
# and the scans cost us nothing measurable. But they are being thrown at a
# stranger's IP, so the polite thing is to say so where the operator will see it.
#
# Without this block the Host falls to 000-default-catchall's 444, which closes
# the connection and tells nobody anything. Related in spirit to pool.ntp.org's
# redirect: both catch a Host we don't own but predictably receive, and answer
# it usefully instead of dropping it.
#
# 299 is not a real status code. It is in the 2xx range, so the scanner records
# a success and the response body is kept rather than discarded as an error,
# but it is odd enough to stand out in a report full of 200s and 404s — which
# is the entire point, since the audience is whoever reads the scan output.
#
# BOTH :80 AND :443. HTTPS would need a certificate for a name in tesla.com,
# which we cannot get, but that is beside the point: the scanner does not
# validate certificates. With no :443 block for this name, its HTTPS requests
# fall through to the first :443 server in config order — the apex — and get
# the real site and a 404 per path, which is exactly what the notice exists to
# prevent. Roughly half its traffic is HTTPS.
#
# So :443 reuses the dreamstation.systems certificate. It does not match this
# name and is not meant to: nginx needs *a* keypair to finish a handshake, the
# scanner ignores the mismatch, and no real client ever asks for this name. The
# mismatch is arguably useful — a cert naming dreamstation.systems tells the
# operator whose machine they are on before they have read a word of the body.
#
# This REUSES an existing certificate file; it does not add a name to one. The
# blast-radius rule that keeps grandexchange on a separate cert (see that file)
# is about re-issuing the dreamstation.systems cert, which also carries mta-sts
# and therefore inbound mail's TLS. Nothing here touches certbot.
#
# Kept out of the apex's server_name rather than added to it, because the apex
# answers with the site and this name must answer with the notice.
#
# If Tesla fixes their asset list, or the pool rotates us out of their resolver
# cache for good, these blocks stop matching anything and can be deleted. Check
# the access log for the Host before assuming they are still earning their place.

server {
    include snippets/clacks.conf;
    include snippets/accessLog.conf;
    listen 80;
    listen [::]:80;
    server_name pool-ntp.tesla.com;

    include snippets/teslaNotice.conf;
}

# Deliberately NOT `default_server`. Adding one here would change what every
# unmatched SNI gets — a bare-IP HTTPS request included — and those should keep
# reaching the apex site, which is how someone with only the address gets to a
# human. This block answers for one name and nothing else.
server {
    include snippets/clacks.conf;
    include snippets/accessLog.conf;
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name pool-ntp.tesla.com;

    ssl_certificate     /etc/letsencrypt/live/dreamstation.systems/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/dreamstation.systems/privkey.pem;

    include snippets/teslaNotice.conf;
}
