#!/usr/bin/perl
# pre-commit: refresh the NTP unique-client sentence on staged HTML.
#
# rootdomain/professional/index.html carries a hand-written line:
#
#     Around 123 million unique client IP addresses seen, or about one in
#     every 30 routable IPv4 addresses.
#
# Both figures drift upward as the pool sends more clients our way. This
# hook rewrites them from the live analytics page ntpstatsgen writes every
# five minutes, so the sentence tracks reality without being hand-edited.
#
# SOURCE: /srv/http/ntpstats.txt (override with $NTP_STATS_FILE). That file
# is a generated artifact -- gitignored, server-only -- so away from the VPS
# it will not exist: the hook then leaves the line untouched and the commit
# proceeds. A stale count is "merely generous, not a false claim"; same
# spirit as the font-subset step in githooks.txt.
#
# Resolution is whole millions for the count ("Around N million") and the
# integer the stats page already rounds to for the ratio ("one in every N").
# A commit that does not move either number produces no diff on the line, so
# unrelated commits are not dragged into touching the page -- but note the
# refresh only rides along on a commit that is ALREADY staging index.html,
# exactly like datestampHook.pl. It is not a substitute for editing the
# page; it keeps the page honest when you do.
#
# Test mode: pass file paths as arguments to rewrite them in place, with no
# git involvement and no re-staging.  ./ntpStatHook.pl some/page.html

use strict;
use warnings;
use JSON::PP qw(decode_json);

my $STATS = $ENV{NTP_STATS_FILE} || '/srv/http/ntpstats.txt';
my $test  = @ARGV ? 1 : 0;

# The sentence, with both numbers captured. Kept deliberately specific so a
# reword of the line makes the hook fall silent rather than mangle prose.
my $RE = qr{
    (Around\s+)          (?<count> [\d,]+ )   (\s+million\ unique\ client\ IP
    \ addresses\ seen,\ or\ about\ one\ in\ every\s+)
                         (?<ratio> \d+ )      (\s+routable\ IPv4\ addresses)
}x;

sub slurp { open my $fh, '<:raw', $_[0] or return undef; local $/; <$fh> }

sub jsonld_ok {                      # every JSON-LD block must still parse
    my ($html) = @_;
    while ($html =~ m{<script[^>]*type="application/ld\+json"[^>]*>(.*?)</script>}gs) {
        eval { decode_json($1); 1 } or return 0;
    }
    return 1;
}

# Pull the two figures out of the analytics page. Returns (millions, ratio)
# or the empty list if the file is absent or does not parse as expected.
sub read_stats {
    my $txt = slurp($STATS);
    return () unless defined $txt;

    my ($raw)   = $txt =~ /unique IPs ever seen\s+([\d,]+)/;
    my ($ratio) = $txt =~ /1 in every\s+(\d+)\s+routable IPv4 addresses/;
    return () unless defined $raw && defined $ratio;

    (my $digits = $raw) =~ tr/0-9//cd;
    return () unless length $digits;
    my $millions = int($digits / 1_000_000 + 0.5);
    return () unless $millions > 0 && $ratio > 0;

    return ($millions, $ratio);
}

sub rewrite {
    my ($html, $millions, $ratio) = @_;
    return undef unless $html =~ $RE;
    return undef if $+{count} eq $millions && $+{ratio} eq $ratio;
    $html =~ s/$RE/$1$millions$3$ratio$5/;
    return jsonld_ok($html) ? $html : '';        # '' signals broken output
}

my @stats = read_stats();
if (!@stats) {
    warn "pre-commit: $STATS unreadable or unrecognised; NTP client line left as-is\n"
        unless $test;
    exit 0;
}

my @files;
if ($test) {
    @files = @ARGV;
} else {
    my $staged = `git diff --cached --name-only --diff-filter=ACM -z`;
    @files = grep { /\.html\z/ } split /\0/, $staged;
}

my $failed = 0;
for my $f (@files) {
    my $html = slurp($f) // next;
    next unless $html =~ $RE;

    # Don't silently sweep unstaged edits into the commit (see datestampHook).
    if (!$test && length `git diff --name-only -- "$f"`) {
        warn "pre-commit: $f has unstaged changes; NTP client line not refreshed\n";
        next;
    }

    my $out = rewrite($html, @stats);
    next unless defined $out;                     # line already current
    if ($out eq '') {
        warn "pre-commit: refreshing $f would break its JSON-LD; left unchanged\n";
        $failed = 1;
        next;
    }
    open my $fh, '>:raw', $f or do { warn "pre-commit: cannot write $f: $!\n"; $failed = 1; next };
    print {$fh} $out;
    close $fh;
    system('git', 'add', '--', $f) == 0 or $failed = 1 unless $test;
    print "pre-commit: NTP client line -> $stats[0]M, 1 in $stats[1] in $f\n";
}
exit($failed ? 1 : 0);
