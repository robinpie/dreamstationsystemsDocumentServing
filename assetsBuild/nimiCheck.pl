#!/usr/bin/perl
# nimiCheck — is this toki pona inside nimi ku suli + linluwi?
#
#     assetsBuild/nimiCheck.pl content/tok/post/gzipt.tri ...
#     assetsBuild/nimiCheck.pl rootdomain/professional/index.tok.html
#     assetsBuild/nimiCheck.pl lawaPage/lawaPage.pl      (its [tok] msgstr lines)
#
# Reads a translation (.tri source, or hand-written .html) and reports every
# lowercase word in its PROSE that is not in the agreed vocabulary: the 120 pu
# words, the 17 nimi ku suli, and linluwi (content/tok/README.md). Exit status
# is non-zero if any file has one.
#
# It is a spell-checker, not a grammar checker, and deliberately a forgiving
# one. It skips everything that is legitimately not toki pona:
#
#   - code: fenced blocks, `inline code`, raw-HTML markup, <pre>/<code>/<style>
#   - addresses: URLs, link refs "(...)" after "]", e-mail addresses
#   - triptych syntax: front-matter keys, "@ attr" lines, @links tables,
#     ":::" fences, "//" comments, {html: cond markers
#   - proper names: any word with a capital letter in it (jan Apen, NTP,
#     GitHub), and anything with a digit
#   - names the file itself vouches for: a source comment
#         // nimiCheck: allow viewpoint xcaca
#     (in .html: <!-- nimiCheck: allow ... -->) admits lowercase proper names,
#     so nobody has to backtick a project name just to get past this script
#   - quoted foreign text: `>` blockquotes, and whatever sits inside “…”, since a quotation is not
#     retypeset or translated (unicodePedanticism.txt)
#
# So a clean run means "no stray English and no nimi sin", not "good toki pona".
use strict;
use warnings;
use utf8;
use open ':std', ':encoding(UTF-8)';

my %OK = map { $_ => 1 } qw(
	a akesi ala alasa ale ali anpa ante anu awen e en esun ijo ike ilo insa
	jaki jan jelo jo kala kalama kama kasi ken kepeken kili kiwen ko kon kule
	kulupu kute la lape laso lawa len lete li lili linja lipu loje lon luka
	lukin lupa ma mama mani meli mi mije moku moli monsi mu mun musi mute
	nanpa nasa nasin nena ni nimi noka o olin ona open pakala pali palisa pan
	pana pi pilin pimeja pini pipi poka poki pona pu sama seli selo seme sewi
	sijelo sike sin sina sinpin sitelen sona soweli suli suno supa suwi tan
	taso tawa telo tenpo toki tomo tu unpa uta utala walo wan waso wawa weka
	wile
	epiku jasima kijetesantakalu kin kipisi kokosila ku lanpan leko meso
	misikeke monsuta n namako oko soko tonsi
	linluwi
);

# Lowercase by nature, and named in content/tok/README.md as words that stay
# in their real spelling: a reader has to be able to type them. Anything more
# local than this belongs in the file's own `nimiCheck: allow` comment.
my %NAME = map { $_ => 1 } qw(
	gzip gzipt nginx chrony chronyd ntpd ntpsec systemd curl git finger telnet
	netcat nc sixel lawa dreamstation starport
);

die "usage: nimiCheck.pl <file>...\n" unless @ARGV;
my $bad = 0;

for my $path (@ARGV) {
	open my $fh, '<:encoding(UTF-8)', $path or die "nimiCheck: $path: $!\n";
	my @lines = <$fh>;
	close $fh;
	chomp @lines;

	my $html = $path =~ /\.html?$/;
	my %unknown;    # word => [line numbers]
	my %allow;      # from `// nimiCheck: allow ...` comments in the file

	if ($path =~ /\.pl$/) {
		# A script with gettext-style translations after __DATA__
		# (lawaPage/lawaPage.pl): the prose is the msgstr lines of the [tok]
		# section, minus their {placeholders}. Everything else is code.
		my ($data, $lang) = (0, '');
		for my $i (0 .. $#lines) {
			local $_ = $lines[$i];
			$lines[$i] = '';
			if ($_ eq '__DATA__') { $data = 1; next }
			next unless $data;
			if (/^\[(\w+)\]\s*$/) { $lang = $1; next }
			next unless $lang eq 'tok' && s/^msgstr ?//;
			# a placeholder stands for a number: make it one, so that a unit
			# symbol bound to it ({n}{nbsp}s) passes exactly as "4 s" does
			s/\{nbsp\}/\x{A0}/g;
			s/\{\w+\}/0/g;
			$lines[$i] = $_;
		}
	} elsif ($html) {
		# Blank out, keeping newlines so line numbers survive.
		my $t = join "\n", @lines;
		$allow{$_} = 1 for map { split ' ' } $t =~ /<!--\s*nimiCheck:\s*allow\s+(.*?)\s*-->/gs;
		my $blank = sub { (my $x = $_[0]) =~ s/[^\n]//g; $x };
		$t =~ s{(<!--.*?-->)}{$blank->($1)}gse;
		$t =~ s{(<(style|script|pre|code|kbd|samp)\b.*?</\2>)}{$blank->($1)}gsie;
		$t =~ s{(<[^>]*>)}{ ' ' . $blank->($1) }gse;
		$t =~ s{&\w+;|&#\d+;}{ }g;
		@lines = split /\n/, $t, -1;
	} else {
		my ($fm, $fence, $links, $raw, $incomment, $inblock, $stanza) = (0, 0, 0, 0, 0, '', 0);
		for my $i (0 .. $#lines) {
			local $_ = $lines[$i];
			my $keep = '';
			if ($_ eq '---' && ($i == 0 || $fm == 1)) { $fm++; $lines[$i] = ''; next }
			if ($fm == 1) {
				# only the human-readable values are prose
				$keep = $1 if /^(?:[\w.]*title|title_markup|[\w.]*page_title|description):\s*(.*)$/;
				$lines[$i] = $keep; next;
			}
			if (/^```/)        { $fence = !$fence; $lines[$i] = ''; next }
			# >>> ... >>> is a verbatim quotation: someone else's words
			if (!$fence && /^>>>\s*$/) { $stanza = !$stanza; $lines[$i] = ''; next }
			if ($stanza)       { $lines[$i] = ''; next }
			if ($fence)        { $lines[$i] = ''; next }
			if (/^\@links\s*$/) { $links = 1; $lines[$i] = ''; next }
			if ($links)        { $links = 0 if /^\@end\s*$/; $lines[$i] = ''; next }
			if (/^:::\s*raw\b/) { $raw = 1; $lines[$i] = ''; next }
			if (/^:::/)        { $raw = 0; $lines[$i] = ''; next }
			# "// nimiCheck: allow viewpoint xcaca" — a lowercase proper name
			# (a project, a command used as a noun) that is right as written
			if (m{^\s*//\s*nimiCheck:\s*allow\s+(.*)$}) { $allow{$_} = 1 for split ' ', $1 }
			if (/^\s*\/\// || /^\@(\s|postlist)/) { $lines[$i] = ''; next }
			# a blockquote is somebody else's words, carried over untranslated
			if (/^>/) { $lines[$i] = ''; next }
			if ($raw) {         # markup out, human text stays
				# an HTML comment may run over several lines of a raw block
				if ($incomment) {
					if (s/^.*?-->//) { $incomment = 0 } else { $lines[$i] = ''; next }
				}
				s{<!--.*?-->}{ }g;
				$incomment = 1 if s/<!--.*$//;
				# likewise a <script> (JSON-LD), <style>, <pre> or <code> block
				if ($inblock) {
					if (s{^.*?</\Q$inblock\E>}{}i) { $inblock = '' } else { $lines[$i] = ''; next }
				}
				s{<(style|script|pre|code|blockquote)\b.*?</\1>}{ }gi;
				$inblock = lc $1 if s{<(style|script|pre|code|blockquote)\b.*$}{}i;
				s{<[^>]*>}{ }g;
				s{&\w+;|&#\d+;}{ }g;
			}
			s{<[^>]*>}{ }g if /^=>\s*raw=/;    # a verbatim link line is markup too
			s/^=>\s*(?:(?:only|raw)=\S+\s*)?//;
			$lines[$i] = $_;
		}
	}

	for my $i (0 .. $#lines) {
		local $_ = $lines[$i];
		next unless length;
		s/`[^`]*`(?::\w+)?/ /g;               # inline code
		s/“[^”]*”/ /g;                        # quoted text is carried, not translated
		s/\]\([^)]*\)/] /g;                   # link refs
		s/\[\[\w+:.*?\]\]/ /g;                # [[html:...]] verbatim spans
		s/\{!?[\w ]+:/ /g;                    # cond markers (their content stays)
		s{\b\w+://\S+}{ }g;                   # URLs
		s/\S+@\S+/ /g;                        # addresses, finger @host
		s/\b[\w-]+(?:\.[\w-]+)+\b/ /g;          # domains and file names: a.b, x.tar.gz
		s/\[\^\d+\]:?/ /g;                    # footnote marks
		# a unit symbol bound to its number: 5 ms, 4 s, 1 min (README: units stay)
		s/(?<=\d)[ \x{A0}\x{202F}\x{2009}]?(?:ns|µs|ms|s|min|h|d|px|em|rem|bit|bits|b)\b/ /g;
		for my $w (/[\p{L}\p{N}_'’‐-]+/g) {
			next if $w =~ /[\p{Lu}\p{N}]/;    # a proper name, an acronym, a number
			next if $w =~ /^[-‐_'’]+$/;
			next if $OK{$w} || $NAME{$w} || $allow{$w};
			push @{ $unknown{$w} }, $i + 1;
		}
	}

	if (%unknown) {
		$bad = 1;
		print "$path:\n";
		for my $w (sort { $unknown{$a}[0] <=> $unknown{$b}[0] } keys %unknown) {
			my @l = @{ $unknown{$w} };
			my $n = @l;
			splice @l, 6 if @l > 6;
			printf "  %-22s line%s %s%s\n", $w, $n > 1 ? 's' : ' ',
				join(', ', @l), $n > 6 ? ", … ($n)" : '';
		}
	} else {
		print "$path: pona\n";
	}
}
exit $bad;
