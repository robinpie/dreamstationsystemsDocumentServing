#!/usr/bin/perl
# lawaPublish.pl - copy lawaPage.pl's finished files (three per language) into the doc roots.
# Runs as ROOT (ExecStartPost=+ in lawaPage.service), because /srv/http is
# root-owned - so it trusts nothing about the directory it reads from, which
# belongs to the unprivileged account that just parsed data off the internet:
#
#   - the source is opened O_NOFOLLOW and must be a regular file OWNED BY
#     lawapull, 1 byte .. 1 MB. (/var/lib/lawapull itself is root-owned, so the
#     account cannot swap out/ for a symlink; fs.protected_hardlinks stops it
#     hard-linking somebody else's file in.)
#   - the HTML fragment is SSI-included into lawa.html, so it is refused if it
#     contains an SSI directive, a script, a frame or an event handler. The
#     renderer escapes everything; this is the second lock.
#   - each destination is written to a temp file beside it and renamed, so no
#     server ever reads half a page.
#
# The fragment goes to the STAGING docroot too, so staging.dreamstation.systems
# previews the real page (stageSite.sh leaves that one file alone).
use strict;
use warnings;
use Fcntl qw(O_RDONLY O_NOFOLLOW S_ISREG);

my $SRC = '/var/lib/lawapull/out';
my @PLAN = (
    # source            destination                                     owner    html?
    [ 'lawa-data.html', '/srv/http/personal/lawa-data.html',            'root',  1 ],
    [ 'lawa-data.html', '/srv/httpstaging/personal/lawa-data.html',     'root',  1 ],
    [ 'lawa.gmi',       '/srv/gemini/lawa.gmi',                         'robin', 0 ],
    [ 'lawa.txt',       '/srv/gopher/lawa.txt',                         'robin', 0 ],
    # The toki pona copies (lawaPage.pl renders one set per language in its
    # __DATA__). The fragment is what content/tok/lawa.tri includes. The two
    # retro files land in tok/, which exists only once some translation has
    # been published there; until then the `-d $dir` test below skips them.
    [ 'lawa-data.tok.html', '/srv/http/personal/lawa-data.tok.html',        'root',  1 ],
    [ 'lawa-data.tok.html', '/srv/httpstaging/personal/lawa-data.tok.html', 'root',  1 ],
    [ 'lawa.tok.gmi',       '/srv/gemini/tok/lawa.gmi',                     'robin', 0 ],
    [ 'lawa.tok.txt',       '/srv/gopher/tok/lawa.txt',                     'robin', 0 ],
);

my $src_uid = getpwnam('lawapull') // die "lawaPublish: no lawapull user\n";
my $bad = 0;
for my $p (@PLAN) {
    my ($name, $dest, $owner, $is_html) = @$p;
    (my $dir = $dest) =~ s{/[^/]+$}{};
    next unless -d $dir;    # e.g. no staging tree on this box
    my $why = eval {
        sysopen(my $in, "$SRC/$name", O_RDONLY | O_NOFOLLOW) or return "cannot open: $!";
        my @st = stat $in;
        return 'not a regular file'    unless S_ISREG($st[2]);
        return 'not owned by lawapull' unless $st[4] == $src_uid;
        return "implausible size $st[7]" unless $st[7] >= 1 && $st[7] <= 1_048_576;
        binmode $in;
        my $data = do { local $/; <$in> };
        return 'short read' unless defined $data && length($data) == $st[7];
        return 'contains NUL' if $data =~ /\0/;
        return 'fragment contains active markup'
            if $is_html && $data =~ /<!--\s*#|<\s*(?:script|iframe|object|embed|link|meta|style|form|img|svg)\b|\bon[a-z]+\s*=|javascript:/i;

        if (open my $old, '<', $dest) {    # unchanged: leave the mtime alone
            binmode $old;
            my $cur = do { local $/; <$old> };
            return '' if defined $cur && $cur eq $data;
        }
        my ($uid, $gid) = (getpwnam $owner)[2, 3];
        return "no such user $owner" unless defined $uid;
        my $tmp = "$dest.lawaPublish.$$";
        open my $out, '>', $tmp or return "cannot write $tmp: $!";
        binmode $out;
        print {$out} $data;
        close $out or return "close $tmp: $!";
        chown $uid, $gid, $tmp;
        chmod 0644, $tmp;
        rename $tmp, $dest or do { unlink $tmp; return "rename to $dest: $!" };
        return '';
    };
    $why = "died: $@" unless defined $why;
    if (length $why) { warn "lawaPublish: $name -> $dest REFUSED: $why\n"; $bad++ }
}
exit($bad ? 1 : 0);
