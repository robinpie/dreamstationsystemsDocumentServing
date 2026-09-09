#!/usr/bin/perl
# Build the 88x31 button wall: re-encode the badges, then generate the markup.
#
#     badgeBuild.pl            build badges/ and rewrite the marked pages
#     badgeBuild.pl --check    exit 1 if anything is stale, write nothing
#     badgeBuild.pl --force    re-encode everything, ignoring the manifest
#
# Run from preCommit.sh, not by hand. Output is a committed artifact, like
# feed.xml and the DejaVu subsets: the deploy is a plain rsync of rootdomain/
# with no build step, so anything served has to already exist in the repo.
#
#     webBadges.csv           <- source of truth: order, alt text, links
#     assetsBuild/badgesSrc/  <- source images, NOT under rootdomain/
#     rootdomain/personal/badges/          <- generated, served
#     assetsBuild/badgeManifest.txt        <- generated, the encode cache
#
# Each source image is re-encoded to lossless WebP and kept only if it came out
# smaller; otherwise the original is copied through, so the served extension is
# not known until the encoder runs and the <li> markup has to be generated too.
# badgeManifest.txt is the committed encode cache (source SHA-256 + winning
# format) that keeps a no-image commit cheap. Full rationale — the per-image
# size comparison, GIF via gif2webp, why mtimes are ignored — in siteAssets.txt,
# THE 88x31 WALL.

use strict;
use warnings;
use Digest::SHA qw(sha256_hex);
use File::Copy qw(copy);
use File::Temp qw(tempfile);
use File::Basename qw(basename);

my $CSV      = 'webBadges.csv';
my $SRC_DIR  = 'assetsBuild/badgesSrc';
my $OUT_DIR  = 'rootdomain/personal/badges';
my $MANIFEST = 'assetsBuild/badgeManifest.txt';
my $PAGE_DIR = 'rootdomain/personal';
my $WEB_PATH = 'badges';          # $OUT_DIR as the marked pages address it

my $MARK_START = '<!-- badges:start';
my $MARK_END   = '<!-- badges:end -->';

my ($check, $force) = (0, 0);
for (@ARGV) {
    if    ($_ eq '--check') { $check = 1 }
    elsif ($_ eq '--force') { $force = 1 }
    else  { die "badgeBuild: unknown argument '$_'\n" }
}
die "badgeBuild: --check and --force are contradictory\n" if $check && $force;

# Repo root, for the same reason preCommit.sh does it: this runs from a hook
# whose cwd is not guaranteed.
chomp(my $root = `git rev-parse --show-toplevel 2>/dev/null`);
die "badgeBuild: not in a git work tree\n" if !$root || $?;
chdir $root or die "badgeBuild: chdir $root: $!\n";

my $stale = 0;                    # --check accumulator
sub note_stale { $stale = 1; print STDERR "badgeBuild: STALE: $_[0]\n" }

# ---------------------------------------------------------------- CSV parsing
#
# RFC 4180 by hand rather than Text::CSV, which is not installed here and is not
# worth a dependency for three columns. Fields may be quoted, quoted fields may
# contain commas, CRLF and doubled "" quotes. The whole file is consumed at once
# so a quoted field containing a line break cannot split a record.
sub parse_csv {
    my ($text) = @_;
    my (@rows, @field, $cur, $quoted, $started);
    ($cur, $quoted, $started) = ('', 0, 0);
    my @c = split //, $text;

    for (my $i = 0; $i <= $#c; $i++) {
        my $ch = $c[$i];
        if ($quoted) {
            if ($ch eq '"') {
                if (defined $c[$i+1] && $c[$i+1] eq '"') { $cur .= '"'; $i++ }
                else                                     { $quoted = 0 }
            }
            else { $cur .= $ch }
            next;
        }
        if ($ch eq '"' && !$started) { $quoted = 1; $started = 1; next }
        if ($ch eq ',')  { push @field, $cur; ($cur,$started) = ('',0); next }
        if ($ch eq "\r") { next }               # tolerate LF-only files too
        if ($ch eq "\n") {
            push @field, $cur; ($cur,$started) = ('',0);
            push @rows, [@field] if grep { $_ ne '' } @field;   # skip blanks
            @field = ();
            next;
        }
        $cur .= $ch; $started = 1;
    }
    push @field, $cur if $cur ne '' || @field;
    push @rows, [@field] if grep { defined && $_ ne '' } @field;
    return @rows;
}

# :raw, NOT :encoding(UTF-8), and load-bearing: everything here is bytes in,
# bytes out. Decoding the CSV's emoji alt text would upgrade the HTML byte
# string on interpolation and re-encode the page's existing UTF-8 as Latin-1,
# turning every curly quote into mojibake. See siteAssets.txt, THE 88x31 WALL.
open my $cfh, '<:raw', $CSV or die "badgeBuild: $CSV: $!\n";
my $csv_text = do { local $/; <$cfh> };
close $cfh;

my @rows = parse_csv($csv_text);
die "badgeBuild: $CSV is empty\n" unless @rows;

# The header row is optional per RFC 4180, so verify rather than assume.
my $hdr = shift @rows;
die "badgeBuild: $CSV: expected header 'file,alt,link', got '"
    . join(',', @$hdr) . "'\n"
    unless @$hdr >= 3 && $hdr->[0] eq 'file' && $hdr->[1] eq 'alt'
        && $hdr->[2] eq 'link';
die "badgeBuild: $CSV has a header but no badges\n" unless @rows;

my @badges;
my %seen;
for my $r (@rows) {
    my ($file, $alt, $link) = (@$r, '', '', '');
    $file = '' unless defined $file;
    $alt  = '' unless defined $alt;
    $link = '' unless defined $link;
    s/^\s+|\s+$//g for ($file, $link);          # NOT $alt: spaces there matter

    die "badgeBuild: $CSV: a row has no file\n" if $file eq '';
    die "badgeBuild: $CSV: '$file' listed twice\n" if $seen{$file}++;
    die "badgeBuild: $CSV: '$file' has no alt text. A decorative badge still\n"
      . "  needs alt=\"\" spelled out; an empty column here is more likely a\n"
      . "  missing field than a deliberate one.\n" if $alt eq '';
    die "badgeBuild: $CSV: '$file' has a path, not a basename. Badge sources\n"
      . "  all live in $SRC_DIR/.\n" if $file =~ m{/};
    die "badgeBuild: $SRC_DIR/$file does not exist\n" unless -f "$SRC_DIR/$file";

    push @badges, { file => $file, alt => $alt, link => $link };
}

# ------------------------------------------------------------- image geometry
#
# Read the header bytes directly. width/height on every <img> is what stops the
# wall from reflowing as it loads, and taking them from the file rather than
# hardcoding 88x31 is what makes a wrongly-sized badge visible instead of
# silently squashed by the CSS.
sub dimensions {
    my ($path) = @_;
    open my $fh, '<:raw', $path or die "badgeBuild: $path: $!\n";
    read $fh, my $head, 32;
    close $fh;

    # PNG: IHDR width/height are two big-endian 32-bit ints at offset 16.
    return unpack('NN', substr($head, 16, 8))
        if substr($head, 0, 8) eq "\x89PNG\r\n\x1a\n";

    # GIF: logical screen descriptor, two little-endian 16-bit ints at offset 6.
    return unpack('vv', substr($head, 6, 4))
        if substr($head, 0, 6) =~ /^GIF8[79]a$/;

    # WebP: VP8/VP8L/VP8X all differ; ask the library rather than parse three.
    if (substr($head, 0, 4) eq 'RIFF' && substr($head, 8, 4) eq 'WEBP') {
        chomp(my $d = `identify -format '%w %h' \Q$path\E 2>/dev/null`);
        return split / /, $d if $d =~ /^\d+ \d+$/;
    }
    die "badgeBuild: $path: unrecognised image format. Add a reader above.\n";
}

# ------------------------------------------------------------------- manifest
sub read_manifest {
    my %m;
    open my $fh, '<', $MANIFEST or return %m;
    while (<$fh>) {
        chomp;
        next if /^\s*(#|$)/;
        my ($file, $sha, $chosen, $srcb, $webpb, $w, $h) = split /\t/;
        next unless defined $h;
        $m{$file} = { sha => $sha, chosen => $chosen, srcbytes => $srcb,
                      webpbytes => $webpb, w => $w, h => $h };
    }
    close $fh;
    return %m;
}

my %old = read_manifest();
my %new;

# ------------------------------------------------------------------ encoding
sub encode_webp {
    my ($src, $dst) = @_;
    my @cmd = $src =~ /\.gif$/i
        # GIF, animated or not — cwebp cannot read the format. -min_size trades
        # encode time for the smallest file, which is the trade this script
        # exists to make.
        ? ('gif2webp', '-q', '100', '-m', '6', '-min_size', '-mt', '-quiet',
           $src, '-o', $dst)
        # Everything else. -z 9 is the maximum lossless effort level.
        : ('cwebp', '-lossless', '-z', '9', '-q', '100', '-mt', '-quiet',
           $src, '-o', $dst);

    my $rc = system(@cmd);
    die "badgeBuild: $cmd[0] failed on $src (exit " . ($rc >> 8) . ")\n" if $rc;
    die "badgeBuild: $cmd[0] produced nothing for $src\n" unless -s $dst;
}

# Write only if the bytes actually differ, and write through a temp file.
# Both matter: no-op writes would churn mtimes and make every commit look like
# it touched the wall, and several of these outputs are historically root-owned,
# which rename() over survives and open-for-write does not.
sub install {
    my ($src, $dst) = @_;
    if (-f $dst && -s $dst == -s $src) {
        open my $a, '<:raw', $src or die "badgeBuild: $src: $!\n";
        open my $b, '<:raw', $dst or die "badgeBuild: $dst: $!\n";
        local $/;
        my ($x, $y) = (<$a>, <$b>);
        close $a; close $b;
        return 0 if $x eq $y;
    }
    if ($check) { note_stale("$dst differs from what this build produces"); return 1 }
    my (undef, $tmp) = tempfile("$dst.XXXXXX", OPEN => 0);
    copy($src, $tmp) or die "badgeBuild: copy to $tmp: $!\n";
    chmod 0644, $tmp;
    rename $tmp, $dst or die "badgeBuild: rename to $dst: $!\n";
    return 1;
}

mkdir $OUT_DIR unless -d $OUT_DIR;

my ($rebuilt, $installed) = (0, 0);
my %produced;

for my $b (@badges) {
    my $src = "$SRC_DIR/$b->{file}";
    open my $fh, '<:raw', $src or die "badgeBuild: $src: $!\n";
    my $sha = sha256_hex(do { local $/; <$fh> });
    close $fh;

    my ($base, $ext) = $b->{file} =~ /^(.*?)\.([^.]+)$/
        or die "badgeBuild: $b->{file} has no extension\n";

    my $cached = $old{$b->{file}};
    my $reuse  = !$force && $cached && $cached->{sha} eq $sha;

    # A cache hit is only a hit if the file it describes is actually there. It
    # will not be on a fresh clone that predates the artifact, or after someone
    # deletes badges/ to force a rebuild.
    $reuse &&= -f "$OUT_DIR/$base." . ($cached->{chosen} eq 'webp' ? 'webp' : $ext);

    my ($chosen, $srcbytes, $webpbytes, $w, $h);
    if ($reuse) {
        ($chosen, $srcbytes, $webpbytes, $w, $h) =
            @$cached{qw(chosen srcbytes webpbytes w h)};
        $b->{from} = undef;   # nothing to install; see the note below
        $b->{tmp}  = undef;
    }
    else {
        if ($check) {
            note_stale("$b->{file} changed since the manifest was written");
        }
        ($w, $h) = dimensions($src);
        $srcbytes = -s $src;

        my (undef, $tmp) = tempfile('badge.XXXXXX', SUFFIX => '.webp',
                                    TMPDIR => 1, OPEN => 0);
        encode_webp($src, $tmp);
        $webpbytes = -s $tmp;

        # STRICTLY smaller. A tie keeps the original: shipping a second format
        # should have to earn it, and an equal-sized WebP earns nothing.
        #
        # {from} is what gets installed, and it is NOT interchangeable with
        # $src: for a WebP winner it is the encoder's temp file, and for a
        # loser it is the source itself. {tmp} is only what to clean up.
        if ($webpbytes < $srcbytes) {
            $chosen = 'webp'; $b->{from} = $tmp; $b->{tmp} = $tmp;
        }
        else {
            $chosen = $ext;   $b->{from} = $src; unlink $tmp;
        }
        $rebuilt++;
    }

    my $out_ext  = $chosen eq 'webp' ? 'webp' : $ext;
    my $out_file = "$base.$out_ext";
    $produced{$out_file} = 1;

    # A cache hit installs NOTHING, and the reason is worth stating: on a hit
    # there is no encoded temp file, because the encoders never ran. Falling
    # back to $src here would copy the PNG source over the .webp output — a
    # file whose bytes are PNG, whose name says WebP, and which nginx would
    # serve as image/webp. Browsers sniff and it would still render, so it
    # would never be noticed. The hit's own precondition is that the output
    # already exists, so there is nothing to do.
    $installed += install($b->{from}, "$OUT_DIR/$out_file") if $b->{from};
    unlink $b->{tmp} if $b->{tmp};

    warn "badgeBuild: NOTE: $b->{file} is ${w}x${h}, not 88x31. The wall's CSS\n"
       . "  forces every badge to 88x31, so this one will be squashed.\n"
        if $w != 88 || $h != 31;

    $b->{src_web} = "$WEB_PATH/$out_file";
    $b->{w} = $w; $b->{h} = $h;

    $new{$b->{file}} = { sha => $sha, chosen => $chosen, srcbytes => $srcbytes,
                         webpbytes => $webpbytes, w => $w, h => $h };
}

# Anything else in badges/ is a leftover: a badge dropped from the CSV, or the
# losing format from a comparison that flipped. The directory is wholly
# generated now, so nothing in it is authored and nothing is worth keeping.
opendir my $dh, $OUT_DIR or die "badgeBuild: $OUT_DIR: $!\n";
for my $f (sort grep { !/^\.\.?$/ } readdir $dh) {
    next if $produced{$f};
    if ($check) { note_stale("$OUT_DIR/$f is not produced by any CSV row") }
    else { unlink "$OUT_DIR/$f" or die "badgeBuild: unlink $OUT_DIR/$f: $!\n";
           print "badgeBuild: removed stale $OUT_DIR/$f\n" }
}
closedir $dh;

# -------------------------------------------------------------------- markup
sub esc {
    my ($s) = @_;
    $s =~ s/&/&amp;/g; $s =~ s/</&lt;/g; $s =~ s/>/&gt;/g; $s =~ s/"/&quot;/g;
    return $s;
}

sub wall_html {
    my ($indent) = @_;
    my @out;
    for my $b (@badges) {
        my $img = sprintf '<img src="%s" alt="%s" width="%d" height="%d">',
            esc($b->{src_web}), esc($b->{alt}), $b->{w}, $b->{h};
        $img = sprintf '<a href="%s">%s</a>', esc($b->{link}), $img
            if $b->{link} ne '';
        push @out, "$indent<li>$img</li>";
    }
    return join "\n", @out;
}

my $pages = 0;
opendir my $pd, $PAGE_DIR or die "badgeBuild: $PAGE_DIR: $!\n";
my @html = sort grep { /\.html$/ } readdir $pd;
closedir $pd;

for my $name (@html) {
    my $path = "$PAGE_DIR/$name";
    open my $fh, '<:raw', $path or die "badgeBuild: $path: $!\n";
    my $html = do { local $/; <$fh> };
    close $fh;
    next unless index($html, $MARK_START) >= 0;

    die "badgeBuild: $path has $MARK_START but no $MARK_END\n"
        if index($html, $MARK_END) < 0;

    # Indent the generated rows one step past the start marker, so the block
    # sits correctly whatever depth the page nests its <ul> at.
    my ($lead) = $html =~ /^([ \t]*)\Q$MARK_START\E/m;
    $lead = '' unless defined $lead;
    my $body = wall_html("$lead    ");

    my $before = $html;
    $html =~ s{
        (\Q$MARK_START\E [^\n]* -->) \n
        .*?
        ^([ \t]*) \Q$MARK_END\E
    }{$1\n$body\n$lead$MARK_END}smx
        or die "badgeBuild: $path: could not match the badge block\n";

    next if $html eq $before;
    if ($check) { note_stale("$path badge block is out of date"); next }

    # See the :raw note on the CSV open. If anything upstream ever decodes, this
    # string picks up wide characters and writing it silently mangles every
    # non-ASCII byte in the page. Refuse rather than corrupt the file.
    die "badgeBuild: $path: refusing to write — the page became a character\n"
      . "  string, which would re-encode its existing UTF-8. Something is\n"
      . "  decoding input that must stay bytes; see the note on the CSV open.\n"
        if $html =~ /[^\x00-\xff]/;

    open my $out, '>:raw', $path or die "badgeBuild: $path: $!\n";
    print $out $html;
    close $out;
    print "badgeBuild: rewrote the wall in $path\n";
    $pages++;
}

# ------------------------------------------------------------- write manifest
my $man = "# GENERATED by assetsBuild/badgeBuild.pl — do not edit.\n"
        . "# The encode cache, and the audit trail for the size comparison:\n"
        . "# a badge is re-encoded only when its source sha256 changes here.\n"
        . "# 'chosen' is the format that won on size; when it is not 'webp',\n"
        . "# the WebP came out no smaller and the original is served instead.\n"
        . "#\n"
        . "# file\tsha256\tchosen\tsrcBytes\twebpBytes\twidth\theight\n";
for my $f (sort keys %new) {
    my $n = $new{$f};
    $man .= join("\t", $f, @$n{qw(sha chosen srcbytes webpbytes w h)}) . "\n";
}

my $man_old = do {
    if (open my $fh, '<', $MANIFEST) { local $/; <$fh> } else { '' }
};
if ($man ne $man_old) {
    if ($check) { note_stale("$MANIFEST is out of date") }
    else {
        open my $fh, '>', $MANIFEST or die "badgeBuild: $MANIFEST: $!\n";
        print $fh $man;
        close $fh;
    }
}

if ($check) {
    print "badgeBuild: everything up to date\n" unless $stale;
    exit($stale ? 1 : 0);
}

my $total_src  = 0; $total_src  += $new{$_}{srcbytes} for keys %new;
my $total_ship = 0;
$total_ship += ($new{$_}{chosen} eq 'webp' ? $new{$_}{webpbytes}
                                           : $new{$_}{srcbytes}) for keys %new;
my $webp_wins = grep { $new{$_}{chosen} eq 'webp' } keys %new;

printf "badgeBuild: %d badges, %d re-encoded, %d files installed, %d pages\n",
    scalar @badges, $rebuilt, $installed, $pages;
printf "badgeBuild: webp wins %d/%d — wall is %d B, was %d B (%.0f%% off)\n",
    $webp_wins, scalar @badges, $total_ship, $total_src,
    $total_src ? 100 * (1 - $total_ship / $total_src) : 0;
