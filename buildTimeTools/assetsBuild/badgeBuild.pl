#!/usr/bin/perl
# Build the 88x31 button wall: re-encode the badges, then generate the markup.
#
#     badgeBuild.pl            build badges/ and rewrite the marked pages
#     badgeBuild.pl --check    exit 1 if anything is stale, write nothing
#     badgeBuild.pl --force    re-encode everything, ignoring the manifest
#
# Run from preCommit.sh, not by hand. Output is a committed artifact, like
# feed.xml and the DejaVu subsets: the deploy is a plain rsync of staticish/http/dreamstation.systems/
# with no build step, so anything served has to already exist in the repo.
#
#     unbuiltContent/webBadges.csv  <- source of truth: order, alt text, links
#     buildTimeTools/assetsBuild/badgesSrc/  <- source images, NOT under staticish/http/dreamstation.systems/
#     staticish/http/dreamstation.systems/personal/badges/          <- generated, served
#     buildTimeTools/assetsBuild/badgeManifest.txt        <- generated, the encode cache
#
# Each source image is re-encoded to lossless WebP, AVIF and JPEG XL, and ALL
# of them ship, with the original, in a <picture> whose <source>s are sorted
# smallest first. A browser takes the first <source> whose type it can decode,
# so the sort order is what makes each browser fetch the smallest file it can
# use. The original is a <source> too, in its own place by size: every browser
# decodes PNG and GIF, so nothing ranked below the original is ever fetched.
# The original is also the <img> fallback.
#
# Every encode is decoded again and compared pixel for pixel (all frames) with
# the source; a mismatch stops the build. "Lossless" here is checked, not
# assumed.
#
# badgeManifest.txt is the committed encode cache (source SHA-256 + the sizes
# in serving order) that keeps a no-image commit cheap. Full rationale — the
# size ordering, GIF handling, the JXL loop-count problem, why mtimes are
# ignored — in siteAssets.txt, THE 88x31 WALL.
#
# Needs: webp (cwebp, gif2webp), libavif-bin (avifenc, avifdec), libjxl-tools
# (cjxl, djxl), imagemagick.

use strict;
use warnings;
use Digest::SHA qw(sha256_hex);
use File::Copy qw(copy);
use File::Temp qw(tempfile tempdir);

my $CSV      = 'unbuiltContent/webBadges.csv';
my $SRC_DIR  = 'buildTimeTools/assetsBuild/badgesSrc';
my $OUT_DIR  = 'staticish/http/dreamstation.systems/personal/badges';
my $MANIFEST = 'buildTimeTools/assetsBuild/badgeManifest.txt';
my $PAGE_DIR = 'staticish/http/dreamstation.systems/personal';
my $WEB_PATH = 'badges';          # $OUT_DIR as the marked pages address it

my $MARK_START = '<!-- badges:start';
my $MARK_END   = '<!-- badges:end -->';

# The encoded formats, and the tie-break order when two files are the same
# size. The original always wins a tie (it is listed first in %RANK): a second
# format should have to earn its place above it.
my @ENCODED = qw(webp jxl avif);
my %MIME = (png => 'image/png', gif => 'image/gif', webp => 'image/webp',
            avif => 'image/avif', jxl => 'image/jxl');

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

my $TMP = tempdir('badgeBuild.XXXXXX', TMPDIR => 1, CLEANUP => 1);

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
my (%seen, %seen_base);
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
    # srcset splits on whitespace and commas, so a filename containing either
    # would be read as several candidates.
    die "badgeBuild: $CSV: '$file': badge filenames must be [A-Za-z0-9._-]\n"
      . "  only; anything else breaks the srcset= attribute.\n"
        unless $file =~ /^[A-Za-z0-9._-]+$/;
    die "badgeBuild: $SRC_DIR/$file does not exist\n" unless -f "$SRC_DIR/$file";

    my ($base, $ext) = $file =~ /^(.*?)\.([^.]+)$/
        or die "badgeBuild: $file has no extension\n";
    $ext = lc $ext;
    die "badgeBuild: $file: a source must be PNG, GIF or WebP\n"
        unless $ext =~ /^(png|gif|webp)$/;
    # foo.png and foo.gif would both want to write foo.webp, foo.avif, foo.jxl.
    die "badgeBuild: $CSV: '$file' and '$seen_base{$base}' share the name\n"
      . "  '$base', so their encoded files would overwrite each other.\n"
        if $seen_base{$base};
    $seen_base{$base} = $file;

    push @badges, { file => $file, alt => $alt, link => $link,
                    base => $base, ext => $ext };
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

# ------------------------------------------------------------------ helpers

# Run a command with its chatter (avifenc and cjxl are loud) sent to a log
# that is only shown if the command fails.
sub run {
    my @cmd = @_;
    my $log = "$TMP/run.log";
    my $pid = fork // die "badgeBuild: fork: $!\n";
    if (!$pid) {
        open STDOUT, '>', $log or die "badgeBuild: $log: $!\n";
        open STDERR, '>&', \*STDOUT or die;
        exec { $cmd[0] } @cmd or die "badgeBuild: exec $cmd[0]: $!\n";
    }
    waitpid $pid, 0;
    return unless $?;
    my $rc = $? >> 8;
    if (open my $l, '<', $log) { print STDERR <$l> }
    die "badgeBuild: $cmd[0] failed (exit $rc): @cmd\n";
}

# Stdout of a command, as bytes; dies if it fails.
sub capture {
    my @cmd = @_;
    open my $fh, '-|', @cmd or die "badgeBuild: $cmd[0]: $!\n";
    binmode $fh;
    my $out = do { local $/; <$fh> };
    close $fh or die "badgeBuild: $cmd[0] failed (exit " . ($? >> 8) . "): @cmd\n";
    return defined $out ? $out : '';
}

# Animation facts for a GIF: frame count, per-frame delays (centiseconds) and
# total plays (0 = forever). The plays come from the NETSCAPE2.0 block, where
# the stored number is REPEATS after the first play: 10 there means browsers
# play it 11 times. No block at all means it plays once.
sub gif_anim {
    my ($src) = @_;
    my @delays = split ' ', capture('identify', '-format', '%T ', $src);
    open my $fh, '<:raw', $src or die "badgeBuild: $src: $!\n";
    my $g = do { local $/; <$fh> };
    close $fh;
    my $plays = 1;
    if ($g =~ /NETSCAPE2\.0\x03\x01(..)/s) {
        my $n = unpack 'v', $1;
        $plays = $n ? $n + 1 : 0;
    }
    # Browsers show a 0 or 1 cs GIF delay as 10 cs; encode what they display.
    $_ = $_ <= 1 ? 10 : $_ for @delays;
    return { frames => scalar @delays, delays => \@delays, plays => $plays };
}

# Every frame of an image as raw RGBA, concatenated, after compositing
# (-coalesce), so formats that store animation differently still compare
# equal when they display the same pixels. The colour under a fully
# transparent pixel is invisible and encoders are free to discard it, so it is
# zeroed on both sides rather than compared.
sub rgba_of {
    my ($path) = @_;
    return capture('magick', $path, '-coalesce', '-alpha', 'on',
                   '-background', 'none', '-alpha', 'background',
                   '-depth', '8', 'rgba:-');
}

# What a browser would display from an encoded file, every frame. ImageMagick
# reads animated WebP whole but only the first frame of an AVIF or JXL
# sequence, so those go through their own decoders frame by frame.
sub decoded_rgba {
    my ($fmt, $path) = @_;
    return rgba_of($path) if $fmt eq 'webp';

    my $d = tempdir(DIR => $TMP);
    if ($fmt eq 'avif') { run('avifdec', '--index', 'all', $path, "$d/f.png") }
    else                { run('djxl', $path, "$d/f.pam", '--output_frames') }
    # avifdec names frames f-0000000000.png; djxl writes f.pam for a still and
    # f.pam-0.pam ... for an animation. The trailing number orders both.
    my $num = sub { ($_[0] =~ /(\d+)\.\w+$/)[0] // -1 };
    my @frames = sort { $num->($a) <=> $num->($b) } glob "$d/f*";
    die "badgeBuild: $fmt decoder produced nothing for $path\n" unless @frames;
    return join '', map { rgba_of($_) } @frames;
}

# ------------------------------------------------------------------ manifest
sub read_manifest {
    my %m;
    open my $fh, '<', $MANIFEST or return %m;
    while (<$fh>) {
        chomp;
        next if /^\s*(#|$)/;
        my ($file, $sha, $w, $h, $served, $dropped) = split /\t/;
        # A row from the old WebP-or-original manifest has a different shape;
        # it simply misses, and that badge is rebuilt.
        next unless defined $dropped && $served =~ /^(\w+:\d+ ?)+$/;
        my @order = map { [split /:/] } split / /, $served;
        $m{$file} = { sha => $sha, w => $w, h => $h, order => \@order,
                      dropped => $dropped };
    }
    close $fh;
    return %m;
}

my %old = read_manifest();
my %new;

# ------------------------------------------------------------------ encoding

# Encode $src as $fmt into $dst. Returns '' on success, or the reason the
# format cannot faithfully represent this source and is being left out.
sub encode {
    my ($fmt, $b, $src, $dst) = @_;
    my $anim = $b->{ext} eq 'gif' ? gif_anim($src) : undef;

    if ($fmt eq 'webp') {
        run($b->{ext} eq 'gif'
            # GIF, animated or not — cwebp cannot read the format. -min_size
            # trades encode time for the smallest file, which is the trade this
            # script exists to make. gif2webp carries the loop count across.
            ? ('gif2webp', '-q', '100', '-m', '6', '-min_size', '-mt', '-quiet',
               $src, '-o', $dst)
            # Everything else. -z 9 is the maximum lossless effort level.
            : ('cwebp', '-lossless', '-z', '9', '-q', '100', '-mt', '-quiet',
               $src, '-o', $dst));
    }
    elsif ($fmt eq 'avif') {
        # Speed 0 is the slowest, smallest setting. --lossless also sets the
        # identity matrix and 4:4:4; without it AVIF is always lossy.
        my @cmd = ('avifenc', '--lossless', '--speed', '0', '--jobs', 'all');
        if ($anim) {
            # avifenc reads PNG, JPEG and y4m — not GIF. Feed it the
            # composited frames, each with its own delay, and carry the loop
            # count across (avifenc counts repeats, as the GIF stores them).
            my $d = tempdir(DIR => $TMP);
            run('magick', $src, '-coalesce', "PNG32:$d/f%04d.png");
            my @f = sort glob "$d/f*.png";
            die "badgeBuild: $src: expected $anim->{frames} frames, got "
              . scalar(@f) . "\n" unless @f == $anim->{frames};
            if (@f > 1) {
                push @cmd, '--timescale', '100', '--repetition-count',
                    $anim->{plays} ? $anim->{plays} - 1 : 'infinite';
                push @cmd, '--duration', $anim->{delays}[$_], $f[$_] for 0..$#f;
            }
            else { push @cmd, $f[0] }
        }
        else { push @cmd, $src }
        run(@cmd, $dst);
    }
    elsif ($fmt eq 'jxl') {
        # cjxl 0.11 drops the loop count — from GIF and from APNG input alike —
        # and writes every animation as "loop forever". For a GIF that stops,
        # that would not be the same badge, so the JXL is left out instead.
        return "cjxl cannot keep its loop count (plays $anim->{plays} times, "
             . "a JXL would loop forever)"
            if $anim && $anim->{frames} > 1 && $anim->{plays} != 0;
        # -d 0 is mathematically lossless; -e 10 is the maximum effort.
        run('cjxl', '-d', '0', '-e', '10', '--quiet', $src, $dst);
    }
    else { die "badgeBuild: no encoder for $fmt\n" }

    die "badgeBuild: $fmt encode of $src produced nothing\n" unless -s $dst;
    return '';
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

# [format, bytes] pairs, smallest first; on a tie the original ($orig), then
# @ENCODED order. Out here, not inline in the loop below, because that loop's
# `my $b` would shadow sort's $b.
sub by_size {
    my ($orig, @pairs) = @_;
    my %rank;
    @rank{@ENCODED} = (1 .. @ENCODED);
    $rank{$orig} = 0;
    return sort { $a->[1] <=> $b->[1] || $rank{$a->[0]} <=> $rank{$b->[0]} }
           @pairs;
}

mkdir $OUT_DIR unless -d $OUT_DIR;

my ($rebuilt, $installed) = (0, 0);
my %produced;

for my $b (@badges) {
    my $src = "$SRC_DIR/$b->{file}";
    open my $fh, '<:raw', $src or die "badgeBuild: $src: $!\n";
    my $sha = sha256_hex(do { local $/; <$fh> });
    close $fh;

    my ($base, $ext) = @$b{qw(base ext)};

    # A cache hit is only a hit if every file it describes is actually there.
    # They will not be on a fresh clone that predates the artifact, or after
    # someone deletes badges/ to force a rebuild.
    my $cached = $old{$b->{file}};
    my $reuse  = !$force && $cached && $cached->{sha} eq $sha
              && !grep { !-f "$OUT_DIR/$base.$_->[0]" } @{ $cached->{order} };

    my ($w, $h, @order, $dropped);
    if ($reuse) {
        ($w, $h, $dropped) = @$cached{qw(w h dropped)};
        @order = @{ $cached->{order} };
        # A cache hit installs NOTHING: there are no encoded temp files,
        # because the encoders never ran, and the hit's own precondition is
        # that every output already exists.
    }
    else {
        note_stale("$b->{file} changed since the manifest was written") if $check;
        ($w, $h) = dimensions($src);

        # The original ships too, under its own extension, lower-cased so the
        # served name and the generated type= always agree.
        my %from = ($ext => $src);
        my @why;
        my $want = rgba_of($src);
        for my $fmt (grep { $_ ne $ext } @ENCODED) {
            my (undef, $tmp) = tempfile("enc.XXXXXX", SUFFIX => ".$fmt",
                                        DIR => $TMP, OPEN => 0);
            my $skip = encode($fmt, $b, $src, $tmp);
            if ($skip) { push @why, "$fmt: $skip"; next }
            die "badgeBuild: $fmt encode of $src is NOT lossless: its decoded\n"
              . "  pixels differ from the source. Nothing was installed.\n"
                unless decoded_rgba($fmt, $tmp) eq $want;
            $from{$fmt} = $tmp;
        }
        $dropped = @why ? join('; ', @why) : '-';
        warn "badgeBuild: NOTE: $b->{file}: left out $_\n" for @why;

        @order = by_size($ext, map { [$_, -s $from{$_}] } keys %from);

        $installed += install($from{$_->[0]}, "$OUT_DIR/$base.$_->[0]")
            for @order;
        $rebuilt++;
    }

    $produced{"$base.$_->[0]"} = 1 for @order;

    warn "badgeBuild: NOTE: $b->{file} is ${w}x${h}, not 88x31. The wall's CSS\n"
       . "  forces every badge to 88x31, so this one will be squashed.\n"
        if $w != 88 || $h != 31;

    $b->{order} = \@order;
    $b->{w} = $w; $b->{h} = $h;

    $new{$b->{file}} = { sha => $sha, w => $w, h => $h, order => \@order,
                         dropped => $dropped };
}

# Anything else in badges/ is a leftover: a badge dropped from the CSV, or a
# format that is no longer produced. The directory is wholly generated, so
# nothing in it is authored and nothing is worth keeping.
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

# One <li> per badge, one line each:
#   <li><a><picture><source>... smallest first ...<img></picture></a></li>
sub wall_html {
    my ($indent) = @_;
    my @out;
    for my $b (@badges) {
        my $pic = '<picture>';
        $pic .= sprintf '<source srcset="%s" type="%s">',
            esc("$WEB_PATH/$b->{base}.$_->[0]"), $MIME{$_->[0]}
            for @{ $b->{order} };
        $pic .= sprintf '<img src="%s" alt="%s" width="%d" height="%d" loading="lazy">',
            esc("$WEB_PATH/$b->{base}.$b->{ext}"), esc($b->{alt}),
            $b->{w}, $b->{h};
        $pic .= '</picture>';
        $pic = sprintf '<a href="%s">%s</a>', esc($b->{link}), $pic
            if $b->{link} ne '';
        push @out, "$indent<li>$pic</li>";
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
my $man = "# GENERATED by buildTimeTools/assetsBuild/badgeBuild.pl — do not edit.\n"
        . "# The encode cache, and the audit trail for the size ordering:\n"
        . "# a badge is re-encoded only when its source sha256 changes here.\n"
        . "# 'served' is every shipped file as format:bytes, smallest first,\n"
        . "# which is the <source> order on the page. 'dropped' is any format\n"
        . "# left out for this badge, and why.\n"
        . "#\n"
        . "# file\tsha256\twidth\theight\tserved\tdropped\n";
for my $f (sort keys %new) {
    my $n = $new{$f};
    $man .= join("\t", $f, @$n{qw(sha w h)},
                 join(' ', map { "$_->[0]:$_->[1]" } @{ $n->{order} }),
                 $n->{dropped}) . "\n";
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

# What the wall costs a browser, given what it decodes: the first <source> in
# each badge's order that it supports. PNG and GIF are always supported.
sub wall_bytes {
    my %ok = map { $_ => 1 } qw(png gif), @_;
    my $t = 0;
    for my $b (@badges) {
        my ($first) = grep { $ok{$_->[0]} } @{ $b->{order} };
        $t += $first ? $first->[1] : 0;   # a WebP original, no WebP support
    }
    return $t;
}
my $orig_total = wall_bytes();

printf "badgeBuild: %d badges, %d re-encoded, %d files installed, %d pages\n",
    scalar @badges, $rebuilt, $installed, $pages;
printf "badgeBuild: wall is %d B as originals; %d B with WebP+AVIF; "
     . "%d B with JXL too\n",
    $orig_total, wall_bytes(qw(webp avif)), wall_bytes(qw(webp avif jxl));
