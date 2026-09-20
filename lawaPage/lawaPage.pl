#!/usr/bin/perl
# lawaPage.pl - pull lawa's finished analysis from starport and render the
# live part of https://dreamstation.systems/personal/lawa.html, plus the
# Gemini and Gopher copies. Runs as the unprivileged `lawapull` user from
# lawaPage.timer; lawaPublish.pl (root) then copies the results into place.
# Notes: ~/configNotes/lawa.txt, "The public page".
#
#   ssh lawapull@starport        the key is pinned there to one forced command
#     -> ~/cache/summary.json    that cats the summary; nothing else is reachable
#     -> ~/out/lawa-data.html    an HTML FRAGMENT, SSI-included by lawa.html
#        ~/out/lawa.gmi          (content/lawa.tri is the themed shell)
#        ~/out/lawa.txt
#
# EVERYTHING IN THE SUMMARY IS HOSTILE. It is arithmetic over header values
# sent by arbitrary servers on the internet. starport already squeezes strings
# into a small alphabet; this script trusts none of that: every string is
# re-filtered, every number re-coerced, and the HTML is escaped on the way out.
#
# A failed pull renders from the cached copy, so the page says how old its
# numbers are rather than silently freezing. All times shown are absolute.
use strict;
use warnings;
use utf8;
use JSON::PP ();
use POSIX qw(strftime floor);

my $HOME   = $ENV{LAWAPAGE_HOME} // '/var/lib/lawapull';
my $CACHE  = "$HOME/cache/summary.json";
my $OUT    = "$HOME/out";
my $SCHEMA = 1;
my $MAXLEN = 512 * 1024;
my $W      = 68;    # text copies stay this narrow, like ntpstats
my @SSH = ('ssh', '-T', '-i', "$HOME/.ssh/id_ed25519", '-o', 'IdentitiesOnly=yes', '-o', 'BatchMode=yes',
           '-o', 'StrictHostKeyChecking=yes', '-o', "UserKnownHostsFile=$HOME/.ssh/known_hosts",
           '-o', 'ConnectTimeout=15', 'lawapull@starport.dreamstation.systems');

# ------------------------------------------------------------------- pull
sub pull {
    local $SIG{ALRM} = sub { die "timeout\n" };
    my $buf = '';
    my $ok = eval {
        alarm 60;
        open my $p, '-|', @SSH or die "cannot run ssh: $!\n";
        binmode $p;
        while (read $p, my $chunk, 65536) {
            $buf .= $chunk;
            die "summary larger than $MAXLEN bytes\n" if length($buf) > $MAXLEN;
        }
        close $p or die "ssh exited " . ($? >> 8) . "\n";
        alarm 0;
        1;
    };
    alarm 0;
    unless ($ok) { warn "lawaPage: pull failed: $@"; return 0 }
    my $d = eval { JSON::PP->new->utf8->decode($buf) };
    unless (ref $d eq 'HASH' && ($d->{schema} // 0) == $SCHEMA && ref $d->{agg} eq 'HASH') {
        warn "lawaPage: pulled data is not a schema-$SCHEMA summary; keeping the cached copy\n";
        return 0;
    }
    open my $fh, '>', "$CACHE.tmp" or die "$CACHE.tmp: $!\n";
    binmode $fh;
    print {$fh} $buf;
    close $fh or die "$CACHE.tmp: $!\n";
    rename "$CACHE.tmp", $CACHE or die "$CACHE: $!\n";
    return 1;
}

# ------------------------------------------------------- distrustful getters
# ($) prototype ON PURPOSE: `pct(num $a, $b)` must parse as pct(num($a), $b).
# Without it `num` is a list operator and swallows $b.
sub num($) { my ($v) = @_; return defined $v && !ref $v && $v =~ /^-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?$/ ? $v + 0 : 0 }
sub txt {
    my ($v, $max) = @_;
    return '?' unless defined $v && !ref $v;
    $v =~ s/[^A-Za-z0-9 .,_+'&()\/:\-]//g;
    $v =~ s/\s+/ /g;
    $v =~ s/^ | $//g;
    $v = substr($v, 0, $max // 44);
    return length $v ? $v : '?';
}
sub hostname { my ($v) = @_; return defined $v && !ref $v && $v =~ /^[a-z0-9][a-z0-9._\-]{0,79}$/ ? $v : '(unprintable)' }
sub tbl { my ($v) = @_; return ref $v eq 'HASH' ? $v : {} }

sub commas { my $n = sprintf '%.0f', shift; 1 while $n =~ s/^(-?\d+)(\d{3})/$1,$2/; return $n }
sub pct { my ($n, $d) = @_; return $d > 0 ? sprintf('%.1f%%', 100 * $n / $d) : '-' }
sub bytes {
    my ($n) = @_;
    for my $u ([ 'TB', 1e12 ], [ 'GB', 1e9 ], [ 'MB', 1e6 ], [ 'kB', 1e3 ]) {
        return sprintf('%.2f %s', $n / $u->[1], $u->[0]) if $n >= $u->[1];
    }
    return sprintf '%d bytes', $n;
}
sub span {
    my ($s) = @_;
    return sprintf('%.1f years', $s / 31557600) if $s >= 2 * 31557600;
    return sprintf('%.0f days', $s / 86400)      if $s >= 3 * 86400;
    return sprintf('%.1f hours', $s / 3600)      if $s >= 2 * 3600;
    return sprintf('%.0f minutes', $s / 60)      if $s >= 120;
    return sprintf('%.0f seconds', $s);
}
sub stamp { return strftime('%Y-%m-%d %H:%M UTC', gmtime shift) }

# top($table, $n, %skip) -> ([name, count], ...), never the folded "(tail)"
sub top {
    my ($t, $n, $skip) = @_;
    $t = tbl($t);
    my @k = sort { num($t->{$b}) <=> num($t->{$a}) || $a cmp $b } grep { $_ ne '(tail)' && !($skip && $skip->{$_}) } keys %$t;
    splice @k, $n if @k > $n;
    return map { [ $_, num($t->{$_}) ] } @k;
}

# ------------------------------------------------------------- the document
# Built once as a list of blocks, emitted three times.
#   [h => text] [p => text] [note => text]
#   [table => { head => [...], rows => [[label, count, share_fraction|undef], ...] }]
#   [kv => [[label, value], ...]]
sub build {
    my ($d, $now) = @_;
    my $A = tbl($d->{agg});
    my $H = tbl($A->{host});
    my $N = tbl($A->{n});
    my $L = tbl($d->{live});
    my $R = tbl($A->{rec});
    my @b;

    my $gen = num($d->{generated_at});
    push @b, [ p => '<strong>lawa</strong> is my web crawler. It crawls the web '
        . 'and writes down the HTTP headers that come back from each site. Everything below is '
        . 'regenerated every few minutes from what it has seen so far.' ];
    if ($now - $gen > 5400) {
        push @b, [ p => 'NOTE: these numbers are stale. the last report from the machine lawa runs on is from '
            . stamp($gen) . ', so either lawa or the link to it is down right now.' ];
    }

    # ---- right now
    my $mode = txt($L->{mode}, 12);
    my @paused = map { txt($_, 20) } @{ ref $L->{paused} eq 'ARRAY' ? $L->{paused} : [] };
    my $doing = @paused ? 'paused (' . join(', ', @paused) . ')'
              : $mode eq 'normal' ? 'crawling'
              : $mode eq 'slow'   ? 'crawling slowly (over its monthly bandwidth budget)'
              : $mode eq 'paused' ? 'paused until next month (bandwidth budget spent)' : $mode;
    $doing = 'not running' if $gen - num($L->{t}) > 900;
    push @b, [ h => 'Status' ];
    push @b, [ kv => [
        [ 'lawa is',                $doing ],
        [ 'pace',                   commas(num $L->{fetches_last_min}) . ' requests in the last minute' ],
        [ 'servers visited',        commas(num $L->{hosts_done}) . ' finished, ' . commas(num $L->{active_hosts}) . ' in progress' ],
        [ 'servers waiting in line', commas(num($L->{backlog_new_domains}) + num($L->{backlog_other})) ],
        [ 'responses studied below', commas(num $N->{responses}) . ' from ' . commas(num $H->{answered}) . ' servers' ],
#       [ 'bandwidth this month',   bytes(num $L->{month_bytes}) . ' of a ' . bytes(num $L->{budget_soft}) . ' budget' ],
        [ 'numbers as of',          stamp($gen) ],
    ] ];
    push @b, [ note => 'The shares below are measured by hostname. Additionally, lawa takes at most 25 '
        . 'pages from any one server, and each server is counted once, when lawa has finished with it.' ];

    # ---- software
    my $ans = num $H->{answered};
    push @b, [ h => 'Web servers seen' ];
    push @b, [ table => { head => [ 'Server header', 'servers', 'share' ],
        rows => [ map { [ txt($_->[0], 30), $_->[1], $ans ? $_->[1] / $ans : undef ] } top($H->{server}, 10) ] } ];
    my $named = $ans - num(tbl($H->{server})->{'(none)'});
    push @b, [ p => pct(num $H->{server_version}, $named) . ' of the servers that name themselves also announce their '
        . 'version number.' ];
    my @pw = top($H->{powered}, 8);
    if (@pw) {
        my $pw_total = 0; $pw_total += num($_) for values %{ tbl($H->{powered}) };
        push @b, [ table => { head => [ 'X-Powered-By', 'servers', 'share of those sending it' ],
            rows => [ map { [ txt($_->[0], 30), $_->[1], $pw_total ? $_->[1] / $pw_total : undef ] } @pw ] } ];
    }

    # ---- clocks
    my $K = tbl($H->{clock});
    my $meas = num $K->{measured};
    if ($meas) {
        push @b, [ h => 'Bad time' ];
        push @b, [ p => 'A Date only has one-second resolution and the network adds delay, so "on time" means '
            . '"within about ' . (num($d->{slack}) || 2) . ' seconds".' ];
        my @rows = ([ 'on time', num $K->{ontime} ], [ 'up to 10 seconds off', num $K->{b10s} ],
                    [ '10 seconds to a minute', num $K->{b1m} ], [ 'a minute to an hour', num $K->{b1h} ],
                    [ 'an hour to a day', num $K->{b1d} ], [ 'more than a day', num $K->{bmore} ]);
        push @b, [ table => { head => [ 'server clock', 'servers', 'share' ], rows => [ map { [ @$_, $_->[1] / $meas ] } @rows ] } ];
        my $wrong = $meas - num $K->{ontime};
        push @b, [ p => 'Of the ' . commas($wrong) . ' wrong clocks, ' . commas(num $K->{slow}) . ' run slow and '
            . commas(num $K->{fast}) . ' run fast. ' . commas(num $K->{tz_hours}) . ' are wrong by a whole number of hours, '
            . 'which is likely timezone problems rather than drift. '
            . commas(num $K->{no_date}) . ' servers sent no Date at all, and ' . commas(num $K->{bad_date})
            . ' sent malformed Dates.' ];
        push @b, [ note => 'Responses served from a cache (indicated by an Age header) are left out. '
            . commas(num $K->{cached_only}) . ' servers only ever answered that way. ' ];
    }

    # ---- security headers
    push @b, [ h => 'Security headers' ];
    my $F = tbl($H->{flag});
    my $https = num $H->{https};
    push @b, [ table => { head => [ 'header', 'servers', 'share' ], rows => [
        [ 'HSTS (share of HTTPS servers)', num $H->{hsts_https}, $https ? num($H->{hsts_https}) / $https : undef ],
        map { [ $_->[0], num $F->{ $_->[1] }, $ans ? num($F->{ $_->[1] }) / $ans : undef ] }
            [ 'X-Content-Type-Options', 'xcto' ], [ 'X-Frame-Options', 'xfo' ], [ 'Content-Security-Policy', 'csp' ],
            [ 'Referrer-Policy', 'refpol' ], [ 'Permissions-Policy', 'permpol' ],
            [ 'X-XSS-Protection (deprecated)', 'xxss' ],
    ] } ];
#    push @b, [ p => 'lawa never sends a cookie, so every cookie it is handed is unprompted: '
#        . pct(num $F->{cookie}, $ans) . ' of servers set one anyway within their first few pages.' ];

    # ---- TLS
    my $T = tbl($H->{tls});
    my $tls = num $T->{total};
    if ($tls) {
        push @b, [ h => 'TLS' ];
        push @b, [ p => pct($https, $ans) . ' of servers answered over HTTPS at least once. lawa connects even when the '
            . 'certificate is bad, so here\'s what was wrong. '
            . pct(num $T->{broken}, $tls) . ' of HTTPS servers would have failed in a browser.' ];
        my $V = tbl($T->{verify});
        push @b, [ table => { head => [ 'certificate problem', 'servers', 'share of HTTPS' ], rows => [
            map { [ $_->[0], $_->[1], $_->[1] / $tls ] }
                [ 'wrong hostname', num $T->{name_bad} ], [ 'unknown or incomplete issuer', num $V->{'unknown issuer'} ],
                [ 'expired', num $V->{expired} ], [ 'self-signed', num $V->{'self-signed'} ],
        ] } ];
        push @b, [ table => { head => [ 'protocol', 'servers', 'share of HTTPS' ],
            rows => [ map { [ txt($_->[0], 12), $_->[1], $_->[1] / $tls ] } top($T->{version}, 4) ] } ];
        push @b, [ table => { head => [ 'certificate authority', 'servers', 'share of HTTPS' ],
            rows => [ map { [ txt($_->[0], 30), $_->[1], $_->[1] / $tls ] } top($H->{issuer}, 8) ] } ];
    }

    # ---- wire quirks
    push @b, [ h => 'Other quirks' ];
    push @b, [ p => 'lawa speaks my handrolled HTTP/1.1 implementation and logs each header block as the raw bytes, so we can see some stuff that HTTP libraries usually clean up.' ];
    my $resp = num $N->{responses};
    push @b, [ table => { head => [ 'quirk', 'servers', 'share' ], rows => [
        map { [ $_->[0], $_->[1], $ans ? $_->[1] / $ans : undef ] }
            [ 'same header sent more than once', num $F->{dup} ],
            [ 'every header name in lowercase',      num $H->{names_lower} ],
            [ 'answered HTTP/1.1 with HTTP/1.0',     num $F->{http10} ],
            [ 'bare LF line endings (no CR)',        num $F->{bare_lf} ],
            [ 'folded (multi-line) header values',   num $F->{obs_fold} ],
    ] } ];
    push @b, [ p => 'The average response carried ' . sprintf('%.1f', $resp ? num($N->{hdr_lines}) / $resp : 0)
        . ' header lines in ' . commas($resp ? num($N->{hdr_bytes}) / $resp : 0) . ' bytes. In total, lawa has read '
        . bytes(num $N->{hdr_bytes}) . ' of headers.' ] if $resp;

    # ---- status codes and manners
    my $S = tbl($A->{status});
    my $pages = 0; $pages += num($_) for values %$S;
    push @b, [ h => 'Status codes' ];
    push @b, [ table => { head => [ 'status', 'responses', 'share' ],
        rows => [ map { [ txt($_->[0], 3), $_->[1], $pages ? $_->[1] / $pages : undef ] } top($S, 8) ] } ];
    my $RS = tbl($A->{robots_status});
    my $SK = tbl($A->{skip});
    my $FN = tbl($A->{finish});
    push @b, [ p => commas(num $S->{418}) . ' responses were 418 I\'m a teapot, and ' . commas(num $S->{451})
        . ' were 451 Unavailable For Legal Reasons. lawa asked for ' . commas(num $N->{robots}) . ' robots.txt files and, '
        . 'because of what they said, left ' . commas(num $SK->{robots}) . ' pages alone. it walked away from '
        . commas(num $FN->{pushback}) . ' servers entirely because of 429, 503, or repeated 403s, and '
        . commas(num $FN->{dns}) . ' linked-to servers turned out not to exist any more.' ];

    # ---- geography
    if (num $d->{geo}) {
        my $geo_total = 0; $geo_total += num($_) for values %{ tbl($H->{asn}) };
        push @b, [ h => 'Where the W3 is from' ];
        push @b, [ table => { head => [ 'network', 'servers', 'share' ],
            rows => [ map { [ txt($_->[0], 34), $_->[1], $geo_total ? $_->[1] / $geo_total : undef ] } top($H->{asn}, 10) ] } ];
        my $cc_total = 0; $cc_total += num($_) for values %{ tbl($H->{country}) };
        push @b, [ table => { head => [ 'country', 'servers', 'share' ],
            rows => [ map { [ txt($_->[0], 30), $_->[1], $cc_total ? $_->[1] / $cc_total : undef ] } top($H->{country}, 10) ] } ];
        push @b, [ note => 'Countries leaves out the ' . commas(num $H->{country_anycast}) . ' servers behind Cloudflare and '
            . 'Fastly, because an anycast address is in every country at once. IP geolocation by DB-IP.' ];
    }
    my $tld_total = 0; $tld_total += num($_) for values %{ tbl($H->{tld}) };
    push @b, [ table => { head => [ 'top-level domain', 'servers', 'share' ],
        rows => [ map { [ '.' . txt($_->[0], 20), $_->[1], $tld_total ? $_->[1] / $tld_total : undef ] } top($H->{tld}, 10) ] } ];

    # ---- fun headers
    my %standard = map { $_ => 1 } qw(date server content-type content-length connection vary cache-control etag
        last-modified expires accept-ranges transfer-encoding content-encoding set-cookie location age via pragma link
        alt-svc strict-transport-security content-security-policy content-security-policy-report-only
        x-content-type-options x-frame-options referrer-policy permissions-policy x-xss-protection keep-alive
        content-language report-to nel server-timing content-disposition www-authenticate retry-after upgrade allow
        access-control-allow-origin access-control-allow-methods access-control-allow-headers
        access-control-allow-credentials access-control-expose-headers access-control-max-age
        cross-origin-opener-policy cross-origin-embedder-policy cross-origin-resource-policy origin-agent-cluster
        timing-allow-origin accept-ch critical-ch content-location p3p x-powered-by x-ua-compatible x-robots-tag
        reporting-endpoints priority);
    push @b, [ h => 'Non-standard headers' ];
    push @b, [ table => { head => [ 'header', 'servers', 'share' ],
        rows => [ map { [ txt($_->[0], 34), $_->[1], $ans ? $_->[1] / $ans : undef ] } top($H->{hdr_names}, 12, \%standard) ] } ];
    my $C = tbl($H->{clacks});
    my $clacks = 0; $clacks += num($_) for values %$C;
    if ($clacks) {
        push @b, [ p => 'And of course, X-Clacks-Overhead. ' . commas($clacks) . ' servers send it:' ];
        push @b, [ table => { head => [ 'X-Clacks-Overhead', 'servers', 'share' ],
            rows => [ map { [ txt($_->[0], 40), $_->[1], $_->[1] / $clacks ] } top($C, 5) ] } ];
    }

    # ---- record holders
    my @rec;
    my $r;
    push @rec, [ 'slowest clock', span(num $r->[0]) . ' behind', hostname($r->[1]) ] if ($r = $R->{slow_clock}) && ref $r eq 'ARRAY';
    push @rec, [ 'fastest clock', span(num $r->[0]) . ' ahead', hostname($r->[1]) ]  if ($r = $R->{fast_clock}) && ref $r eq 'ARRAY';
    push @rec, [ 'oldest Last-Modified', strftime('%Y-%m-%d', gmtime num $r->[0]), hostname($r->[1]) ]
        if ($r = $R->{oldest_lm}) && ref $r eq 'ARRAY';
    push @rec, [ 'biggest header block', commas(num $r->[0]) . ' bytes', hostname($r->[1]) ]   if ($r = $R->{hdr_bytes}) && ref $r eq 'ARRAY';
    push @rec, [ 'most header lines', commas(num $r->[0]), hostname($r->[1]) ]                 if ($r = $R->{hdr_lines}) && ref $r eq 'ARRAY';
    push @rec, [ 'most cookies in one response', commas(num $r->[0]), hostname($r->[1]) ]      if ($r = $R->{cookies}) && ref $r eq 'ARRAY';
    push @rec, [ 'farthest from this site', commas(num $r->[0]) . ' links away', hostname($r->[1]) ] if ($r = $R->{hops}) && ref $r eq 'ARRAY';
    if (@rec) {
        push @b, [ h => 'record holders' ];
        push @b, [ rec => \@rec ];
        push @b, [ note => commas(num $N->{lm_before_web}) . ' pages claimed implausibly old Last-Modified (before the W3 existed, mostly 1970 (epoch fail!))  '
            . 'and ' . commas(num $N->{lm_in_future}) . ' claimed one from the future; neither counts.' ];
    }

    # ---- small print
    push @b, [ h => 'Details' ];
    push @b, [ p => 'lawa obeys robots.txt (its name there is "lawa"), waits at least ten seconds between requests to the '
        . 'same server, and takes at most 25 pages from any one. If it is bothering you, '
        . 'a robots.txt rule is honored within a day, and I read my email robin@dreamstation.systems regularly.' ];
    my ($t0, $t1) = (num $A->{t_first}, num $A->{t_last});
    push @b, [ note => 'Figures cover ' . stamp($t0) . ' to ' . stamp($t1) . ' (' . commas(num $d->{segments})
        . ' data segments); the crawl is constantly running, and the newest ~45 minutes are not in yet.' ] if $t0 && $t1;
    return \@b;
}

# ----------------------------------------------------------------- emitters
sub esc { my ($s) = @_; $s =~ s/&/&amp;/g; $s =~ s/</&lt;/g; $s =~ s/>/&gt;/g; $s =~ s/"/&quot;/g; $s =~ s/'/&#39;/g; return $s }

sub html {
    my ($blocks) = @_;
    my @o = ('<!-- GENERATED every few minutes by lawaPage.timer (documentServing/lawaPage). Do not edit. -->');
    for my $b (@$blocks) {
        my ($type, $v) = @$b;
        if    ($type eq 'h')    { push @o, '', '    <h2>' . esc($v) . '</h2>' }
        elsif ($type eq 'p')    { push @o, '    <p>' . esc($v) . '</p>' }
        elsif ($type eq 'note') { push @o, '    <p><small>' . esc($v) . '</small></p>' }
        elsif ($type eq 'kv') {
            push @o, '    <table>', '      <tbody>';
            push @o, '        <tr><th scope="row">' . esc($_->[0]) . '</th><td>' . esc($_->[1]) . '</td></tr>' for @$v;
            push @o, '      </tbody>', '    </table>';
        }
        elsif ($type eq 'rec') {
            push @o, '    <table>', '      <thead><tr><th scope="col">record</th><th scope="col">value</th><th scope="col">server</th></tr></thead>', '      <tbody>';
            push @o, '        <tr><th scope="row">' . esc($_->[0]) . '</th><td>' . esc($_->[1]) . '</td><td>' . esc($_->[2]) . '</td></tr>' for @$v;
            push @o, '      </tbody>', '    </table>';
        }
        elsif ($type eq 'table') {
            my @head = @{ $v->{head} };
            push @o, '    <table>', '      <thead><tr>' . join('', map { '<th scope="col">' . esc($_) . '</th>' } @head)
                . '<th scope="col" aria-hidden="true"></th></tr></thead>', '      <tbody>';
            my $peak = 0;
            for (@{ $v->{rows} }) { $peak = $_->[2] if defined $_->[2] && $_->[2] > $peak }
            for my $r (@{ $v->{rows} }) {
                my $bar = defined $r->[2] && $peak > 0 ? "\x{2588}" x int(16 * $r->[2] / $peak + 0.5) : '';
                push @o, '        <tr><th scope="row">' . esc($r->[0]) . '</th><td>' . commas($r->[1]) . '</td><td>'
                    . (defined $r->[2] ? sprintf('%.1f%%', 100 * $r->[2]) : '-') . '</td><td aria-hidden="true">' . $bar . '</td></tr>';
            }
            push @o, '      </tbody>', '    </table>';
        }
    }
    return join("\n", @o) . "\n";
}

sub wrap {
    my ($text, $width, $indent) = @_;
    $indent //= '';
    my (@lines, $cur);
    for my $w (split ' ', $text) {
        if (defined $cur && length($cur) + 1 + length($w) > $width) { push @lines, $cur; undef $cur }
        $cur = defined $cur ? "$cur $w" : "$indent$w";
    }
    push @lines, $cur if defined $cur;
    return @lines;
}

# Rows for the two text formats. Never wider than $W.
sub text_table {
    my ($v) = @_;
    my @o;
    my $peak = 0;
    for (@{ $v->{rows} }) { $peak = $_->[2] if defined $_->[2] && $_->[2] > $peak }
    push @o, sprintf('%-34s %10s %6s', substr($v->{head}[0], 0, 34), substr($v->{head}[1], 0, 10), 'share');
    for my $r (@{ $v->{rows} }) {
        my $bar = defined $r->[2] && $peak > 0 ? '#' x int(14 * $r->[2] / $peak + 0.5) : '';
        push @o, sprintf('%-34s %10s %6s %s', substr($r->[0], 0, 34), commas($r->[1]),
            (defined $r->[2] ? sprintf('%.1f%%', 100 * $r->[2]) : '-'), $bar);
    }
    return @o;
}

sub text_kv  { my ($v) = @_; return map { my @w = wrap($_->[1], $W - 27); (sprintf('%-26s %s', $_->[0], shift(@w) // ''), map { (' ' x 27) . $_ } @w) } @$v }
sub text_rec { my ($v) = @_; return map { (sprintf('%-30s %s', $_->[0], $_->[1]), "    $_->[2]") } @$v }

sub gemini {
    my ($blocks) = @_;
    my @o = ('# lawa', '');
    for my $b (@$blocks) {
        my ($type, $v) = @$b;
        $v =~ s/^(?=[#>*]|=>|```)/ /mg unless ref $v;    # no block may start a gemtext line type by accident
        if    ($type eq 'h')     { push @o, "## $v", '' }
        elsif ($type eq 'p')     { push @o, $v, '' }
        elsif ($type eq 'note')  { push @o, "($v)", '' }
        elsif ($type eq 'kv')    { push @o, '```', text_kv($v), '```', '' }
        elsif ($type eq 'rec')   { push @o, '```', text_rec($v), '```', '' }
        elsif ($type eq 'table') { push @o, '```', text_table($v), '```', '' }
    }
    push @o, '=> https://dreamstation.systems/personal/lawa.html the same page on the web', '=> / back to home';
    return join("\n", @o) . "\n";
}

sub gopher {
    my ($blocks) = @_;
    my @o = ('lawa', '====', '');
    for my $b (@$blocks) {
        my ($type, $v) = @$b;
        if    ($type eq 'h')     { push @o, $v, '-' x length($v), '' }
        elsif ($type eq 'p')     { push @o, wrap($v, $W), '' }
        elsif ($type eq 'note')  { push @o, wrap("($v)", $W, '  '), '' }
        elsif ($type eq 'kv')    { push @o, map({ "  $_" } text_kv($v)), '' }
        elsif ($type eq 'rec')   { push @o, map({ "  $_" } text_rec($v)), '' }
        elsif ($type eq 'table') { push @o, text_table($v), '' }
    }
    push @o, 'The same page on the web:', '  https://dreamstation.systems/personal/lawa.html';
    # A gopher text file ends at a line holding a single dot; make sure no data line is one.
    return join("\n", map { $_ eq '.' ? ' .' : $_ } @o) . "\n";
}

# ------------------------------------------------------------------- main
my $render_only = grep { $_ eq '--render-only' } @ARGV;
pull() unless $render_only;
my $d = do {
    my $fh;
    open($fh, '<', $CACHE) ? do { local $/; eval { JSON::PP->new->utf8->decode(scalar <$fh>) } } : undef;
};
unless (ref $d eq 'HASH' && ($d->{schema} // 0) == $SCHEMA && ref $d->{agg} eq 'HASH') {
    warn "lawaPage: nothing to render yet\n";
    exit 0;    # not a failure worth a red unit: the page shows its "no numbers" stub
}
my $blocks = build($d, time);
my %files = ('lawa-data.html' => html($blocks), 'lawa.gmi' => gemini($blocks), 'lawa.txt' => gopher($blocks));
for my $name (sort keys %files) {
    open my $fh, '>:encoding(UTF-8)', "$OUT/$name.tmp" or die "$OUT/$name.tmp: $!\n";
    print {$fh} $files{$name};
    close $fh or die "$OUT/$name.tmp: $!\n";
    rename "$OUT/$name.tmp", "$OUT/$name" or die "$OUT/$name: $!\n";
}
