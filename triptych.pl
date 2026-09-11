#!/usr/bin/perl
# triptych — one source, three panels.
#
# Renders content/*.tri to all three protocols:
#
#     rootdomain/personal/*.html   HTML (SSI, themes, JSON-LD, badge markers)
#     gemini/**.gmi                gemtext (Spartan reads the same tree)
#     gopher/**                    gophermaps and text/plain
#
# Design and rationale: triptych.md. Target conventions: triptych.conf.
# Page chrome lives in templates/<target>/<kind>.tpl, never in a .tri.
#
#     ./triptych.pl              render everything, write the outputs
#     ./triptych.pl --check      render to memory, diff against the tree
#     ./triptych.pl --list       what would be written, from what
#     ./triptych.pl --source-of <file>
#                                print the .tri an output file came from, so
#                                another hook can tell generated from authored
#     ./triptych.pl <id>...      restrict to these pages (with or without
#                                --check; unnamed pages are left alone)
#
# The outputs are COMMITTED, because promoteSite.sh is a plain rsync with no
# build step on the server. preCommit.sh runs this first, before the hooks
# that rewrite what it produced (badgeBuild.pl fills the badge markers,
# datestampHook.pl stamps dateModified) — see githooks.txt.
use strict;
use warnings;
use utf8;
use open ':std', ':encoding(UTF-8)';
use File::Basename qw(basename dirname);
use File::Path qw(make_path);

my $ROOT = dirname(File::Spec->rel2abs($0));
use File::Spec;

# ---------------------------------------------------------------- arguments
my ($CHECK, $LIST, $SOURCE_OF, @ONLY) = (0, 0, '');
for (my $i = 0; $i < @ARGV; $i++) {
	my $a = $ARGV[$i];
	if    ($a eq '--check') { $CHECK = 1 }
	elsif ($a eq '--list')  { $LIST  = 1 }
	elsif ($a eq '--source-of') { $SOURCE_OF = $ARGV[++$i] // '' }
	elsif ($a =~ /^-/)      { die "triptych: unknown option $a\n" }
	else                    { push @ONLY, $a }
}
my %only = map { $_ => 1 } @ONLY;

# ================================================================== config
#
# triptych.conf is [section] + key=value. The three target sections carry the
# per-protocol conventions that would otherwise be retyped in every page; the
# [links] section is the site-wide link table (see parse_links).
my %CONF = read_conf("$ROOT/triptych.conf");
my @TARGETS = qw(html gemini gopher);
my %SITELINKS = %{ $CONF{links} || {} };

sub read_conf {
	my ($path) = @_;
	open my $fh, '<:encoding(UTF-8)', $path or die "triptych: $path: $!\n";
	my (%c, $sec);
	my @lines = <$fh>;
	chomp @lines;
	while (defined(my $l = shift @lines)) {
		# a row may be continued with a trailing backslash, like a link table
		while ($l =~ /\\$/ && @lines) {
			$l =~ s/\s*\\$//;
			$l .= ' ' . shift @lines;
		}
		next if $l =~ /^\s*(#|$)/;
		if ($l =~ /^\s*\[(\w+)\]\s*$/) { $sec = $1; next }
		die "triptych: $path:$.: value outside a section\n" unless $sec;
		if ($sec eq 'links') {
			my ($id, $rest) = $l =~ /^\s*(\S+)\s+(.*)$/
				or die "triptych: $path:$.: bad link row\n";
			$c{links}{$id} = parse_attrs($rest);
		} else {
			my ($k, $v) = $l =~ /^\s*([\w.]+)\s*=\s*(.*?)\s*$/
				or die "triptych: $path:$.: bad key=value\n";
			$c{$sec}{$k} = $v;
		}
	}
	close $fh;
	return %c;
}

# key=value pairs, values optionally "quoted", bare key means key=1.
sub parse_attrs {
	my ($s) = @_;
	my %a;
	while ($s =~ /\G\s*([\w.]+)(?:=(?:"([^"]*)"|(\S+)))?/gc) {
		my $k = $1;
		my $v = defined $2 ? $2 : defined $3 ? $3 : 1;
		$a{$k} = $v;
	}
	return \%a;
}

# A target-scoped lookup: attr('gemini', 'col', $attrs) prefers gemini.col
# over a bare col. Used for block attributes, link rows and front matter alike,
# which is what makes "one knob, optionally narrowed to one protocol" uniform.
sub attr {
	my ($t, $k, @sets) = @_;
	for my $s (@sets) {
		next unless $s;
		return $s->{"$t.$k"} if exists $s->{"$t.$k"};
		return $s->{$k}      if exists $s->{$k};
	}
	return undef;
}

# ================================================================== parsing
#
# A .tri is front matter, then blocks. Blocks are blank-line separated; the
# constructs that are not (attribute lines, region fences, link tables) are
# consumed as they are met.
sub parse_file {
	my ($path) = @_;
	open my $fh, '<:encoding(UTF-8)', $path or die "triptych: $path: $!\n";
	my @lines = <$fh>;
	close $fh;
	chomp @lines;

	my %doc = (path => $path, links => {}, blocks => []);

	# ---- front matter
	die "triptych: $path: no front matter\n" unless @lines && $lines[0] eq '---';
	shift @lines;
	while (@lines) {
		my $l = shift @lines;
		last if $l eq '---';
		next if $l =~ m{^\s*(#|//|$)};
		my ($k, $v) = $l =~ /^([\w.]+):\s*(.*)$/
			or die "triptych: $path: bad front matter line: $l\n";
		if ($v eq '|') {    # indented heredoc, dedented by its first line
			my @buf;
			my $indent;
			while (@lines && $lines[0] ne '---'
				&& ($lines[0] =~ /^\s/ || $lines[0] eq '')) {
				my $b = shift @lines;
				$b = '' if $b =~ /^\s*$/;
				if ($b ne '' && !defined $indent) { ($indent) = $b =~ /^(\s+)/ }
				$b =~ s/^\Q$indent\E// if defined $indent && $b ne '';
				push @buf, $b;
			}
			pop @buf while @buf && $buf[-1] eq '';
			$v = join("\n", @buf);
		}
		$doc{fm}{$k} = $v;
	}

	# ---- body
	$doc{blocks} = parse_blocks(\@lines, \%doc, $path);
	return \%doc;
}

sub parse_blocks {
	my ($lines, $doc, $path) = @_;
	my @blocks;
	my %pending;       # attributes from @ lines, applied to the next block
	my @region;        # stack of region conditions from ::: fences

	my $take = sub {
		my %b = (@_, attrs => {%pending});
		%pending = ();
		# A region's condition rides on every block inside it.
		for my $r (@region) {
			$b{attrs}{only} = $r->{only} if $r->{only};
			$b{attrs}{skip} = $r->{skip} if $r->{skip};
		}
		push @blocks, \%b;
	};

	while (@$lines) {
		my $l = shift @$lines;

		# blank
		next if $l =~ /^\s*$/;

		# comment (source-only, reaches no output)
		next if $l =~ /^\s*\/\//;

		# attribute line
		if ($l =~ /^\@\s+(.*)$/) {
			my $a = parse_attrs($1);
			$pending{$_} = $a->{$_} for keys %$a;
			next;
		}

		# link table
		if ($l =~ /^\@links\s*$/) {
			while (@$lines) {
				my $r = shift @$lines;
				last if $r =~ /^\@end\s*$/;
				next if $r =~ /^\s*(#|$)/;
				while ($r =~ /\\$/ && @$lines) {    # continuation
					$r =~ s/\s*\\$//;
					$r .= ' ' . shift @$lines;
				}
				my ($id, $rest) = $r =~ /^\s*(\S+)\s+(.*)$/
					or die "triptych: $path: bad link row: $r\n";
				$doc->{links}{$id} = parse_attrs($rest);
			}
			next;
		}

		# region fence
		if ($l =~ /^:::\s*(.*)$/) {
			my $spec = $1;
			if ($spec eq '') { pop @region; next }       # closing :::
			if ($spec =~ /^raw\s+(\w+)(?:\s+(\w+))?$/) { # verbatim passthrough
				my ($t, $slot) = ($1, $2 || 'body');
				my @buf;
				while (@$lines) {
					my $r = shift @$lines;
					last if $r =~ /^:::\s*$/;
					push @buf, $r;
				}
				$take->(type => 'raw', target => $t, slot => $slot, lines => \@buf);
				next;
			}
			my ($kw, @t) = split ' ', $spec;
			if    ($kw eq 'only') { push @region, { only => join(' ', @t) } }
			elsif ($kw eq 'skip') { push @region, { skip => join(' ', @t) } }
			else { push @region, { only => join(' ', $kw, @t) } }
			next;
		}

		# heading
		if ($l =~ /^(\#{1,4})\s+(.*)$/) {
			$take->(type => 'heading', level => length($1), text => $2);
			next;
		}

		# horizontal rule
		if ($l =~ /^-{4,}\s*$/) { $take->(type => 'rule'); next }

		# the blog index's entries, which are not authored anywhere: they are
		# the set of posts, newest first.
		if ($l =~ /^\@postlist\s*$/) { $take->(type => 'postlist'); next }

		# preformatted / code fence
		if ($l =~ /^```(\S*)\s*$/) {
			my $lang = $1;
			my @buf;
			while (@$lines) {
				my $r = shift @$lines;
				last if $r =~ /^```\s*$/;
				push @buf, $r;
			}
			$take->(type => 'pre', lang => $lang, lines => \@buf);
			next;
		}

		# quote block: lines prefixed >, or a ">>>" fence for verbatim stanzas
		if ($l =~ /^>>>\s*$/) {
			my @buf;
			while (@$lines) {
				my $r = shift @$lines;
				last if $r =~ /^>>>\s*$/;
				push @buf, $r;
			}
			$take->(type => 'quote', lines => \@buf);
			next;
		}

		# table: markdown pipe rows, optionally with a --- separator. The HTML
		# shape (thead, or th scope="row" for a key/value table) and the retro
		# shape (column-aligned, fenced) come from the same rows.
		if ($l =~ /^\|/) {
			my @rows = ($l);
			while (@$lines && $lines->[0] =~ /^\|/) { push @rows, shift @$lines }
			my (@cells, $sep);
			for my $r (@rows) {
				my $x = $r;
				$x =~ s/^\|\s*//;
				$x =~ s/\s*\|\s*$//;
				if ($x =~ /^-{2,}(\s*\|\s*-{2,})*$/) { $sep = scalar @cells; next }
				# \| is a literal pipe inside a cell
				push @cells, [ map { s/^\s+|\s+$//gr =~ s/\\\|/|/gr }
					split /\s*(?<!\\)\|\s*/, $x ];
			}
			$take->(type => 'table', rows => \@cells, sep => $sep);
			next;
		}

		# list. An item may carry indented blocks under it (a paragraph, a
		# table, a code block), which is how the numbered walkthroughs work.
		if ($l =~ /^([-*]|\d+\.)\s+(.*)$/) {
			my ($marker, $first) = ($1, $2);
			my $ordered = ($marker =~ /\d/) ? 1 : 0;
			my @items;
			my $push_item = sub { push @items, { text => $_[0], blocks => [] } };
			$push_item->($first);
			while (@$lines) {
				# Look past blank lines: what comes next decides whether this is
				# the next item, a block belonging to the current one, or the
				# end of the list.
				my $k = 0;
				$k++ while $k < @$lines && $lines->[$k] =~ /^\s*$/;
				last unless $k < @$lines;
				if ($lines->[$k] =~ /^(?:[-*]|\d+\.)\s+(.*)$/) {
					my $text = $1;
					splice @$lines, 0, $k + 1;
					$push_item->($text);
					next;
				}
				last unless $lines->[$k] =~ /^ {3,}\S/;
				splice @$lines, 0, $k;
				my @sub;
				while (@$lines && ($lines->[0] =~ /^ {3,}/ || $lines->[0] =~ /^\s*$/)) {
					last if $lines->[0] =~ /^\s*$/
						&& !(@$lines > 1 && $lines->[1] =~ /^ {3,}\S/);
					my $x = shift @$lines;
					$x =~ s/^ {3}//;
					push @sub, $x;
				}
				push @{ $items[-1]{blocks} }, @{ parse_blocks(\@sub, $doc, $path) };
			}
			$take->(type => 'list', ordered => $ordered, items => \@items);
			next;
		}

		# footnote body: [^1]: the text
		if ($l =~ /^\[\^(\d+)\]:\s*(.*)$/) {
			my ($n, $first) = ($1, $2);
			my @buf = ($first);
			while (@$lines && $lines->[0] !~ /^\s*$/) { push @buf, shift @$lines }
			$take->(type => 'footnote', n => $n, lines => \@buf);
			next;
		}

		# prose blockquote
		if ($l =~ /^>\s?(.*)$/) {
			my @buf = ($1);
			while (@$lines && $lines->[0] =~ /^>\s?(.*)$/) {
				push @buf, $1;
				shift @$lines;
			}
			$take->(type => 'blockquote', lines => \@buf);
			next;
		}

		# standalone link line: => [label](ref)
		if ($l =~ /^=>\s*(.*)$/) {
			my @items = ($1);
			while (@$lines && $lines->[0] =~ /^=>\s*(.*)$/) {
				push @items, $1;
				shift @$lines;
			}
			$take->(type => 'links', items => \@items);
			next;
		}

		# paragraph: consecutive non-blank lines that start nothing else
		my @para = ($l);
		while (@$lines
			&& $lines->[0] !~ /^\s*$/
			&& $lines->[0] !~ /^(\@|:::|\#{1,4}\s|```|>>>|=>\s|-{4,}\s*$)/
			&& $lines->[0] !~ /^(?:[-*]|\d+\.)\s/)
		{
			push @para, shift @$lines;
		}
		$take->(type => 'para', lines => \@para);
	}
	return \@blocks;
}

# ------------------------------------------------------------------ inline
#
# Inline source becomes a node list once, and each emitter walks it. Nodes:
#   text, em, code, link{anchor,ref}, img{alt,ref}, cond{targets,neg,nodes}
sub parse_inline {
	my ($s) = @_;
	my @n;
	while (length $s) {
		# conditional span: {html: ...} / {!gopher: ...}
		# {html: …} / {!gopher: …}. Everything after the colon is content,
		# leading space included — the difference between one target's
		# parenthetical and another's is often exactly that space.
		if ($s =~ /\G\{(!?)([\w ]+):/gc) {
			my ($neg, $t) = ($1, $2);
			my $depth = 1;
			my $body  = '';
			while ($s =~ /\G(.)/gcs) {
				my $c = $1;
				$depth++ if $c eq '{';
				if ($c eq '}') { $depth--; last if $depth == 0 }
				$body .= $c;
			}
			push @n, { type => 'cond', targets => [split ' ', $t],
				neg => ($neg ? 1 : 0), nodes => parse_inline($body) };
			$s = substr($s, pos($s) // length $s);
			next;
		}
		# [[target:markup]] — verbatim output for one target, for the odd bit
		# of inline markup a text protocol has no equivalent for.
		if ($s =~ /\G\[\[(\w+):(.*?)\]\]/gc) {
			push @n, { type => 'rawspan', target => $1, text => $2 };
			$s = substr($s, pos($s)); next;
		}
		if ($s =~ /\G!\[([^\]]*)\]\(([^)]*)\)/gc) {
			push @n, { type => 'img', alt => $1, ref => $2 };
			$s = substr($s, pos($s)); next;
		}
		if ($s =~ /\G\[([^\]]*)\]\(([^)]*)\)/gc) {
			push @n, { type => 'link', anchor => $1, ref => $2 };
			$s = substr($s, pos($s)); next;
		}
		if ($s =~ /\G\[\^(\d+)\]/gc) {
			push @n, { type => 'fnref', n => $1 };
			$s = substr($s, pos($s)); next;
		}
		if ($s =~ /\G\*\*([^*]+)\*\*/gc) {
			push @n, { type => 'strong', nodes => parse_inline($1) };
			$s = substr($s, pos($s)); next;
		}
		# `code`, or `code`:lang for the web's language-tagged spans
		if ($s =~ /\G`([^`]+)`(?::(\w+))?/gc) {
			push @n, { type => 'code', text => $1, lang => $2 };
			$s = substr($s, pos($s)); next;
		}
		if ($s =~ /\G\*([^*]+)\*/gc) {
			push @n, { type => 'em', nodes => parse_inline($1) };
			$s = substr($s, pos($s)); next;
		}
		# _italic_ is <i> — typographic italics, as against *emphasis*. Both
		# are plain words on the retro targets; only the web distinguishes.
		if ($s =~ /\G_([^_]+)_/gc) {
			push @n, { type => 'i', text => $1 };
			$s = substr($s, pos($s)); next;
		}
		# ~a work's title~ is <cite>
		if ($s =~ /\G~([^~]+)~/gc) {
			push @n, { type => 'cite', text => $1 };
			$s = substr($s, pos($s)); next;
		}
		if ($s =~ /\G\\(.)/gc) {    # escape
			push @n, { type => 'text', text => $1 };
			$s = substr($s, pos($s)); next;
		}
		# plain run up to the next construct
		if ($s =~ /\G(.[^\\{!\[`*_~]*)/gcs) {
			push @n, { type => 'text', text => $1 };
			$s = substr($s, pos($s)); next;
		}
		last;
	}
	# merge adjacent text nodes so emitters see the longest runs
	my @m;
	for my $x (@n) {
		if (@m && $m[-1]{type} eq 'text' && $x->{type} eq 'text') {
			$m[-1]{text} .= $x->{text};
		} else { push @m, $x }
	}
	return \@m;
}

# ================================================================ rendering
sub want {    # does this block appear on this target?
	my ($t, $b) = @_;
	my $a = $b->{attrs};
	if (my $o = $a->{only}) { return 0 unless grep { $_ eq $t } split ' ', $o }
	if (my $s = $a->{skip}) { return 0 if     grep { $_ eq $t } split ' ', $s }
	return 0 if $b->{type} eq 'raw'
		&& ($b->{target} ne $t || ($b->{slot} // 'body') ne 'body');
	return 1;
}

sub resolve_link {    # -> (url, extra attrs) for this target, or undef if none
	my ($t, $ref, $doc) = @_;
	if ($ref =~ /^\@(\S+)$/) {
		my $row = $doc->{links}{$1} || $SITELINKS{$1}
			or die "triptych: $doc->{path}: undefined link \@$1\n";
		my $u = attr($t, 'url', $row);
		$u = $row->{$t} if exists $row->{$t};
		return (undef, $row) if !defined $u || $u eq '-';
		return ($u, $row);
	}
	return ($ref, {});
}

# ---- inline emitters. Each returns the text, and pushes any links that this
# protocol cannot keep inline onto @$defer for the block emitter to flush.
sub esc_html {
	my ($s) = @_;
	$s =~ s/&/&amp;/g;
	$s =~ s/</&lt;/g;
	$s =~ s/>/&gt;/g;
	return $s;
}

# The one typographic transform, and it is a rule this site already follows:
# a parenthetical em dash is thin space + em dash + thin space on the web, and
# plain spaces in text/plain, where a stray U+2009 is a mojibake risk. See
# unicodePedanticism.txt. The source carries the plain form; nothing else is
# substituted anywhere — what you type is what ships.
sub typo {
	my ($t, $s, $fm) = @_;
	# A page may say that its text copies use plain spaces where the web binds
	# a number to its unit: unicodePedanticism.txt asks for no stray non-ASCII
	# in the middle of a text/plain sentence.
	$s =~ s/\x{a0}/ /g if ($fm && ($fm->{"$t.nbsp"} // '') eq 'strip');
	return $s unless ($CONF{$t}{dash} // '') eq 'thin';
	$s =~ s/ \x{2014} /\x{2009}\x{2014}\x{2009}/g;
	return $s;
}

sub inline_out {
	my ($t, $nodes, $doc, $defer) = @_;
	my $fm = $doc->{fm};
	my $out = '';
	for my $n (@$nodes) {
		my $ty = $n->{type};
		if ($ty eq 'text') {
			$out .= $t eq 'html' ? esc_html(typo($t, $n->{text}, $fm))
			                     : typo($t, $n->{text}, $fm);
		} elsif ($ty eq 'em') {
			# Emphasis can contain a link; the asterisks survive into the retro
			# copies, the anchor inside them does not.
			my $inner = inline_out($t, $n->{nodes}, $doc, $defer);
			$out .= $t eq 'html' ? "<em>$inner</em>" : "*$inner*";
		} elsif ($ty eq 'i' || $ty eq 'cite') {
			my $tag = $ty eq 'i' ? 'i' : 'cite';
			$out .= $t eq 'html'
				? "<$tag>" . esc_html(typo($t, $n->{text}, $fm)) . "</$tag>"
				: $ty eq 'cite' ? '*' . $n->{text} . '*' : $n->{text};
		} elsif ($ty eq 'strong') {
			# Bold is a web-only distinction here: the retro copies say the
			# words without marking them, so the source marks them once.
			my $inner = inline_out($t, $n->{nodes}, $doc, $defer);
			$out .= $t eq 'html' ? "<strong>$inner</strong>" : $inner;
		} elsif ($ty eq 'fnref') {
			if ($t eq 'html') {
				$out =~ s/ $//;    # the marker attaches tight on the web
				$out .= qq{<sup><a href="#footnote-$n->{n}" }
					. qq{id="footnote-ref-$n->{n}">$n->{n}</a></sup>};
			} else {
				$out .= "[$n->{n}]";
			}
		} elsif ($ty eq 'code') {
			my $cls = $n->{lang} ? qq{ class="language-$n->{lang}"} : '';
			if ($t eq 'html') {
				$out .= "<code$cls>" . esc_html($n->{text}) . '</code>';
			} else {
				# `<div>` is a tag on the web and the word "div" in text/plain,
				# where angle brackets are how this site writes a bare URL.
				my $txt = $n->{text};
				$txt =~ s/^<(.+)>$/$1/ if ($CONF{$t}{code_angle} // '') eq 'strip';
				$out .= $txt;
			}
		} elsif ($ty eq 'rawspan') {
			$out .= $n->{text} if $n->{target} eq $t;
		} elsif ($ty eq 'cond') {
			my $hit = grep { $_ eq $t } @{ $n->{targets} };
			$hit = !$hit if $n->{neg};
			$out .= inline_out($t, $n->{nodes}, $doc, $defer) if $hit;
		} elsif ($ty eq 'link' || $ty eq 'img') {
			my $anchor = $ty eq 'img' ? $n->{alt} : $n->{anchor};
			my ($url, $row) = resolve_link($t, $n->{ref}, $doc);
			if (!defined $url) {    # dropped on this target: prose stays
				$out .= inline_out($t, parse_inline($anchor), $doc, $defer);
				next;
			}
			my $mode = attr($t, 'mode', $row, $CONF{$t}) || 'inline';
			if ($t eq 'html' && $ty eq 'img') {
				$out .= sprintf '<img src="%s" alt="%s">', $url, esc_html($anchor);
			} elsif ($mode eq 'inline') {
				$out .= sprintf '<a href="%s">%s</a>', $url,
					inline_out($t, parse_inline($anchor), $doc, $defer);
			} elsif ($mode eq 'after') {
				# gopher sometimes sets the URL right after the words it
				# belongs to, mid-sentence, rather than after the block.
				$out .= inline_out($t, parse_inline($anchor), $doc, $defer)
					. " <$url>";
			} else {
				# defer (gemini) / trail (gopher): the words stay in the prose
				# and the link follows the block.
				$out .= inline_out($t, parse_inline($anchor), $doc, $defer);
				my $label = attr($t, 'label', $row);
				$label = $anchor unless defined $label;
				$label = inline_out($t, parse_inline($label), $doc, []);
				push @$defer, { url => $url, label => $label, mode => $mode,
					col => attr($t, 'col', $row) };
			}
		}
	}
	return $out;
}

# ---- the deferred-link flush, which is where the two retro protocols differ
# most from each other. gemini gets its own => lines, column-aligned across
# the group; gopher gets "label: <url>", with local selectors left bare.
sub flush_defer {
	my ($t, $defer, $battrs) = @_;
	return () unless @$defer;
	my @out;
	if ($t eq 'gemini') {
		my $gap = attr('gemini', 'gap', $battrs, $CONF{gemini}) // 3;
		my $floor = attr('gemini', 'col', $battrs) // 0;
		my $align = attr('gemini', 'align', $battrs) // 'group';
		my $max = 0;
		# align=line gives each line its own gap instead of a shared column
		for (@$defer) { $max = length($_->{url})
			if $align eq 'group' && length($_->{url}) > $max }
		# an explicit column wins over the group's natural width
		my $col = $floor ? $floor : $max + $gap;
		for my $d (@$defer) {
			my $c = $d->{col} // $col;
			# A column set by hand is taken as given; it only moves when a URL
			# would not fit inside it.
			$c = length($d->{url}) + $gap if length($d->{url}) + 1 > $c;
			push @out, sprintf '=> %-*s%s', $c, $d->{url}, $d->{label};
		}
	} else {    # gopher
		for my $d (@$defer) {
			my $u = $d->{url};
			$u = "<$u>" if $u =~ m{^\w+://};    # absolute: angle-bracketed
			push @out, $d->{mode} eq 'bare' ? $u : "$d->{label}: $u";
		}
	}
	@$defer = ();
	return @out;
}

# ---- width, for gopher's heading underlines. Combining marks and the
# zero-width joiners in the emoji take no columns; everything else here is
# single-width, which is true of this site's prose.
sub width {
	my ($s) = @_;
	$s =~ s/[\x{0300}-\x{036F}\x{200B}-\x{200D}\x{FE0F}]//g;
	return length $s;
}

my %UNDERLINE = (1 => '=', 2 => '-', 3 => '~', 4 => '.');

# Greedy wrap, for the one place a target reflows text: gopher indents and
# wraps block quotes, where gemini keeps the author's single long line.
sub wrap_lines {
	my ($text, $width, $indent) = @_;
	my @out;
	my $cur = '';
	# Split on single spaces, so a double space inside a quoted passage (the
	# RFCs use them between sentences) survives the rewrap.
	for my $w (split / /, $text) {
		if ($cur eq '' && !@out) { $cur = $w; next }
		if ($cur eq '') { $cur = $w; next }
		if (width($cur) + 1 + width($w) + length($indent) <= $width) { $cur .= " $w" }
		else { push @out, $indent . $cur; $cur = $w }
	}
	push @out, $indent . $cur if $cur ne '';
	return @out;
}

# A table is authored once as pipe rows. HTML gets a real <table>; the retro
# targets get the same cells column-aligned inside a preformatted block, which
# is what both of them already hold today.
sub table_out {
	my ($t, $b, $doc) = @_;
	my $a    = $b->{attrs};
	my @rows = @{ $b->{rows} };
	my $sep  = $b->{sep};
	my @out;
	if ($t eq 'html') {
		my $rowhead = attr('html', 'rowheader', $a);
		push @out, '<table>';
		my $start = 0;
		if (defined $sep && $sep == 1) {    # a header row, then the body
			push @out, '  <thead>',
				'    <tr>' . join('', map { '<th>' . inline_out($t, parse_inline($_), $doc, []) . '</th>' } @{ $rows[0] }) . '</tr>',
				'  </thead>';
			$start = 1;
		}
		push @out, '  <tbody>';
		for my $r (@rows[ $start .. $#rows ]) {
			my @c = @$r;
			my $line = '    <tr>';
			if ($rowhead) {
				$line .= '<th scope="row">' . inline_out($t, parse_inline(shift @c), $doc, []) . '</th>';
			}
			$line .= join '', map { '<td>' . inline_out($t, parse_inline($_), $doc, []) . '</td>' } @c;
			push @out, $line . '</tr>';
		}
		push @out, '  </tbody>', '</table>';
		return @out;
	}
	# retro: align the columns, and redraw a --- separator as dashes under the
	# header cells it separates.
	my $gap = attr($t, 'gap', $a) // 1;
	my @w;
	for my $r (@rows) {
		for my $i (0 .. $#$r) {
			my $s = inline_out($t, parse_inline($r->[$i]), $doc, []);
			$w[$i] = width($s) if !defined $w[$i] || width($s) > $w[$i];
		}
	}
	# A prose column can be wider than the screen: `@ wrap=N` wraps the last
	# column and hangs its continuation lines under itself.
	my $wrap = attr($t, 'wrap', $a);
	my $ind_n = attr($t, 'indent', $a) // 4;
	my @body;
	for my $i (0 .. $#rows) {
		my @c = map { inline_out($t, parse_inline($_), $doc, []) } @{ $rows[$i] };
		my @f;
		for my $j (0 .. $#c) {
			push @f, $j == $#c ? $c[$j] : $c[$j] . (' ' x ($w[$j] - width($c[$j]) + $gap));
		}
		if ($wrap && @c > 1) {
			my $colstart = 0;
			$colstart += $w[$_] + $gap for 0 .. $#c - 1;
			my @wrapped = wrap_lines($c[-1], $wrap - $ind_n - $colstart, '');
			$f[-1] = shift @wrapped;
			push @body, join('', @f);
			push @body, (' ' x $colstart) . $_ for @wrapped;
		} else {
			push @body, join('', @f);
		}
		if (defined $sep && $sep == $i + 1) {
			my @d;
			for my $j (0 .. $#c) {
				my $dash = '-' x width($c[$j]);
				push @d, $j == $#c ? $dash : $dash . (' ' x ($w[$j] - width($c[$j]) + $gap));
			}
			push @body, join('', @d);
		}
	}
	my $ind = ' ' x (attr($t, 'indent', $a) // 4);
	@body = map { $_ eq '' ? '' : $ind . $_ } @body;
	return $t eq 'gemini' ? ('```', @body, '```') : @body;
}

# `@ pair=1`: list items written as "term | gloss" are set with an em dash on
# the web and a parenthesis in the text protocols, which is how this site
# already punctuates its definition lists in each medium.
sub pair_text {
	my ($t, $text, $a) = @_;
	my $kind = attr($t, 'pair', $a) or return $text;
	my ($term, $gloss) = split / \| /, $text, 2;
	return $text unless defined $gloss;
	return $t eq 'html' ? "$term \x{2014} $gloss" : "$term ($gloss)"
		if $kind eq '1';
	return $text;
}

sub blocks_out {
	my ($t, $doc, $blocks, $fm) = @_;
	my @out;
	my $prev_heading = 0;
	for my $b (@$blocks) {
		next unless want($t, $b);
		my $a = $b->{attrs};
		my @defer;
		my @chunk;

		if ($b->{type} eq 'raw') {
			# Raw means raw: the author wrote the exact bytes, indentation
			# included, so the page's body indent is not applied on top.
			@chunk = map { "\0" . $_ } @{ $b->{lines} };
		} elsif ($b->{type} eq 'heading') {
			my $lvl = attr($t, 'level', $a) // $b->{level};
			my $txt = inline_out($t, parse_inline($b->{text}), $doc, \@defer);
			if ($t eq 'html') {
				my $cls = attr('html', 'class', $a);
				push @chunk, sprintf '<h%d%s>%s</h%d>', $lvl,
					($cls ? qq{ class="$cls"} : ''), $txt, $lvl;
			} elsif ($t eq 'gemini') {
				push @chunk, ('#' x $lvl) . ' ' . $txt;
			} elsif ($fm && $fm->{'gopher.map'}) {
				push @chunk, $txt;
			} else {
				push @chunk, $txt, $UNDERLINE{$lvl} x width($txt);
			}
		} elsif ($b->{type} eq 'para') {
			my $txt = join "\n", map {
				inline_out($t, parse_inline($_), $doc, \@defer)
			} @{ $b->{lines} };
			if ($t eq 'html') {
				my $cls = attr('html', 'class', $a);
				$txt = "<em>$txt</em>" if attr('html', 'em', $a);
				push @chunk, sprintf '<p%s>%s</p>',
					($cls ? qq{ class="$cls"} : ''), $txt;
			} elsif (my $w = attr($t, 'wrap', $a)) {
				push @chunk, wrap_lines($txt, $w, '');
			} else {
				push @chunk, split /\n/, $txt, -1;
			}
		} elsif ($b->{type} eq 'footnote') {
			# One sentence, two shapes: a doc-footnote aside with a back-link on
			# the web, a bracketed number in the text protocols.
			my $n = $b->{n} // 1;
			my $txt = inline_out($t, parse_inline(join ' ', @{ $b->{lines} }), $doc, \@defer);
			if ($t eq 'html') {
				push @chunk, '<hr>', '',
					qq{<aside id="footnote-$n" role="doc-footnote">},
					qq{  <p><sup>$n</sup> $txt <a href="#footnote-ref-$n">\x{21a9}</a></p>},
					'</aside>';
			} else {
				push @chunk, "[$n] $txt";
			}
		} elsif ($b->{type} eq 'list') {
			my @items = @{ $b->{items} };
			if ($t eq 'html') {
				my $tag = $b->{ordered} ? 'ol' : 'ul';
				my $cls = attr('html', 'class', $a);
				push @chunk, "<$tag" . ($cls ? qq{ class="$cls"} : '') . '>';
				for my $it (@items) {
					if ((attr('html', 'pair', $a) // '') eq 'labels') {
						my ($term, $gloss) = split / \| /, $it->{text}, 2;
						push @chunk, sprintf
							'  <li><span class="label">%s</span> %s</li>', $term,
							inline_out($t, parse_inline($gloss), $doc, \@defer);
						next;
					}
					my $txt = inline_out($t, parse_inline(pair_text($t, $it->{text}, $a)), $doc, \@defer);
					if (@{ $it->{blocks} }) {
						push @chunk, '  <li>', "    <p>$txt</p>",
							(map { "    $_" } grep { $_ ne '' }
								@{ blocks_out($t, $doc, $it->{blocks}, $fm) }),
							'  </li>';
					} else {
						push @chunk, "  <li>$txt</li>";
					}
				}
				push @chunk, "</$tag>";
			} elsif ((attr($t, 'pair', $a) // '') eq 'labels') {
				# a contact block: aligned columns, no bullets
				my @terms = map { (split / \| /, $_->{text}, 2)[0] } @items;
				my $w = 0;
				for (@terms) { $w = width($_) if width($_) > $w }
				for my $it (@items) {
					my ($term, $gloss) = split / \| /, $it->{text}, 2;
					my $g = inline_out($t, parse_inline($gloss), $doc, \@defer);
					push @chunk, $term . (' ' x ($w - width($term) + 1)) . $g;
				}
			} else {
				my $i = 0;
				my $li = ' ' x (attr($t, 'indent', $a) // 0);
				for my $it (@items) {
					my $txt = inline_out($t, parse_inline(pair_text($t, $it->{text}, $a)), $doc, \@defer);
					$i++;
					push @chunk, $li . ($t eq 'gemini' && !$b->{ordered} ? "* $txt"
						: $b->{ordered} ? "$i. $txt" : "- $txt");
					if (@{ $it->{blocks} }) {
						push @chunk, '', @{ blocks_out($t, $doc, $it->{blocks}, $fm) };
						push @chunk, '' unless $it == $items[-1];
					}
				}
			}
		} elsif ($b->{type} eq 'postlist') {
			my $host = $CONF{gopher}{host};
			my $port = $CONF{gopher}{port};
			my @rows;
			for my $pp (@{ $doc->{posts} }) {
				my $f = $pp->{fm};
				my $ed = ($f->{updated} && $f->{updated} ne $f->{date})
					? $f->{updated} : '';
				my $title = $t eq 'html'
					? inline_out($t, parse_inline($f->{title_markup} // $f->{title}), $doc, [])
					: $f->{title};
				if ($t eq 'html') {
					my $sep = ' <span class="sep">|</span> ';
					my $line = sprintf '<li><a href="%s.html">%s</a>%s<time datetime="%s">%s</time>',
						$f->{id}, $title, $sep, $f->{date}, $f->{date};
					$line .= sprintf '%sedited <time datetime="%s">%s</time>', $sep, $ed, $ed if $ed;
					push @rows, '  ' . $line . '</li>';
				} elsif ($t eq 'gemini') {
					push @rows, { url => "$f->{id}.gmi",
						label => "$title | $f->{date}" . ($ed ? " | edited $ed" : '') };
				} else {
					push @rows, sprintf "0%s\t/blog/%s.txt\t%s\t%s",
						"$title | $f->{date}" . ($ed ? " | edited $ed" : ''),
						$f->{id}, $host, $port;
				}
			}
			if ($t eq 'html') {
				my $cls = attr('html', 'class', $a);
				push @chunk, '<ul' . ($cls ? qq{ class="$cls"} : '') . '>', @rows, '</ul>';
			} elsif ($t eq 'gemini') {
				push @defer, { url => $_->{url}, label => $_->{label}, mode => 'defer',
					col => undef } for @rows;
			} else {
				push @chunk, @rows;
				# A post may contribute its own row to the index — the gopher
				# copy of an illustrated post links the image from here, since
				# a text/plain page cannot show it inline.
				for my $pp (@{ $doc->{posts} }) {
					my $x = $pp->{fm}{'gopher.gophermap_extra'} or next;
					push @chunk, $x;
				}
			}
		} elsif ($b->{type} eq 'table') {
			@chunk = table_out($t, $b, $doc);
		} elsif ($b->{type} eq 'pre') {
			my @l = @{ $b->{lines} };
			# Source is held unindented. HTML prints it flush inside <pre>
			# (with a language class when the fence names one, bare otherwise);
			# both retro targets indent it, which is what sets a preformatted
			# block apart from prose when there is no other way to mark it.
			if ($t eq 'html') {
				my $cls  = attr('html', 'class', $a);
				my @e = map { esc_html($_) } @l;
				if ($cls) {
					$e[0]  = qq{<pre class="$cls">} . $e[0];
					$e[-1] = $e[-1] . '</pre>';
				} elsif ($b->{lang}) {
					$e[0]  = qq{<pre><code class="language-$b->{lang}">} . $e[0];
					$e[-1] = $e[-1] . '</code></pre>';
				} else {
					$e[0]  = '<pre>' . $e[0];
					$e[-1] = $e[-1] . '</pre>';
				}
				# Only the opening line takes the page's indent: everything
				# inside <pre> is significant whitespace, so the rest is
				# flagged flush with \0 for the template's indenter.
				$e[$_] = "\0" . $e[$_] for 1 .. $#e;
				push @chunk, @e;
			} else {
				my $ind = ' ' x (attr($t, 'indent', $a) // 4);
				my $tab = $CONF{$t}{tabs};
				my @i = map {
					my $x = $_;
					# a leading tab is a 4-column indent in the text copies
					$x =~ s/^(\t+)/'    ' x length($1)/e if $tab;
					$x eq '' ? '' : $ind . $x;
				} @l;
				push @chunk, $t eq 'gemini' ? ('```', @i, '```') : @i;
			}
		} elsif ($b->{type} eq 'blockquote') {
			my $txt = inline_out($t, parse_inline(join ' ', @{ $b->{lines} }), $doc, \@defer);
			if ($t eq 'html') {
				push @chunk, '<blockquote>', "  <p>$txt</p>", '</blockquote>';
			} elsif ($t eq 'gemini') {
				push @chunk, "> $txt";
			} else {
				my $w = attr('gopher', 'wrap', $a, $CONF{gopher}) // 74;
				my $ind = ' ' x (attr('gopher', 'indent', $a) // 2);
				push @chunk, wrap_lines($txt, $w, $ind);
			}
		} elsif ($b->{type} eq 'quote') {
			my @l = @{ $b->{lines} };
			if ($t eq 'html') {
				push @chunk, '<blockquote>';
				my @stanza;
				my $emit = sub {
					return unless @stanza;
					push @chunk, '  <p>' . join("<br>\n  ", @stanza) . '</p>';
					@stanza = ();
				};
				for my $x (@l) {
					if ($x =~ /^\s*$/) { $emit->() }
					else { my $y = $x; $y =~ s/^\s{0,4}//; push @stanza, esc_html($y) }
				}
				$emit->();
				push @chunk, '</blockquote>';
			} elsif ($t eq 'gemini') {
				push @chunk, '```', @l, '```';
			} else {
				push @chunk, @l;
			}
		} elsif ($b->{type} eq 'rule') {
			push @chunk, $t eq 'html' ? '<hr>' : $t eq 'gemini' ? '---' : '-' x 80;
		} elsif ($b->{type} eq 'links') {
			# A block of standalone links. On html a <ul> of anchors (or a run
			# of <p>s, or "term | gloss" items); on the retro targets they are
			# already in each protocol's native shape.
			my @l;
			# A copy, not the loop's alias: this walks the same block once per
			# target, and rewriting an entry in place would strip its scope
			# before the next target ever saw it.
			for my $entry (@{ $b->{items} }) {
				my $it = $entry;
				# an entry may be narrowed to some targets, or given verbatim
				if ($it =~ /^only=(\S+)\s+(.*)$/) {
					my ($tt, $rest) = ($1, $2);
					next unless grep { $_ eq $t } split /,/, $tt;
					$it = $rest;
				}
				if ($it =~ /^raw=(\w+) (.*)$/) {
					push @l, $2 if $1 eq $t;
					next;
				}
				my ($anchor, $ref) = $it =~ /^\[(.*)\]\((.*)\)$/
					or die "triptych: $doc->{path}: bad link line: $it\n";
				my ($url, $row) = resolve_link($t, $ref, $doc);
				next unless defined $url;
				my $label = attr($t, 'label', $row);
				$label = $anchor unless defined $label;
				$label = inline_out($t, parse_inline($label), $doc, []);
				if ($t eq 'html') {
					# html.pair: the label reads "term | gloss", and only the
					# term is the link — the shape this site's lists already use.
					if (attr('html', 'pair', $a) && $label =~ /^(.*?) \| (.*)$/) {
						push @l, sprintf
							'  <li><a href="%s">%s</a> <span class="sep">|</span> %s</li>',
							$url, $1, $2;
					} elsif ((attr('html', 'as', $a) // '') eq 'p') {
						push @l, sprintf '<p><a href="%s">%s</a></p>', $url, $label;
					} else {
						push @l, sprintf '  <li><a href="%s">%s</a></li>', $url, $label;
					}
				} elsif ($fm && $fm->{'gopher.map'} && $t eq 'gopher') {
					# a gophermap row: a menu item, typed by what it points at.
					# The item type carries what a "/0/" prefix says in a URL,
					# so a row may give its bare selector separately.
					$url = attr($t, 'sel', $row) // $url;
					my $type = $url =~ m{^\w+://} ? 'h' : $url =~ /\.txt$/ ? '0' : '1';
					my $sel = $type eq 'h' ? "URL:$url" : $url;
					push @l, sprintf "%s%s\t%s\t%s\t%s", $type, $label, $sel,
						$CONF{gopher}{host}, $CONF{gopher}{port};
				} else {
					# A standalone link line still honours a row's own mode,
					# so a link the gopher copy prints bare stays bare.
					my $mode = attr($t, 'mode', $row)
						|| ($t eq 'gemini' ? 'defer' : 'label');
					push @defer, { url => $url, label => $label, mode => $mode,
						col => attr($t, 'col', $row) };
				}
			}
			if (@l && ($t ne 'html' || (attr('html', 'as', $a) // '') ne 'p')) {
				if ($t eq 'html') {
					my $cls = attr('html', 'class', $a);
					push @chunk, '<ul' . ($cls ? qq{ class="$cls"} : '') . '>',
						@l, '</ul>';
				} else {
					push @chunk, @l;
				}
			} elsif (@l) {
				push @chunk, @l;
			}
		} else {
			die "triptych: $doc->{path}: unhandled block type $b->{type}\n";
		}

		my $all_bare = @defer && !grep { $_->{mode} ne 'bare' } @defer;
		my @links = flush_defer($t, \@defer, $a);
		if (@links) {
			# A bare URL line belongs to the sentence above it, so it sits
			# tight; a labelled one is its own thing and gets a blank line.
			push @chunk, '' if @chunk && $b->{type} ne 'links' && !$all_bare;
			push @chunk, @links;
		}
		next unless @chunk;

		# Blank line between blocks. HTML keeps a heading tight against a list
		# it introduces (and, on pages that set html.tight, against anything),
		# which is how the hand-written pages are punctuated today.
		if (@out) {
			# html.tight: "all" runs the whole page without blank lines
			# between blocks; "headings" only closes the gap under a heading.
			# Without it, a heading still sits tight against a list.
			my $mode = ($fm && $fm->{'html.tight'}) || '';
			my $tight = $t eq 'html' && ($mode eq 'all'
				|| ($mode eq 'sections' && $b->{type} ne 'heading')
				|| ($prev_heading && ($b->{type} eq 'list' || $mode eq 'headings')));
			# `@ tight=1` closes the gap before a block that belongs to the
			# one above it — a link line under its own lead-in, say.
			$tight ||= attr($t, 'tight', $a);
			# `@ blank=N` widens the gap where a page leaves one
			my $n = $tight ? 0 : (attr($t, 'blank', $a) // 1);
			push @out, ('') x $n;
		}
		push @out, @chunk;
		$prev_heading = ($b->{type} eq 'heading') ? 1 : 0;
	}
	return \@out;
}

sub render_body {
	my ($t, $doc) = @_;
	my $blocks = $doc->{blocks};

	# `@ join=1` on a preformatted block: the web shows a command and its
	# output as two <pre>s (only the first is a shell snippet worth
	# highlighting), while the text protocols show one screenful. Joining
	# happens here so the source keeps the two apart and says so once.
	if ($t ne 'html') {
		my @m;
		for my $b (@$blocks) {
			if (@m && $m[-1]{type} eq 'pre' && $m[-1]{attrs}{join}
				&& $b->{type} eq 'pre' && want($t, $b))
			{
				push @{ $m[-1]{lines} }, '', @{ $b->{lines} };
				next;
			}
			my %copy = %$b;
			$copy{lines} = [ @{ $b->{lines} } ] if $b->{lines};
			push @m, \%copy;
		}
		$blocks = \@m;
	}
	return blocks_out($t, $doc, $blocks, $doc->{fm});
}

# ---- raw head slots are pulled out separately: they belong in the template's
sub raw_slot {
	my ($t, $doc, $slot) = @_;
	my @out;
	for my $b (@{ $doc->{blocks} }) {
		next unless $b->{type} eq 'raw' && $b->{target} eq $t;
		next unless ($b->{slot} // 'body') eq $slot;
		push @out, @{ $b->{lines} };
	}
	return @out ? join("\n", @out) : '';
}

# ================================================================ templates
#
# {{key}} substitutes, {{?key}}...{{/key}} keeps its contents only when key is
# non-empty, and {{indent:key}} re-indents a multi-line value to the column the
# placeholder sits at. Anything else in the file is chrome, emitted verbatim —
# which is how every explanatory comment and SSI conditional in the current
# pages survives untouched.
sub render_template {
	my ($path, $vars) = @_;
	open my $fh, '<:encoding(UTF-8)', $path or die "triptych: $path: $!\n";
	local $/;
	my $t = <$fh>;
	close $fh;

	1 while $t =~ s{\{\{\?(\w+)\}\}(.*?)\{\{/\1\}\}}{
		(defined $vars->{$1} && $vars->{$1} ne '') ? $2 : ''
	}ges;
	# Collapse the gaps an absent section left behind. Done HERE, before any
	# content is substituted in, so a deliberate run of blank lines inside a
	# preformatted block survives.
	$t =~ s/\n{3,}/\n\n/g;
	$t =~ s{^([ \t]*)\{\{indent:(\w+)\}\}$}{
		my ($ind, $k) = ($1, $2);
		my $v = $vars->{$k} // '';
		$v eq '' ? '' : join "\n",
			map { /^\0(.*)$/s ? $1 : $_ eq '' ? '' : $ind . $_ } split /\n/, $v;
	}gme;
	$t =~ s{\{\{(\w+)\}\}}{ defined $vars->{$1} ? $vars->{$1} : '' }ge;
	return $t;
}

# ================================================================== outputs
sub out_path {
	my ($t, $doc) = @_;
	my $id   = $doc->{fm}{id};
	my $kind = $doc->{fm}{kind};
	my $conf = $CONF{$t};
	my $sub  = $kind eq 'post' ? ($conf->{postdir} // '') : '';
	if ($t eq 'html') {
		my $name = $kind eq 'bloglist' ? 'blog' : $id;
		return "$conf->{out}$name.html";
	}
	if ($t eq 'gemini') {
		my $name = $kind eq 'index' ? 'index' : $kind eq 'bloglist' ? 'blog/index' : "$sub$id";
		return "$conf->{out}$name.gmi";
	}
	my $name = $kind eq 'index' ? 'gophermap'
		: $kind eq 'bloglist' ? 'blog/gophermap' : "$sub$id.txt";
	return "$conf->{out}$name";
}

# The 88x31 wall is written by badgeBuild.pl AFTER this runs (preCommit.sh
# order), so triptych must not clobber it: the existing file's block is carried
# through verbatim, and a page that has none gets the empty markers for
# badgeBuild to fill on the next commit.
my $BADGES_EMPTY = '<!-- badges:start GENERATED by assetsBuild/badgeBuild.pl'
	. " from webBadges.csv - do not edit -->\n    <!-- badges:end -->";

sub badges_block {
	my ($path) = @_;
	open my $fh, '<:encoding(UTF-8)', $path or return $BADGES_EMPTY;
	local $/;
	my $cur = <$fh>;
	close $fh;
	return $1 if $cur =~ /(<!-- badges:start.*?<!-- badges:end -->)/s;
	return $BADGES_EMPTY;
}

# A region another generator owns, carried through from the file on disk.
sub preserved_block {
	my ($path, $name) = @_;
	open my $fh, '<:encoding(UTF-8)', $path or return '';
	local $/;
	my $cur = <$fh>;
	close $fh;
	return $1 if $cur =~ /(  <!-- \Q$name\E:start.*?  <!-- \Q$name\E:end -->)/s;
	return '';
}

sub render_page {
	my ($t, $doc, $posts, $outpath) = @_;
	my $fm   = $doc->{fm};
	my $kind = $fm->{kind};

	# The blog index's entries are not authored anywhere: they are the post
	# set, in each protocol's own idiom. Adding a post is dropping a file in.
	$doc = { %$doc, posts => $posts };

	# The page title is one fact, in three shapes. HTML's template owns its
	# <h1> (it carries the pangram badge and a flex class); the retro targets
	# have no template hook for it, so the heading is injected as a block and
	# goes through the normal heading path — which is what gives gopher an
	# underline of the right width without anything hand-counting it.
	if ($t ne 'html' || $kind ne 'post') {
		my $ht = $fm->{"$t.title"} // $fm->{title_markup} // $fm->{title};
		$doc = { %$doc, blocks => [
			{ type => 'heading', level => 1, text => $ht, attrs => {} },
			@{ $doc->{blocks} },
		] } if defined $ht && !$fm->{"$t.notitle"};
	}

	my @bodylines = @{ render_body($t, $doc) };
	if ($t eq 'gopher' && $fm->{'gopher.map'}) {
		# A gophermap is a menu: text that is not a link is an "i" info row,
		# carrying the three filler fields gophernicus expects.
		@bodylines = map { /\t/ ? $_ : "i$_\tfake\t(NULL)\t0" } @bodylines;
	}
	my $body = join "\n", @bodylines;
	# Target-scoped front matter is what the template asks for by its bare
	# name: html.style reaches templates/html/*.tpl as {{style}} and reaches
	# no other target at all.
	my %scoped;
	for my $k (keys %$fm) {
		next unless $k =~ /^\Q$t\E\.(.+)$/;
		$scoped{$1} = $fm->{$k};
	}
	my %vars = (
		%$fm,
		%scoped,
		url        => "https://dreamstation.systems/personal/"
			. ($kind eq 'bloglist' ? 'blog' : $fm->{id}) . '.html',
		body       => $body,
		head_extra => raw_slot($t, $doc, 'head'),
		year       => (localtime)[5] + 1900,
	);
	$vars{title_esc}   = esc_html($fm->{title} // '');
	$vars{title_class} = $fm->{'html.title_class'} // "$fm->{id}-title";
	# The h1 may carry inline markup the <title> and og: tags cannot.
	$vars{title_h1} = inline_out('html',
		parse_inline($fm->{title_markup} // $fm->{title} // ''), $doc, []);
	$vars{badges} = badges_block($outpath) if $t eq 'html';
	# Same treatment as the badge wall: makeMeta.py owns this block, and runs
	# after triptych does, so what is already on disk is carried through.
	$vars{blogld} = preserved_block($outpath, 'blogld') if $t eq 'html';
	$vars{edited} = ($fm->{updated} && $fm->{updated} ne ($fm->{date} // ''))
		? $fm->{updated} : '';
	my $tpl = "$ROOT/templates/$t/" . ($fm->{"$t.template"} // $kind) . '.tpl';
	$tpl = "$ROOT/templates/$t/page.tpl" unless -f $tpl;
	return render_template($tpl, \%vars);
}

# =================================================================== driver
my @docs;
for my $path (sort glob("$ROOT/content/*.tri $ROOT/content/post/*.tri")) {
	my $doc = parse_file($path);
	die "triptych: $path: no id\n"   unless $doc->{fm}{id};
	die "triptych: $path: no kind\n" unless $doc->{fm}{kind};
	push @docs, $doc;
}
my @posts = sort { $b->{fm}{date} cmp $a->{fm}{date} }
	grep { $_->{fm}{kind} eq 'post' } @docs;

# The post link table is implicit: [text](@post:id) resolves per target, so no
# page ever spells out another page's three URLs.
for my $p (@posts) {
	my $id = $p->{fm}{id};
	$SITELINKS{"post:$id"} = {
		html   => "$id.html",
		gemini => "$id.gmi",
		gopher => "/blog/$id.txt",
	};
}

# --source-of: which .tri produced this output file, if any. Lets the other
# pre-commit steps tell a generated page from a hand-written one without a
# banner comment in the output (which would change every file it touches).
if ($SOURCE_OF ne '') {
	my $want = $SOURCE_OF;
	$want =~ s{^\./}{};
	$want =~ s{^\Q$ROOT\E/}{};
	for my $doc (@docs) {
		for my $t (split ' ', ($doc->{fm}{targets} // join ' ', @TARGETS)) {
			next unless out_path($t, $doc) eq $want;
			my $src = $doc->{path};
			$src =~ s{^\Q$ROOT\E/}{};
			print "$src\n";
			exit 0;
		}
	}
	exit 1;
}

my ($written, $differ, $same) = (0, 0, 0);
for my $doc (@docs) {
	next if %only && !$only{ $doc->{fm}{id} };
	my @t = split ' ', ($doc->{fm}{targets} // join ' ', @TARGETS);
	for my $t (@t) {
		my $path = "$ROOT/" . out_path($t, $doc);
		my $out  = render_page($t, $doc, \@posts, $path);
		if ($LIST) {
			printf "%-46s <- %s\n", out_path($t, $doc), basename($doc->{path});
			next;
		}
		if ($CHECK) {
			my $cur = '';
			if (open my $fh, '<:encoding(UTF-8)', $path) { local $/; $cur = <$fh>; close $fh }
			if ($cur eq $out) { $same++; next }
			$differ++;
			print "DIFFERS: " . out_path($t, $doc) . "\n";
			my $tmp = "/tmp/triptych.$$";
			open my $fh, '>:encoding(UTF-8)', $tmp or die $!;
			print $fh $out;
			close $fh;
			system('diff', '-u', $path, $tmp);
			unlink $tmp;
			next;
		}
		make_path(dirname($path));
		open my $fh, '>:encoding(UTF-8)', $path or die "triptych: $path: $!\n";
		print $fh $out;
		close $fh;
		$written++;
	}
}

if ($CHECK) {
	print "triptych --check: $same identical, $differ differing\n";
	exit($differ ? 1 : 0);
} elsif (!$LIST) {
	print "triptych: wrote $written files\n";
}
