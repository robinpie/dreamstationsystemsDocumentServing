# pool-ntp.tesla.com — a notice served to Tesla's attack-surface scanner.
#
# Tesla points pool-ntp.tesla.com at the NTP pool by CNAME:
#
#     pool-ntp.tesla.com  ->  pool.ntp.org  ->  ~thousands of volunteer servers
#
# and then lists that hostname as an asset in their bug-bounty tooling. Their
# scanner (Assetnote ExposureScan, from 54.165.75.96 and 35.168.63.24) resolves
# it, gets whichever pool member DNS handed back that minute, and scans that
# machine as if it were Tesla's. Since 2026-08-25 it has picked us ~30,000
# times: WordPress, Confluence, log4shell, webshell uploads, the lot. Nothing
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
# PORT 80 ONLY, deliberately. Serving this over HTTPS would need a certificate
# for a hostname in tesla.com, which we cannot obtain and should not want to;
# an HTTPS scan of this Host gets a cert-mismatch against the apex block as it
# always has. The scanner's plaintext requests are the ones that reach here.
#
# If Tesla fixes their asset list, or the pool rotates us out of their resolver
# cache for good, this block stops matching anything and can be deleted. Check
# the access log for the Host before assuming it's still earning its place.

server {
    include snippets/clacks.conf;
    listen 80;
    listen [::]:80;
    server_name pool-ntp.tesla.com;

    # Same answer on every path, including the several thousand CVE probes the
    # scanner will walk through. No location block, so nothing here can reach
    # the filesystem.
    default_type text/html;
    charset utf-8;

    return 299 '<h1>This is not Tesla infrastructure!</h1>

<p>This is a hobbyist NTP, web, and miscellaneous server.</p>

<p>Over the past few days, I have been receiving tons of requests at the pool-ntp.tesla.com Host from two Assetnote scanning hosts (<code>54.165.75.96</code> and <code>35.168.63.24</code>).</p>

<p>pool-ntp.tesla.com CNAMEs to pool.ntp.org, which round-robins to thousands of volunteer NTP servers, and your scanner seems to have gotten stuck to my server.</p>

<p>You have not caused me any harm, but you are throwing exploits at strangers&rsquo; IPs.</p>

<p>I have emailed VulnerabilityReporting@tesla.com about this. If you would like, email me back at <a href="mailto:robin@dreamstation.systems">robin@dreamstation.systems</a> and I can provide detailed logs.</p>
';
}
