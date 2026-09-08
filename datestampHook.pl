#!/usr/bin/perl
# pre-commit: stamp schema.org dateModified on the WebSite node of staged HTML.
#
# Rewrites "dateModified" inside the JSON-LD node whose @id is $ANCHOR, to
# today's date, then re-stages the file. Date-only (not a full timestamp) so
# repeated commits on the same day produce no diff.
#
# Test mode: pass file paths as arguments to stamp them directly, with no git
# involvement and no re-staging.  ./datestampHook.pl some/page.html
use strict;
use warnings;
use POSIX qw(strftime);
use JSON::PP qw(decode_json);

my $ANCHOR = '"@id": "https://dreamstation.systems/#website"';
my $TYPE   = '"@type": "WebSite"';
my $today  = strftime('%Y-%m-%d', localtime);
my $test   = @ARGV ? 1 : 0;

sub slurp { open my $fh, '<:raw', $_[0] or return undef; local $/; <$fh> }

sub jsonld_ok {                      # every JSON-LD block must still parse
    my ($html) = @_;
    while ($html =~ m{<script[^>]*type="application/ld\+json"[^>]*>(.*?)</script>}gs) {
        eval { decode_json($1); 1 } or return 0;
    }
    return 1;
}

sub stamp {
    my ($html) = @_;
    # Anchor on the node's own @type, not the site @id: that @id also appears
    # as an isPartOf reference in other nodes, which would match first.
    my $pos = index($html, $TYPE);
    return undef if $pos < 0;                       # no WebSite node here

    # Walk forward to the closing brace of the object holding the anchor.
    my ($depth, $i, $end) = (1, $pos, -1);
    while ($i < length $html) {
        my $c = substr($html, $i, 1);
        if    ($c eq '{') { $depth++ }
        elsif ($c eq '}') { $depth--; if (!$depth) { $end = $i; last } }
        $i++;
    }
    return undef if $end < 0;                       # unbalanced; leave alone

    my $region = substr($html, $pos, $end - $pos);
    return undef unless index($region, $ANCHOR) >= 0;   # some other WebSite
    if ($region =~ /"dateModified"\s*:\s*"([^"]*)"/) {
        return undef if $1 eq $today;               # already current
        $region =~ s/("dateModified"\s*:\s*")[^"]*(")/$1$today$2/;
    } else {
        # Insert after the @id line, matching its indentation. If that line had
        # no trailing comma it was the last property, so the comma moves to it.
        $region =~ s/^([ \t]*)(\Q$ANCHOR\E)(,?)[ \t]*(\r?\n)/
                     $1 . $2 . "," . $4 . $1 . "\"dateModified\": \"$today\"" .
                     ($3 ? "," : "") . $4/me or return undef;
    }
    substr($html, $pos, $end - $pos) = $region;
    return jsonld_ok($html) ? $html : '';           # '' signals broken output
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
    next unless index($html, $ANCHOR) >= 0;

    # Don't silently sweep unstaged edits into the commit.
    if (!$test && length `git diff --name-only -- "$f"`) {
        warn "pre-commit: $f has unstaged changes; dateModified not stamped\n";
        next;
    }

    my $out = stamp($html);
    next unless defined $out;
    if ($out eq '') {
        warn "pre-commit: stamping $f would break its JSON-LD; left unchanged\n";
        $failed = 1;
        next;
    }
    open my $fh, '>:raw', $f or do { warn "pre-commit: cannot write $f: $!\n"; $failed = 1; next };
    print {$fh} $out;
    close $fh;
    system('git', 'add', '--', $f) == 0 or $failed = 1 unless $test;
    print "pre-commit: dateModified -> $today in $f\n";
}
exit($failed ? 1 : 0);
