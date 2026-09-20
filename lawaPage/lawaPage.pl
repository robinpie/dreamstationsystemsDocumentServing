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
#
# LANGUAGES. Every string a visitor reads goes through T() (or L(), for a label
# that has to fit a column of the text copies). The English text IS the key,
# gettext-style, so the code still reads as the page does; the translations are
# msgid/msgstr pairs after __DATA__ at the bottom of this file, and a missing
# or empty msgstr falls back to English rather than printing nothing. Each
# language in there gets its own three files (lawa-data.tok.html, lawa.tok.gmi,
# lawa.tok.txt), which lawaPublish.pl copies beside the English ones and
# content/tok/lawa.tri includes. Values are slotted into {named} placeholders,
# so a translation is free to reorder a sentence; {nbsp} is U+00A0.
#
#   lawaPage.pl --msgids          every msgid in this file, in source order
#   lawaPage.pl --check-strings   per language: msgids with no translation,
#                                 msgstrs whose msgid no longer exists (the
#                                 English was edited), placeholders that do not
#                                 match, and labels too wide for their column.
#                                 Non-zero exit on any of the last three.
# Both are static (they read this file, not the summary) and touch nothing.
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
# The text copies' column widths, which L() labels have to fit.
my ($W_KV, $W_ROW, $W_COUNT, $W_SHARE, $W_REC) = (26, 34, 10, 6, 30);
my @SSH = ('ssh', '-T', '-i', "$HOME/.ssh/id_ed25519", '-o', 'IdentitiesOnly=yes', '-o', 'BatchMode=yes',
           '-o', 'StrictHostKeyChecking=yes', '-o', "UserKnownHostsFile=$HOME/.ssh/known_hosts",
           '-o', 'ConnectTimeout=15', 'lawapull@starport.dreamstation.systems');

# ------------------------------------------------------------ translations
my $LANG = 'en';
my %TR;    # $TR{lang}{msgid} = msgstr, from __DATA__
# Where each language's copies live, for the links the text copies end with.
my %SITE = (
    en  => { web => 'https://dreamstation.systems/personal/lawa.html',     home => '/' },
    tok => { web => 'https://dreamstation.systems/personal/lawa.tok.html', home => '/tok/' },
);

sub T {
    my ($id, %a) = @_;
    my $s = $TR{$LANG}{$id};
    $s = $id unless defined $s && length $s;
    # One pass, so a value can never be re-read as a placeholder.
    $s =~ s/\{(\w+)\}/$1 eq 'nbsp' ? "\x{A0}" : exists $a{$1} ? $a{$1} : "{$1}"/ge;
    return $s;
}
# A label with a column to fit in the Gemini and Gopher copies. The width is
# only read by --check-strings; at run time this is T().
sub L { my ($w, $id, %a) = @_; return T($id, %a) }

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
sub pct { my ($n, $d) = @_; return $d > 0 ? sprintf('%.1f%%', 100 * $n / $d) : '—' }
sub bytes {
    my ($n) = @_;
    for my $u ([ 'TB', 1e12 ], [ 'GB', 1e9 ], [ 'MB', 1e6 ], [ 'kB', 1e3 ]) {
        return sprintf("%.2f\x{A0}%s", $n / $u->[1], $u->[0]) if $n >= $u->[1];
    }
    return T('{n}{nbsp}bytes', n => sprintf('%d', $n));
}
sub span {
    my ($s) = @_;
    return T('{n}{nbsp}years',   n => sprintf('%.1f', $s / 31557600)) if $s >= 2 * 31557600;
    return T('{n}{nbsp}days',    n => sprintf('%.0f', $s / 86400))    if $s >= 3 * 86400;
    return T('{n}{nbsp}hours',   n => sprintf('%.1f', $s / 3600))     if $s >= 2 * 3600;
    return T('{n}{nbsp}minutes', n => sprintf('%.0f', $s / 60))       if $s >= 120;
    return T('{n}{nbsp}seconds', n => sprintf('%.0f', $s));
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
    push @b, [ p => T('lawa is my web crawler. It crawls the web and writes down the HTTP headers that come back from each site. Everything below is regenerated every few minutes from what it has seen so far.') ];
    if ($now - $gen > 5400) {
        push @b, [ p => T('NOTE: these numbers are stale. the last report from the machine lawa runs on is from {when}, so either lawa or the link to it is down right now.', when => stamp($gen)) ];
    }

    # ---- right now
    my $mode = txt($L->{mode}, 12);
    my @paused = map { txt($_, 20) } @{ ref $L->{paused} eq 'ARRAY' ? $L->{paused} : [] };
    my $doing = @paused ? T('paused ({what})', what => join(', ', @paused))
              : $mode eq 'normal' ? T('crawling')
              : $mode eq 'slow'   ? T('crawling slowly (over its monthly bandwidth budget)')
              : $mode eq 'paused' ? T('paused until next month (bandwidth budget spent)') : $mode;
    $doing = T('not running') if $gen - num($L->{t}) > 900;
    push @b, [ h => T('Status') ];
    push @b, [ kv => [
        [ L($W_KV, 'lawa is'),                 $doing ],
        [ L($W_KV, 'pace'),                    T('{n} requests in the last minute', n => commas(num $L->{fetches_last_min})) ],
        [ L($W_KV, 'servers visited'),         T('{done} finished, {active} in progress', done => commas(num $L->{hosts_done}), active => commas(num $L->{active_hosts})) ],
        [ L($W_KV, 'servers waiting in line'), commas(num($L->{backlog_new_domains}) + num($L->{backlog_other})) ],
        [ L($W_KV, 'responses studied below'), T('{responses} from {servers} servers', responses => commas(num $N->{responses}), servers => commas(num $H->{answered})) ],
#       [ 'bandwidth this month',   bytes(num $L->{month_bytes}) . ' of a ' . bytes(num $L->{budget_soft}) . ' budget' ],
        [ L($W_KV, 'numbers as of'),           stamp($gen) ],
    ] ];
    push @b, [ note => T('The shares below are measured by hostname. Additionally, lawa takes at most 25 pages from any one server, and each server is counted once, when lawa has finished with it.') ];

    # ---- software
    my $ans = num $H->{answered};
    push @b, [ h => T('Web servers seen') ];
    push @b, [ table => { head => [ L($W_ROW, 'Server header'), L($W_COUNT, 'servers'), T('share') ],
        rows => [ map { [ txt($_->[0], 30), $_->[1], $ans ? $_->[1] / $ans : undef ] } top($H->{server}, 10) ] } ];
    my $named = $ans - num(tbl($H->{server})->{'(none)'});
    push @b, [ p => T('{pct} of the servers that name themselves also announce their version number.', pct => pct(num $H->{server_version}, $named)) ];
    my @pw = top($H->{powered}, 8);
    if (@pw) {
        my $pw_total = 0; $pw_total += num($_) for values %{ tbl($H->{powered}) };
        push @b, [ table => { head => [ 'X-Powered-By', L($W_COUNT, 'servers'), T('share of those sending it') ],
            rows => [ map { [ txt($_->[0], 30), $_->[1], $pw_total ? $_->[1] / $pw_total : undef ] } @pw ] } ];
    }

    # ---- clocks
    my $K = tbl($H->{clock});
    my $meas = num $K->{measured};
    if ($meas) {
        push @b, [ h => T('Bad time') ];
        push @b, [ p => T('A Date only has one‐second resolution and the network adds delay, so “on time” means “within about {n}{nbsp}seconds”.', n => (num($d->{slack}) || 2)) ];
        my @rows = ([ L($W_ROW, 'on time'), num $K->{ontime} ], [ L($W_ROW, 'up to 10{nbsp}seconds off'), num $K->{b10s} ],
                    [ L($W_ROW, '10{nbsp}seconds to a minute'), num $K->{b1m} ], [ L($W_ROW, 'a minute to an hour'), num $K->{b1h} ],
                    [ L($W_ROW, 'an hour to a day'), num $K->{b1d} ], [ L($W_ROW, 'more than a day'), num $K->{bmore} ]);
        push @b, [ table => { head => [ L($W_ROW, 'server clock'), L($W_COUNT, 'servers'), T('share') ], rows => [ map { [ @$_, $_->[1] / $meas ] } @rows ] } ];
        my $wrong = $meas - num $K->{ontime};
        push @b, [ p => T('Of the {wrong} wrong clocks, {slow} run slow and {fast} run fast. {tz} are wrong by a whole number of hours, which is likely timezone problems rather than drift. {nodate} servers sent no Date at all, and {baddate} sent malformed Dates.',
            wrong => commas($wrong), slow => commas(num $K->{slow}), fast => commas(num $K->{fast}), tz => commas(num $K->{tz_hours}),
            nodate => commas(num $K->{no_date}), baddate => commas(num $K->{bad_date})) ];
        # (the English ends in a space, and always has)
        push @b, [ note => T('Responses served from a cache (indicated by an Age header) are left out. {n} servers only ever answered that way. ', n => commas(num $K->{cached_only})) ];
    }

    # ---- security headers
    push @b, [ h => T('Security headers') ];
    my $F = tbl($H->{flag});
    my $https = num $H->{https};
    push @b, [ table => { head => [ L($W_ROW, 'header'), L($W_COUNT, 'servers'), T('share') ], rows => [
        [ L($W_ROW, 'HSTS (share of HTTPS servers)'), num $H->{hsts_https}, $https ? num($H->{hsts_https}) / $https : undef ],
        map { [ $_->[0], num $F->{ $_->[1] }, $ans ? num($F->{ $_->[1] }) / $ans : undef ] }
            [ 'X-Content-Type-Options', 'xcto' ], [ 'X-Frame-Options', 'xfo' ], [ 'Content-Security-Policy', 'csp' ],
            [ 'Referrer-Policy', 'refpol' ], [ 'Permissions-Policy', 'permpol' ],
            [ L($W_ROW, 'X-XSS-Protection (deprecated)'), 'xxss' ],
    ] } ];
#    push @b, [ p => 'lawa never sends a cookie, so every cookie it is handed is unprompted: '
#        . pct(num $F->{cookie}, $ans) . ' of servers set one anyway within their first few pages.' ];

    # ---- TLS
    my $T = tbl($H->{tls});
    my $tls = num $T->{total};
    if ($tls) {
        push @b, [ h => 'TLS' ];
        push @b, [ p => T('{https} of servers answered over HTTPS at least once. lawa connects even when the certificate is bad, so here’s what was wrong. {broken} of HTTPS servers would have failed in a browser.',
            https => pct($https, $ans), broken => pct(num $T->{broken}, $tls)) ];
        my $V = tbl($T->{verify});
        push @b, [ table => { head => [ L($W_ROW, 'certificate problem'), L($W_COUNT, 'servers'), T('share of HTTPS') ], rows => [
            map { [ $_->[0], $_->[1], $_->[1] / $tls ] }
                [ L($W_ROW, 'wrong hostname'), num $T->{name_bad} ], [ L($W_ROW, 'unknown or incomplete issuer'), num $V->{'unknown issuer'} ],
                [ L($W_ROW, 'expired'), num $V->{expired} ], [ L($W_ROW, 'self‐signed'), num $V->{'self-signed'} ],
        ] } ];
        push @b, [ table => { head => [ L($W_ROW, 'protocol'), L($W_COUNT, 'servers'), T('share of HTTPS') ],
            rows => [ map { [ txt($_->[0], 12), $_->[1], $_->[1] / $tls ] } top($T->{version}, 4) ] } ];
        push @b, [ table => { head => [ L($W_ROW, 'certificate authority'), L($W_COUNT, 'servers'), T('share of HTTPS') ],
            rows => [ map { [ txt($_->[0], 30), $_->[1], $_->[1] / $tls ] } top($H->{issuer}, 8) ] } ];
    }

    # ---- wire quirks
    push @b, [ h => T('Other quirks') ];
    push @b, [ p => T('lawa speaks my handrolled HTTP/1.1 implementation and logs each header block as the raw bytes, so we can see some stuff that HTTP libraries usually clean up.') ];
    my $resp = num $N->{responses};
    push @b, [ table => { head => [ L($W_ROW, 'quirk'), L($W_COUNT, 'servers'), T('share') ], rows => [
        map { [ $_->[0], $_->[1], $ans ? $_->[1] / $ans : undef ] }
            [ L($W_ROW, 'same header sent more than once'),     num $F->{dup} ],
            [ L($W_ROW, 'every header name in lowercase'),      num $H->{names_lower} ],
            [ L($W_ROW, 'answered HTTP/1.1 with HTTP/1.0'),     num $F->{http10} ],
            [ L($W_ROW, 'bare LF line endings (no CR)'),        num $F->{bare_lf} ],
            [ L($W_ROW, 'folded (multi‐line) header values'),   num $F->{obs_fold} ],
    ] } ];
    push @b, [ p => T('The average response carried {lines} header lines in {bytes}{nbsp}bytes. In total, lawa has read {total} of headers.',
        lines => sprintf('%.1f', $resp ? num($N->{hdr_lines}) / $resp : 0), bytes => commas($resp ? num($N->{hdr_bytes}) / $resp : 0),
        total => bytes(num $N->{hdr_bytes})) ] if $resp;

    # ---- status codes and manners
    my $S = tbl($A->{status});
    my $pages = 0; $pages += num($_) for values %$S;
    push @b, [ h => T('Status codes') ];
    push @b, [ table => { head => [ L($W_ROW, 'status'), L($W_COUNT, 'responses'), T('share') ],
        rows => [ map { [ txt($_->[0], 3), $_->[1], $pages ? $_->[1] / $pages : undef ] } top($S, 8) ] } ];
    my $RS = tbl($A->{robots_status});
    my $SK = tbl($A->{skip});
    my $FN = tbl($A->{finish});
    push @b, [ p => T('{teapot} responses were 418 I\'m a teapot, and {legal} were 451 Unavailable For Legal Reasons. lawa asked for {robots} robots.txt files and, because of what they said, left {skipped} pages alone. it walked away from {pushback} servers entirely because of 429, 503, or repeated 403s, and {dns} linked‐to servers turned out not to exist any more.',
        teapot => commas(num $S->{418}), legal => commas(num $S->{451}), robots => commas(num $N->{robots}),
        skipped => commas(num $SK->{robots}), pushback => commas(num $FN->{pushback}), dns => commas(num $FN->{dns})) ];

    # ---- geography
    if (num $d->{geo}) {
        my $geo_total = 0; $geo_total += num($_) for values %{ tbl($H->{asn}) };
        push @b, [ h => T('Where the W3 is from') ];
        push @b, [ table => { head => [ L($W_ROW, 'network'), L($W_COUNT, 'servers'), T('share') ],
            rows => [ map { [ txt($_->[0], 34), $_->[1], $geo_total ? $_->[1] / $geo_total : undef ] } top($H->{asn}, 10) ] } ];
        my $cc_total = 0; $cc_total += num($_) for values %{ tbl($H->{country}) };
        push @b, [ table => { head => [ L($W_ROW, 'country'), L($W_COUNT, 'servers'), T('share') ],
            rows => [ map { [ txt($_->[0], 30), $_->[1], $cc_total ? $_->[1] / $cc_total : undef ] } top($H->{country}, 10) ] } ];
        push @b, [ note => T('Countries leaves out the {n} servers behind Cloudflare and Fastly, because an anycast address is in every country at once. IP geolocation by DB-IP.', n => commas(num $H->{country_anycast})) ];
    }
    my $tld_total = 0; $tld_total += num($_) for values %{ tbl($H->{tld}) };
    push @b, [ table => { head => [ L($W_ROW, 'top‐level domain'), L($W_COUNT, 'servers'), T('share') ],
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
    push @b, [ h => T('Non‐standard headers') ];
    push @b, [ table => { head => [ L($W_ROW, 'header'), L($W_COUNT, 'servers'), T('share') ],
        rows => [ map { [ txt($_->[0], 34), $_->[1], $ans ? $_->[1] / $ans : undef ] } top($H->{hdr_names}, 12, \%standard) ] } ];
    my $C = tbl($H->{clacks});
    my $clacks = 0; $clacks += num($_) for values %$C;
    if ($clacks) {
        push @b, [ p => T('And of course, X-Clacks-Overhead. {n} servers send it:', n => commas($clacks)) ];
        push @b, [ table => { head => [ 'X-Clacks-Overhead', L($W_COUNT, 'servers'), T('share') ],
            rows => [ map { [ txt($_->[0], 40), $_->[1], $_->[1] / $clacks ] } top($C, 5) ] } ];
    }

    # ---- record holders
    my @rec;
    my $r;
    push @rec, [ L($W_REC, 'slowest clock'), T('{span} behind', span => span(num $r->[0])), hostname($r->[1]) ] if ($r = $R->{slow_clock}) && ref $r eq 'ARRAY';
    push @rec, [ L($W_REC, 'fastest clock'), T('{span} ahead', span => span(num $r->[0])), hostname($r->[1]) ]  if ($r = $R->{fast_clock}) && ref $r eq 'ARRAY';
    push @rec, [ L($W_REC, 'oldest Last-Modified'), strftime('%Y-%m-%d', gmtime num $r->[0]), hostname($r->[1]) ]
        if ($r = $R->{oldest_lm}) && ref $r eq 'ARRAY';
    push @rec, [ L($W_REC, 'biggest header block'), T('{n}{nbsp}bytes', n => commas(num $r->[0])), hostname($r->[1]) ]   if ($r = $R->{hdr_bytes}) && ref $r eq 'ARRAY';
    push @rec, [ L($W_REC, 'most header lines'), commas(num $r->[0]), hostname($r->[1]) ]                 if ($r = $R->{hdr_lines}) && ref $r eq 'ARRAY';
    push @rec, [ L($W_REC, 'most cookies in one response'), commas(num $r->[0]), hostname($r->[1]) ]      if ($r = $R->{cookies}) && ref $r eq 'ARRAY';
    push @rec, [ L($W_REC, 'farthest from this site'), T('{n} links away', n => commas(num $r->[0])), hostname($r->[1]) ] if ($r = $R->{hops}) && ref $r eq 'ARRAY';
    if (@rec) {
        push @b, [ h => T('record holders') ];
        push @b, [ rec => \@rec ];
        push @b, [ note => T('{old} pages claimed implausibly old Last-Modified (before the W3 existed, mostly 1970 (epoch fail!)) and {future} claimed one from the future; neither counts.',
            old => commas(num $N->{lm_before_web}), future => commas(num $N->{lm_in_future})) ];
    }

    # ---- small print
    push @b, [ h => T('Details') ];
    push @b, [ p => T('lawa obeys robots.txt (its name there is “lawa”), waits at least ten seconds between requests to the same server, and takes at most 25 pages from any one. If it is bothering you, a robots.txt rule is honored within a day, and I read my email robin@dreamstation.systems regularly.') ];
    my ($t0, $t1) = (num $A->{t_first}, num $A->{t_last});
    push @b, [ note => T('Figures cover {from} to {to} ({segments} data segments); the crawl is constantly running, and the newest ~45{nbsp}minutes are not in yet.',
        from => stamp($t0), to => stamp($t1), segments => commas(num $d->{segments})) ] if $t0 && $t1;
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
            push @o, '    <table>', '      <thead><tr><th scope="col">' . esc(T('record')) . '</th><th scope="col">' . esc(T('value')) . '</th><th scope="col">' . esc(T('server')) . '</th></tr></thead>', '      <tbody>';
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
                    . (defined $r->[2] ? sprintf('%.1f%%', 100 * $r->[2]) : '—') . '</td><td aria-hidden="true">' . $bar . '</td></tr>';
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
    for my $w (grep { length } split /[ \t\n]+/, $text) {    # not split ' ': that also breaks at U+00A0
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
    push @o, sprintf('%-34s %10s %6s', substr($v->{head}[0], 0, 34), substr($v->{head}[1], 0, 10), L($W_SHARE, 'share'));
    for my $r (@{ $v->{rows} }) {
        my $bar = defined $r->[2] && $peak > 0 ? '#' x int(14 * $r->[2] / $peak + 0.5) : '';
        push @o, sprintf('%-34s %10s %6s %s', substr($r->[0], 0, 34), commas($r->[1]),
            (defined $r->[2] ? sprintf('%.1f%%', 100 * $r->[2]) : '—'), $bar);
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
    push @o, "=> $SITE{$LANG}{web} " . T('the same page on the web'), "=> $SITE{$LANG}{home} " . T('back to home');
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
    push @o, T('The same page on the web:'), "  $SITE{$LANG}{web}";
    # A gopher text file ends at a line holding a single dot; make sure no data line is one.
    return join("\n", map { $_ eq '.' ? ' .' : $_ } @o) . "\n";
}

# ------------------------------------------------------------------- main
binmode DATA, ':encoding(UTF-8)';
{
    my ($lang, $id);
    while (my $l = <DATA>) {
        chomp $l;
        if    ($l =~ /^\[(\w+)\]\s*$/)      { $lang = $1; $TR{$lang} //= {}; undef $id }
        elsif ($l =~ /^msgid (.*)$/)        { $id = $1 }
        elsif ($l =~ /^msgstr ?(.*)$/ && defined $lang && defined $id) { $TR{$lang}{$id} = $1; undef $id }
    }
}

if (grep { $_ eq '--msgids' || $_ eq '--check-strings' } @ARGV) {
    binmode STDOUT, ':encoding(UTF-8)';
    open my $me, '<:encoding(UTF-8)', $0 or die "$0: $!\n";
    my $src = do { local $/; <$me> };
    $src =~ s/^__DATA__\n.*\z//ms;
    my %wvar = (W_KV => $W_KV, W_ROW => $W_ROW, W_COUNT => $W_COUNT, W_SHARE => $W_SHARE, W_REC => $W_REC);
    my (@ids, %width, %seen);
    while ($src =~ /\b(?:T\(\s*|L\(\s*\$(W_\w+)\s*,\s*)'((?:[^'\\]|\\.)*)'/g) {
        my ($w, $id) = ($1, $2);
        $id =~ s/\\(['\\])/$1/g;
        $width{$id} = $wvar{$w} if defined $w && (!defined $width{$id} || $wvar{$w} < $width{$id});
        push @ids, $id unless $seen{$id}++;
    }
    if (grep { $_ eq '--msgids' } @ARGV) {
        print "msgid $_\nmsgstr \n\n" for @ids;
        exit 0;
    }
    my $bad = 0;
    my $ph = sub { join ' ', sort grep { $_ ne 'nbsp' } $_[0] =~ /\{(\w+)\}/g };
    for my $lang (sort keys %TR) {
        my @missing = grep { !length($TR{$lang}{$_} // '') } @ids;
        print "[$lang] ", scalar(@ids) - @missing, " of ", scalar(@ids), " strings translated\n";
        print "  untranslated (falls back to English): $_\n" for @missing;
        for my $id (sort keys %{ $TR{$lang} }) {
            my $s = $TR{$lang}{$id};
            unless ($seen{$id}) { print "  ORPHAN, its English no longer exists: $id\n"; $bad = 1; next }
            next unless length $s;
            if ($ph->($id) ne $ph->($s)) { print "  PLACEHOLDERS differ: $id\n      -> $s\n"; $bad = 1 }
            (my $flat = $s) =~ s/\{nbsp\}/ /g;
            if ($width{$id} && length($flat) > $width{$id}) {
                printf "  TOO WIDE (%d > %d columns): %s\n      -> %s\n", length($flat), $width{$id}, $id, $s;
                $bad = 1;
            }
        }
    }
    exit $bad;
}

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
my $now = time;
my %files;
for my $lang ('en', grep { $_ ne 'en' } sort keys %TR) {
    $LANG = $lang;
    my $blocks = build($d, $now);
    my $sfx = $lang eq 'en' ? '' : ".$lang";    # lawa-data.tok.html, lawa.tok.gmi, lawa.tok.txt
    $files{"lawa-data$sfx.html"} = html($blocks);
    $files{"lawa$sfx.gmi"}       = gemini($blocks);
    $files{"lawa$sfx.txt"}       = gopher($blocks);
}
for my $name (sort keys %files) {
    open my $fh, '>:encoding(UTF-8)', "$OUT/$name.tmp" or die "$OUT/$name.tmp: $!\n";
    print {$fh} $files{$name};
    close $fh or die "$OUT/$name.tmp: $!\n";
    rename "$OUT/$name.tmp", "$OUT/$name" or die "$OUT/$name: $!\n";
}

__DATA__
# Translations: [language], then msgid/msgstr pairs. The msgid is the English
# string exactly as it appears in T()/L() above; `lawaPage.pl --msgids` prints
# them all, and `--check-strings` says what is missing, stale, mismatched or too
# wide. Keep every {placeholder} (order is yours to choose); {nbsp} is a
# no-break space. An empty msgstr means "use the English".
#
# Column limits for the Gemini/Gopher copies (L() in the code; --check-strings
# enforces them): key/value labels 26, table row labels and first headings 34,
# the count heading 10, "share" 6, record-holder labels 30.

[tok]
msgid {n}{nbsp}bytes
msgstr {n}{nbsp}B

msgid {n}{nbsp}years
msgstr tenpo sike{nbsp}{n}

msgid {n}{nbsp}days
msgstr tenpo suno{nbsp}{n}

msgid {n}{nbsp}hours
msgstr {n}{nbsp}h

msgid {n}{nbsp}minutes
msgstr {n}{nbsp}min

msgid {n}{nbsp}seconds
msgstr {n}{nbsp}s

msgid lawa is my web crawler. It crawls the web and writes down the HTTP headers that come back from each site. Everything below is regenerated every few minutes from what it has seen so far.
msgstr ilo lawa li ilo alasa mi. ona li alasa lon linluwi W3 li sitelen e nimi sewi HTTP tan kulupu lipu ale. ijo ale lon anpa li tan lukin ona tawa tenpo ni. tenpo lili ale la ilo li pali sin e ijo ni.

msgid NOTE: these numbers are stale. the last report from the machine lawa runs on is from {when}, so either lawa or the link to it is down right now.
msgstr o sona: nanpa ni li sin ala. ilo lawa li lon ilo sona ante. tenpo {when} la ilo sona ni li toki tawa mi. ni li toki pini ona. ken la ilo lawa li pali ala lon tenpo ni. ken la linja tawa ona li pakala.

msgid paused ({what})
msgstr lape ({what})

msgid crawling
msgstr alasa

msgid crawling slowly (over its monthly bandwidth budget)
msgstr alasa lili (pali linluwi pi tenpo mun ni li suli tawa mute ken)

msgid paused until next month (bandwidth budget spent)
msgstr lape tawa tenpo mun kama (mute ken pi pali linluwi li pini)

msgid not running
msgstr pali ala

msgid Status
msgstr pilin ilo

msgid lawa is
msgstr ilo lawa li

msgid pace
msgstr wawa tawa

msgid {n} requests in the last minute
msgstr wile {n} lon 1{nbsp}min pini

msgid servers visited
msgstr ilo pana pi alasa ona

msgid {done} finished, {active} in progress
msgstr {done} li pini. {active} li lon pali

msgid servers waiting in line
msgstr ilo pana lon linja awen

msgid responses studied below
msgstr pana pi nanpa anpa

msgid {responses} from {servers} servers
msgstr {responses} tan ilo pana {servers}

msgid numbers as of
msgstr tenpo pi nanpa ni

msgid The shares below are measured by hostname. Additionally, lawa takes at most 25 pages from any one server, and each server is counted once, when lawa has finished with it.
msgstr kipisi anpa la nimi ilo wan li ilo pana wan. kin la ilo lawa li kama jo e lipu 25 anu lili taso tan ilo pana wan. mi nanpa e ilo pana ale lon tenpo wan taso: ilo lawa li pini lon ona la mi nanpa e ona.

msgid Web servers seen
msgstr ilo pana W3 pi kama lukin

msgid Server header
msgstr nimi sewi Server

msgid servers
msgstr ilo pana

msgid share
msgstr kipisi

msgid {pct} of the servers that name themselves also announce their version number.
msgstr ilo pana pi toki nimi la {pct} li toki kin e nanpa ona (Version).

msgid share of those sending it
msgstr kipisi lon ilo pana pi toki ni

msgid Bad time
msgstr tenpo ike

msgid A Date only has one‐second resolution and the network adds delay, so “on time” means “within about {n}{nbsp}seconds”.
msgstr nimi sewi Date li toki ala e kipisi lili pi 1{nbsp}s. linluwi kin li pana e tenpo awen. tan ni la “tenpo pona” li ni: ante li ~{n}{nbsp}s anu lili.

msgid on time
msgstr tenpo pona

msgid up to 10{nbsp}seconds off
msgstr ante li lili tawa 10{nbsp}s

msgid 10{nbsp}seconds to a minute
msgstr tan 10{nbsp}s tawa 1{nbsp}min

msgid a minute to an hour
msgstr tan 1{nbsp}min tawa 1{nbsp}h

msgid an hour to a day
msgstr tan 1{nbsp}h tawa tenpo suno{nbsp}1

msgid more than a day
msgstr ante li suli tawa tenpo suno{nbsp}1

msgid server clock
msgstr ilo tenpo pi ilo pana

msgid Of the {wrong} wrong clocks, {slow} run slow and {fast} run fast. {tz} are wrong by a whole number of hours, which is likely timezone problems rather than drift. {nodate} servers sent no Date at all, and {baddate} sent malformed Dates.
msgstr ilo tenpo {wrong} li pakala. ona la {slow} li lon tenpo pini. {fast} li lon tenpo kama. ilo tenpo {tz} la ante li 1{nbsp}h anu 2{nbsp}h anu sama: kipisi li lon ala. ken suli la ni li tan pakala pi tenpo ma (Timezone). ken lili la ni li tan ni: ilo tenpo li tawa weka lili. ilo pana {nodate} li pana ala e nimi sewi Date. ilo pana {baddate} li pana e nimi sewi Date pakala.

msgid Responses served from a cache (indicated by an Age header) are left out. {n} servers only ever answered that way. 
msgstr pana li tan poki awen (Cache) la mi nanpa ala e ona (nimi sewi Age li lon la pana li tan poki ni). ilo pana {n} li pana kepeken nasin ni taso.

msgid Security headers
msgstr nimi sewi pi nasin awen

msgid header
msgstr nimi sewi

msgid HSTS (share of HTTPS servers)
msgstr HSTS (kipisi pi ilo pana HTTPS)

msgid X-XSS-Protection (deprecated)
msgstr X-XSS-Protection (o kepeken ala)

msgid {https} of servers answered over HTTPS at least once. lawa connects even when the certificate is bad, so here’s what was wrong. {broken} of HTTPS servers would have failed in a browser.
msgstr ilo pana ale la {https} li pana kepeken nasin HTTPS lon tenpo wan anu mute. lipu awen li ike la ilo lawa li open kin e linja. tan ni la mi ken toki e ike ona. ilo pana HTTPS la {broken} li pakala lon ilo pi lukin lipu.

msgid certificate problem
msgstr ike pi lipu awen

msgid share of HTTPS
msgstr kipisi pi ilo pana HTTPS

msgid wrong hostname
msgstr nimi ilo li ante

msgid unknown or incomplete issuer
msgstr kulupu pana pi sona ala anu weka

msgid expired
msgstr tenpo ona li pini

msgid self‐signed
msgstr kulupu pana li ona sama

msgid protocol
msgstr nasin toki

msgid certificate authority
msgstr kulupu pana pi lipu awen

msgid Other quirks
msgstr nasa ante

msgid lawa speaks my handrolled HTTP/1.1 implementation and logs each header block as the raw bytes, so we can see some stuff that HTTP libraries usually clean up.
msgstr ilo lawa li toki kepeken nasin HTTP/1.1. mi taso li pali e ilo toki ni. ona li sitelen e kulupu ale pi nimi sewi lon lipu sona. ona li ante ala e sitelen wan. tan ni la mi mute li ken lukin e nasa ni: tenpo mute la ilo HTTP ante li pona e ona.

msgid quirk
msgstr nasa

msgid same header sent more than once
msgstr nimi sewi wan li lon tenpo mute

msgid every header name in lowercase
msgstr nimi sewi ale li sitelen lili

msgid answered HTTP/1.1 with HTTP/1.0
msgstr wile HTTP/1.1 la pana HTTP/1.0

msgid bare LF line endings (no CR)
msgstr pini linja li LF taso (CR ala)

msgid folded (multi‐line) header values
msgstr nimi sewi wan li lon linja mute

msgid The average response carried {lines} header lines in {bytes}{nbsp}bytes. In total, lawa has read {total} of headers.
msgstr pana meso la nimi sewi li jo e linja {lines}. suli ona li {bytes}{nbsp}B. ale la ilo lawa li lukin e nimi sewi pi suli {total}.

msgid Status codes
msgstr nanpa pana

msgid status
msgstr nanpa pana

msgid responses
msgstr pana

msgid {teapot} responses were 418 I'm a teapot, and {legal} were 451 Unavailable For Legal Reasons. lawa asked for {robots} robots.txt files and, because of what they said, left {skipped} pages alone. it walked away from {pushback} servers entirely because of 429, 503, or repeated 403s, and {dns} linked‐to servers turned out not to exist any more.
msgstr pana {teapot} li “418 I'm a teapot”. pana {legal} li “451 Unavailable For Legal Reasons”. ilo lawa li wile e lipu robots.txt {robots}. tan toki pi lipu ni la ona li wile ala e lipu {skipped}. ilo pana {pushback} li pana e nanpa 429 anu nanpa 503, anu nanpa 403 lon tenpo mute. tan ni la ilo lawa li tawa weka tan ilo pana ni li pini e pali ale lon ona. nimi tawa li pana e ilo lawa tawa ilo pana {dns}. taso ilo pana ni li awen lon ala.

msgid Where the W3 is from
msgstr linluwi W3 li tan seme?

msgid network
msgstr linluwi

msgid country
msgstr ma

msgid Countries leaves out the {n} servers behind Cloudflare and Fastly, because an anycast address is in every country at once. IP geolocation by DB-IP.
msgstr ilo pana {n} li lon monsi pi kulupu Cloudflare anu kulupu Fastly. nanpa ma li jo ala e ona. tan ni: nanpa IP pi nasin Anycast li lon ma ale lon tenpo sama. kulupu DB-IP li pana e sona ma pi nanpa IP.

msgid top‐level domain
msgstr pini pi nimi ilo (TLD)

msgid Non‐standard headers
msgstr nimi sewi pi lipu nasin ala

msgid And of course, X-Clacks-Overhead. {n} servers send it:
msgstr nimi sewi X-Clacks-Overhead kin li lon. ni li nasa ala a. ilo pana {n} li pana e ona:

msgid slowest clock
msgstr ilo tenpo pi tenpo pini suli

msgid {span} behind
msgstr {span} lon tenpo pini

msgid fastest clock
msgstr ilo tenpo pi tenpo kama suli

msgid {span} ahead
msgstr {span} lon tenpo kama

msgid oldest Last-Modified
msgstr Last-Modified pi lili nanpa 1

msgid biggest header block
msgstr nimi sewi ale pi suli nanpa 1

msgid most header lines
msgstr nimi sewi pi mute nanpa 1

msgid most cookies in one response
msgstr Set-Cookie mute lon pana wan

msgid farthest from this site
msgstr weka nanpa 1 tan lipu mi

msgid {n} links away
msgstr weka pi nimi tawa {n}

msgid record holders
msgstr ilo pana pi nanpa wan

msgid {old} pages claimed implausibly old Last-Modified (before the W3 existed, mostly 1970 (epoch fail!)) and {future} claimed one from the future; neither counts.
msgstr lipu {old} la nimi sewi Last-Modified li toki e tenpo pini pi ken lili (tenpo ona la linluwi W3 li lon ala. mute la ni li tenpo sike 1970 (pakala Epoch a!)). lipu {future} la ona li toki e tenpo kama. mi nanpa ala e ni tu.

msgid Details
msgstr sona namako

msgid lawa obeys robots.txt (its name there is “lawa”), waits at least ten seconds between requests to the same server, and takes at most 25 pages from any one. If it is bothering you, a robots.txt rule is honored within a day, and I read my email robin@dreamstation.systems regularly.
msgstr ilo lawa li kute e lipu robots.txt (lipu ni la nimi ona li “lawa”). ona li pana e wile tawa ilo pana la ona li awen. 10{nbsp}s anu mute li pini la ona li ken pana e wile sin tawa ilo pana sama. ilo pana wan la ona li kama jo e lipu 25 anu lili taso. ilo lawa li ike tawa sina la sina ken sitelen e lawa lon lipu robots.txt. tenpo suno{nbsp}1 li pini ala la ilo lawa li kute e lawa ni. kin la mi lukin e lipu linluwi mi lon tenpo mute. nimi ona li robin@dreamstation.systems.

msgid Figures cover {from} to {to} ({segments} data segments); the crawl is constantly running, and the newest ~45{nbsp}minutes are not in yet.
msgstr nanpa ni li tan tenpo {from} tawa tenpo {to} (poki sona {segments}). ilo lawa li alasa lon tenpo ale. sona pi ~45{nbsp}min pini li awen weka.

msgid record
msgstr ijo

msgid value
msgstr nanpa

msgid server
msgstr ilo pana

msgid the same page on the web
msgstr lipu sama lon linluwi W3

msgid back to home
msgstr tawa lipu open

msgid The same page on the web:
msgstr lipu sama lon linluwi W3:

