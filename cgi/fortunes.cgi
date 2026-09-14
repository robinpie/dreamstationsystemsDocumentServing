#!/usr/bin/perl
#
# fortunes.cgi — add or remove fortunes, create fortune files, or download
# them all as a tarball.
#
# Deployed to /srv/cgi/fortunes.cgi by promoteSite.sh; served as the whole of
# https://fortunes.dreamstation.systems/ via fcgiwrap, behind basic auth in
# the nginx vhost (this script does no auth of its own). Runs as www-data.
#
# The data lives in /srv/http/fortunes/, which is NOT in the repo: promote
# carves it out of both its --delete and its chown/chmod, because www-data
# must be able to write there. See ~/configNotes/fortunes.txt.
#
#   GET  /                 the main page
#   POST /                 [action=add&]file=<name>&fortune=<text>  append
#   GET  /?remove=<name>   list that file's fortunes with checkboxes
#   POST /                 action=remove&file=<name>&sum=<sha1>&n=<i>&n=<j>...
#   POST /                 action=create&name=<name>  new empty fortune file
#   GET  /?download        fortunes.tar.gz of the whole directory

use strict;
use warnings;
use Digest::SHA qw(sha1_hex);
use Fcntl qw(O_WRONLY O_CREAT O_EXCL);

my $DIR  = '/srv/http/fortunes';
my $SELF = 'https://fortunes.dreamstation.systems';
my $LAST = "$DIR/.last-added";    # "<epoch> <file>", written on every add

# Fortune file names; the same pattern is the path-traversal guard for every
# file name that comes in from a request, and keeps .dat and dotfiles out.
my $NAME_RE = qr/^[A-Za-z0-9_-]{1,64}$/;

sub fortune_files {
	opendir(my $dh, $DIR) or return ();
	my @f = sort grep { /$NAME_RE/ && -f "$DIR/$_" } readdir $dh;
	closedir $dh;
	return @f;
}

sub html_escape {
	my $s = shift;
	$s =~ s/&/&amp;/g; $s =~ s/</&lt;/g; $s =~ s/>/&gt;/g; $s =~ s/"/&quot;/g;
	return $s;
}

sub url_decode {
	my $s = shift // '';
	$s =~ tr/+/ /;
	$s =~ s/%([0-9A-Fa-f]{2})/chr hex $1/ge;
	return $s;
}

# "Last fortune added", in Central Time. Read from .last-added, which only an
# add writes, so removing fortunes or creating a file does not move it. If that
# file is missing, fall back to the newest mtime among the fortune files.
sub last_added {
	my ($when, $newest);
	if (open my $fh, '<', $LAST) {
		(my $l = <$fh> // '') =~ /^(\d+) (\S+)/ and ($when, $newest) = ($1, $2);
		close $fh;
	}
	unless (defined $when) {
		for my $f (fortune_files()) {
			my $m = (stat "$DIR/$f")[9] // next;
			($newest, $when) = ($f, $m) if !defined $when || $m > $when;
		}
	}
	return '' unless defined $when;
	require POSIX;
	local $ENV{TZ} = 'America/Chicago';
	POSIX::tzset();
	my $ts = POSIX::strftime('%Y-%m-%d %H:%M:%S %Z', localtime $when);
	return '<p>Last fortune added: ' . html_escape("$ts ($newest)") . "</p>\n";
}

sub file_options {
	my $selected = shift // '';
	return join '', map {
		"<option" . ($_ eq $selected ? ' selected' : '') . '>' . html_escape($_) . "</option>\n"
	} fortune_files();
}

sub respond {
	my ($status, $body) = @_;
	print "Status: $status\r\nContent-Type: text/html; charset=utf-8\r\n",
		"Cache-Control: no-store\r\n\r\n";
	print <<"EOF";
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>fortunes</title></head>
<body>
<h1>fortunes</h1>
$body</body>
</html>
EOF
	exit 0;
}

sub page {
	my ($status, $msg, $selected) = @_;
	my $opts = file_options($selected);
	my $note = defined $msg ? '<p>' . html_escape($msg) . "</p>\n" : '';
	$note .= last_added();
	respond($status, <<"EOF");
$note<h2>Add a fortune</h2>
<form method="post" action="/">
<input type="hidden" name="action" value="add">
<p><select name="file">
$opts</select></p>
<p><textarea name="fortune" rows="10" cols="72"></textarea></p>
<p><button type="submit">Add fortune</button></p>
</form>
<h2>Remove fortunes</h2>
<form method="get" action="/">
<p><select name="remove">
$opts</select> <button type="submit">List fortunes</button></p>
</form>
<h2>New file</h2>
<form method="post" action="/">
<input type="hidden" name="action" value="create">
<p><input type="text" name="name" maxlength="64" pattern="[A-Za-z0-9_\\-]+" required>
<button type="submit">Create file</button></p>
<p>Letters, digits, _ and - only.</p>
</form>
<h2>Download</h2>
<form method="get" action="/">
<p><button type="submit" name="download" value="1">Download all fortunes</button></p>
</form>
EOF
}

# A file as fortune(6) sees it: segments separated by lines that are just "%".
# Returns (\@segments, \@delimiters), where the file is exactly
# seg0 . delim0 . seg1 . delim1 ... segN. Empty segments are not fortunes.
sub split_file {
	my $content = shift;
	my (@segs, @delims) = ('');
	for my $line ($content =~ /[^\n]*\n|[^\n]+\z/g) {
		if ($line =~ /^%\n?\z/) { push @delims, $line; push @segs, '' }
		else                    { $segs[-1] .= $line }
	}
	return (\@segs, \@delims);
}

sub slurp {
	my $fh = shift;
	seek($fh, 0, 0);
	local $/;
	return scalar(<$fh>) // '';
}

# The remove page: every fortune in $file with a checkbox. sum= is the SHA-1 of
# the file as listed, so a remove against a file that has changed since (an add,
# another remove, a re-POST on reload) is refused rather than hitting the wrong
# fortunes.
sub remove_page {
	my ($status, $msg, $file) = @_;
	open(my $fh, '<:raw', "$DIR/$file") or page('500 Internal Server Error', "Cannot open $file: $!");
	my $content = slurp($fh);
	close $fh;
	my ($segs) = split_file($content);
	my $body = '';
	$body .= '<p>' . html_escape($msg) . "</p>\n" if defined $msg;
	$body .= "<p><a href=\"/\">Back</a></p>\n<h2>Remove from " . html_escape($file) . "</h2>\n";
	my $k = 0;
	my $list = '';
	for my $i (0 .. $#$segs) {
		next unless length $segs->[$i];
		$k++;
		my $t = $segs->[$i];
		utf8::decode($t);
		if (length $t > 2000) {
			my $more = length($t) - 2000;
			$t = substr($t, 0, 2000) . "\n[... $more more characters]";
		}
		$t = html_escape($t);
		utf8::encode($t);
		$list .= "<p><label><input type=\"checkbox\" name=\"n\" value=\"$i\"> #$k</label></p>\n<pre>$t</pre>\n";
	}
	if ($k) {
		my $sum = sha1_hex($content);
		my $ef = html_escape($file);
		$body .= <<"EOF";
<form method="post" action="/">
<input type="hidden" name="action" value="remove">
<input type="hidden" name="file" value="$ef">
<input type="hidden" name="sum" value="$sum">
$list<p><button type="submit">Remove selected</button></p>
</form>
EOF
	} else {
		$body .= "<p>No fortunes in this file.</p>\n";
	}
	respond($status, $body);
}

# strfile(1), version 2, no flags — byte-identical to what fortune-mod's
# strfile writes for these files, so fortune-mod does not need installing.
# Header: version, count, longest, shortest, flags, delim + 3 pad bytes; then
# count+1 big-endian offsets (each entry's start, then end of file).
sub write_dat {
	my $name = shift;
	open(my $in, '<:raw', "$DIR/$name") or die "open $name: $!";
	my (@offs, $long, $short);
	my ($pos, $start) = (0, 0);
	my $take = sub {
		my $len = shift;
		return if $len <= 0;
		push @offs, $start;
		$long  = $len if !defined $long  || $len > $long;
		$short = $len if !defined $short || $len < $short;
	};
	while (my $line = <$in>) {
		if ($line =~ /^%\n?\z/) {
			$take->($pos - $start);
			$start = $pos + length $line;
		}
		$pos += length $line;
	}
	close $in;
	$take->($pos - $start);
	my $dat = pack('N5 a1 x3 N*', 2, scalar @offs, $long // 0, $short // 0, 0,
		'%', @offs, $pos);
	my $tmp = "$DIR/.$name.dat.$$";
	open(my $out, '>:raw', $tmp) or die "open $tmp: $!";
	print $out $dat;
	close $out or die "close $tmp: $!";
	chmod 0664, $tmp;
	rename $tmp, "$DIR/$name.dat" or die "rename $tmp: $!";
}

# Offline use: `fortunes.cgi --strfile <name>` rebuilds one .dat.
if (@ARGV == 2 && $ARGV[0] eq '--strfile') {
	write_dat($ARGV[1]);
	exit 0;
}

my $method = $ENV{REQUEST_METHOD} // 'GET';
my $query  = $ENV{QUERY_STRING}   // '';

if ($method eq 'GET' || $method eq 'HEAD') {
	if ($query =~ /(?:^|&)download(?:=|&|$)/) {
		my @stamp = gmtime;
		my $fn = sprintf 'fortunes-%04d%02d%02d.tar.gz',
			$stamp[5] + 1900, $stamp[4] + 1, $stamp[3];
		$| = 1;
		print "Content-Type: application/gzip\r\n",
			"Content-Disposition: attachment; filename=\"$fn\"\r\n",
			"Cache-Control: no-store\r\n\r\n";
		exit 0 if $method eq 'HEAD';
		exec 'tar', '-czf', '-', '-C', '/srv/http', '--exclude', 'fortunes/.*',
			'fortunes';
		die "exec tar: $!";
	}
	if ($query =~ /(?:^|&)remove=([^&]*)/) {
		my $file = url_decode($1);
		page('404 Not Found', 'No such fortune file.')
			unless grep { $_ eq $file } fortune_files();
		remove_page('200 OK', undef, $file);
	}
	page('200 OK');
}

page('405 Method Not Allowed', 'Method not allowed.') unless $method eq 'POST';

# Basic auth credentials ride along on cross-site requests too, so a page
# elsewhere could otherwise POST here on a logged-in browser's behalf.
my $origin = $ENV{HTTP_ORIGIN};
if (defined $origin && $origin ne '' && $origin ne $SELF) {
	page('403 Forbidden', 'Cross-origin POST refused.');
}

my $clen = $ENV{CONTENT_LENGTH} // 0;
page('413 Content Too Large', 'Too long.') if $clen > 65536;
my $body = '';
read(STDIN, $body, $clen) if $clen > 0;

# Last value wins for single fields; every value is kept for repeated ones (n=).
my (%p, %multi);
for my $pair (split /&/, $body) {
	my ($k, $v) = split /=/, $pair, 2;
	($k, $v) = (url_decode($k), url_decode($v));
	$p{$k} = $v;
	push @{ $multi{$k} }, $v;
}

my $action = $p{action} // 'add';

if ($action eq 'create') {
	my $name = $p{name} // '';
	$name =~ s/^\s+|\s+$//g;
	page('400 Bad Request', 'File names are letters, digits, _ and - only (at most 64).')
		unless $name =~ /$NAME_RE/;
	sysopen(my $fh, "$DIR/$name", O_WRONLY | O_CREAT | O_EXCL, 0664)
		or page($!{EEXIST} ? '409 Conflict' : '500 Internal Server Error',
			$!{EEXIST} ? "$name already exists." : "Cannot create $name: $!");
	close $fh;
	chmod 0664, "$DIR/$name";
	eval { write_dat($name); 1 }
		or page('500 Internal Server Error', "Created, but writing $name.dat failed: $@", $name);
	page('201 Created', "Created $name.", $name);
}

my $file = $p{file} // '';
page('400 Bad Request', 'No such fortune file.')
	unless grep { $_ eq $file } fortune_files();

if ($action eq 'remove') {
	my @want = @{ $multi{n} // [] };
	remove_page('400 Bad Request', 'Nothing selected, nothing removed.', $file) unless @want;
	open(my $fh, '+<:raw', "$DIR/$file") or page('500 Internal Server Error', "Cannot open $file: $!", $file);
	flock($fh, 2) or page('500 Internal Server Error', "Cannot lock $file: $!", $file);
	my $content = slurp($fh);
	if (sha1_hex($content) ne ($p{sum} // '')) {
		close $fh;
		remove_page('409 Conflict', "$file changed since it was listed; nothing removed. Here it is again.", $file);
	}
	my ($segs, $delims) = split_file($content);
	my @pieces = map { ($segs->[$_], $_ < @$delims ? $delims->[$_] : ()) } 0 .. $#$segs;
	my %gone;
	for my $i (@want) {
		unless ($i =~ /^\d+$/ && $i <= $#$segs && length $segs->[$i]) {
			close $fh;
			remove_page('400 Bad Request', 'Bad selection; nothing removed.', $file);
		}
		next if $gone{$i}++;
		# Drop the fortune and the delimiter after it, or before it if it is the
		# last segment. Everything else stays byte-for-byte as it was.
		$pieces[2 * $i] = undef;
		$pieces[$i < @$delims ? 2 * $i + 1 : 2 * $i - 1] = undef if @$delims;
	}
	my $new = join '', grep { defined } @pieces;
	# Rewritten in place, not renamed over: an add waiting on this flock holds
	# the same inode and must append to the new contents, not an orphaned file.
	seek($fh, 0, 0);
	print $fh $new;
	truncate($fh, length $new) or page('500 Internal Server Error', "Cannot truncate $file: $!", $file);
	close $fh or page('500 Internal Server Error', "Cannot write $file: $!", $file);
	eval { write_dat($file); 1 }
		or page('500 Internal Server Error', "Removed, but rebuilding $file.dat failed: $@", $file);
	my $n = keys %gone;
	remove_page('200 OK', "Removed $n fortune" . ($n == 1 ? '' : 's') . " from $file.", $file);
}

page('400 Bad Request', 'Unknown action.') unless $action eq 'add';

my $text = $p{fortune} // '';
$text =~ s/\r\n?/\n/g;
$text =~ s/[ \t]+$//mg;    # trailing whitespace on every line
$text =~ s/\A\n+//;        # leading blank lines
$text =~ s/\n+\z//;        # trailing blank lines
page('400 Bad Request', 'Empty fortune, nothing added.', $file)
	if $text !~ /\S/;
# A line that is just "%" is the delimiter and would split this into two.
page('400 Bad Request', 'A line consisting only of "%" is not allowed.', $file)
	if $text =~ /^%$/m;

open(my $fh, '+<:raw', "$DIR/$file") or page('500 Internal Server Error', "Cannot open $file: $!", $file);
flock($fh, 2) or page('500 Internal Server Error', "Cannot lock $file: $!", $file);
seek($fh, 0, 2);
my $size = tell $fh;
my $sep = '';
if ($size > 0) {
	seek($fh, $size - 1, 0);
	read($fh, my $last, 1);
	$sep = ($last eq "\n" ? '' : "\n") . "%\n";
	seek($fh, 0, 2);
}
print $fh $sep, $text, "\n";
close $fh or page('500 Internal Server Error', "Cannot write $file: $!", $file);
# The .dat is rebuilt after the lock is released; two near-simultaneous adds
# to one file each rebuild from the whole file, so the last rename wins with
# a .dat that covers both.
eval { write_dat($file); 1 }
	or page('500 Internal Server Error', "Added, but rebuilding $file.dat failed: $@", $file);

# Record the add for the "Last fortune added" line (temp + rename, so a reader
# never sees half a line). Failure here does not undo or fail the add.
my $tmp = "$LAST.$$";
if (open my $lf, '>', $tmp) {
	print $lf time, " $file\n";
	close $lf and chmod(0664, $tmp) and rename($tmp, $LAST) or unlink $tmp;
}

page('200 OK', "Added to $file.", $file);
