#!/usr/bin/perl
# Deploy-time: strip HTML comments from the staged copy of rootdomain/.
#
#   ./stripComments.pl <source tree> <deployed tree>
#
# Called by stageSite.sh right after its rsync, as
# `stripComments.pl rootdomain /srv/httpstaging`. For every *.html under the
# SOURCE tree it rewrites the copy at the same relative path under the
# DEPLOYED tree. Walking the source rather than the destination is deliberate:
# the deployed tree also holds files this repo does not own (lawaPublish.pl's
# lawa-data.html and friends), and those are not ours to touch.
#
# The repo keeps every comment; only the served copy loses them. Staging is
# where this happens (not promote), so that what you preview is byte-for-byte
# what promote makes live. See githooks.txt, "comment stripping".
#
# KEPT, everything else removed:
#   <!--# ... -->                   nginx SSI. nginx only treats "<!--#" as a
#                                   directive, so that prefix is the test.
#   any comment containing "<!--#"  an SSI nested in a comment is still live
#                                   to nginx; cutting around it would mangle it
#   doNotRemoveCommentInDeploy      the opt-out marker, anywhere in the comment
#   <!--[if ...]> / <!--<![endif]-->  conditional comments (old/ has some)
#
# Never looked inside: <script>, <style>, <textarea>, <title>, <xmp>. Their
# content is raw text to an HTML parser, so a "<!--" there is not a comment.
#
# A comment alone on its line(s) takes the whole line with it, so the output
# has no blank-line scars; a trailing comment takes its leading whitespace.
#
# The deployed file keeps its mtime (which rsync -a copied from the source),
# so promote's rsync to /srv/http sees an unchanged file as unchanged and
# Last-Modified/ETag do not move on every commit.
use strict;
use warnings;
use File::Find;

my $KEEP_MARK = 'doNotRemoveCommentInDeploy';

die "usage: $0 <source tree> <deployed tree>\n" unless @ARGV == 2;
my ($src, $dst) = @ARGV;
-d $src or die "$0: $src: not a directory\n";
-d $dst or die "$0: $dst: not a directory\n";

sub keep_comment {
	my ($c) = @_;
	return 1 if $c =~ /^<!--#/;               # SSI directive
	return 1 if index($c, '<!--#', 4) >= 0;   # comment wrapping an SSI
	return 1 if index($c, $KEEP_MARK) >= 0;   # explicit opt-out
	return 1 if $c =~ /^<!--\s*(?:\[if\b|<!\[endif\])/i;  # conditional
	return 0;
}

# Returns (stripped html, number of comments removed, warning or undef).
sub strip {
	my ($in) = @_;
	my ($out, $removed, $pos) = ('', 0, 0);
	my $len = length $in;

	while ($pos < $len) {
		# Next thing of interest: a comment, or a raw-text element to skip.
		$in =~ /\G(.*?)(<!--|<(script|style|textarea|title|xmp)\b)/gcis
			or last;
		$out .= $1;
		my $start = $-[2];

		if (defined $3) {                     # raw-text element: copy to its end tag
			my $tag = lc $3;
			if ($in =~ /\G.*?<\/$tag\s*>/gcis) {
				$out .= substr($in, $start, pos($in) - $start);
				$pos = pos($in);
				next;
			}
			$out .= substr($in, $start);      # unterminated: leave as is
			return ($out, $removed, "unterminated <$tag>");
		}

		my $end = index($in, '-->', $start + 4);
		if ($end < 0) {
			$out .= substr($in, $start);      # unterminated: leave as is
			return ($out, $removed, 'unterminated comment');
		}
		$end += 3;
		my $c = substr($in, $start, $end - $start);

		if (keep_comment($c)) {
			$out .= $c;
		} else {
			$removed++;
			# Whitespace up to end of line after the comment?
			my $rest_ws = substr($in, $end) =~ /\A([ \t]*)(\r?\n|\z)/ ? $1 . $2 : undef;
			if (defined $rest_ws) {
				if ($out =~ /(?:\A|\n)([ \t]*)\z/) {
					# Alone on its line: drop the line entirely.
					substr($out, -length $1) = '' if length $1;
					$end += length $rest_ws;
				} else {
					# Trailing comment: drop the whitespace before it too.
					$out =~ s/[ \t]+\z//;
				}
			}
		}
		$pos = $end;
		pos($in) = $pos;
	}
	$out .= substr($in, $pos) if $pos < $len;
	return ($out, $removed, undef);
}

my ($files, $total) = (0, 0);
find({ no_chdir => 1, wanted => sub {
	return unless -f $_ && /\.html\z/;
	my $rel = substr($File::Find::name, length($src));
	$rel =~ s{^/+}{};
	my $target = "$dst/$rel";
	return unless -f $target && !-l $target;

	open my $fh, '<:raw', $target or die "$0: $target: $!\n";
	my $html = do { local $/; <$fh> };
	close $fh;

	my ($stripped, $n, $warn) = strip($html);
	warn "$0: WARNING: $rel: $warn; rest of file left as is\n" if $warn;
	return if $stripped eq $html;

	my @st = stat $target or die "$0: $target: $!\n";
	open my $out, '>:raw', "$target.strip$$" or die "$0: $target.strip$$: $!\n";
	print {$out} $stripped or die "$0: write $target: $!\n";
	close $out or die "$0: close $target: $!\n";
	chmod $st[2] & 07777, "$target.strip$$";
	utime $st[8], $st[9], "$target.strip$$";
	rename "$target.strip$$", $target or die "$0: rename $target: $!\n";
	$files++;
	$total += $n;
}}, $src);

print "Stripped $total comment(s) from $files file(s) in $dst\n";
