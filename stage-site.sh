#!/bin/bash
# Stage: runs on every commit and merge (post-commit / post-merge hooks).
#
#   rootdomain/ -> /srv/httpstaging     previewable at staging.dreamstation.systems
#
# TOUCHES NOTHING LIVE. That is the entire point of the split: a typo now
# reaches a password-protected copy instead of the public site, and the live
# docroot, /srv/cgi, /usr/local/bin and /etc/nginx change only when a human
# runs promote-site.sh.
#
# The syntax gates live here rather than in promote-site.sh so they fire at
# commit time, when the mistake is fresh and the fix is one --amend away. They
# gate the STAGE, so a failure means there is nothing new to promote either.
#
# Everything in this repo that is not rootdomain/ — cgi/, status-sample/,
# nginx/ — has no meaningful staging copy: they are system state (executables,
# systemd units, the server's own config), not content. They are promote-only.
# See promote-site.sh.
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
STAGING=/srv/httpstaging

# --------------------------------------------------------------- syntax gates
#
# These catch compile-time errors only, not logic ones. That is the point: a
# cheap gate against the realistic failure, not a test suite. They cover files
# this script does not itself deploy, deliberately — a commit that breaks
# status.cgi should fail at the commit, not silently stage clean and then blow
# up during a promote, when the thing you were checking was the HTML.
if compgen -G "$ROOT/cgi/*.cgi" >/dev/null; then
	for f in "$ROOT"/cgi/*.cgi; do
		if ! perl -c "$f" >/dev/null 2>&1; then
			echo "ABORT: $(basename "$f") fails syntax check — nothing staged." >&2
			perl -c "$f" || true # show the user why
			exit 1
		fi
	done
fi

if [ -f "$ROOT/status-sample/status-sample.sh" ]; then
	if ! bash -n "$ROOT/status-sample/status-sample.sh" 2>/dev/null; then
		echo "ABORT: status-sample.sh fails syntax check — nothing staged." >&2
		bash -n "$ROOT/status-sample/status-sample.sh" || true
		exit 1
	fi
fi

# -------------------------------------------------------------------- content
#
# No .well-known/acme-challenge/ or ntpstats.txt carve-out here, unlike the
# promote. Neither exists in this tree: certbot's webroot is the LIVE docroot
# (see the staging vhost) and ntpstatsgen writes only to the live one. Staging
# owns every byte under it, so a plain --delete is correct.
sudo rsync -a --delete "$ROOT/rootdomain/" "$STAGING/"

sudo chown -R root:root "$STAGING/"
sudo chmod -R u=rwX,go=rX "$STAGING/"

echo "Staged rootdomain/ → $STAGING  (https://staging.dreamstation.systems)"
echo "Run ./promote-site.sh to go live."
