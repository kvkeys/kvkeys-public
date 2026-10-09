#!/bin/bash
# bin/mirror.sh <artifact-dir> [us|eu|both]  -> push one public artifact directory to the Cloudflare Workers Artifacts
# namespace(s) of its jurisdiction (kvkeys-public-us / kvkeys-public-eu). Prints kv lines. Never prints the token.
#   account: CF_ACCOUNT_ID (default the KVMACHINES account); token: CF_ARTIFACTS_TOKEN or the 0600 file
#   ~/.config/kvkeys/secrets/kvmachines-cloudflare-artifacts.key (a Cloudflare API token with Artifacts Edit; ADR-0022 naming).
#   The repo is created through the REST API, then pushed with git over HTTPS and a Bearer header (docs: artifacts/api/git-protocol).
set -u
DIR=${1:?artifact directory}; JUR=${2:-$(grep -o '^jurisdiction -> .*' "$DIR/meta.kv" 2>/dev/null | sed 's/.*-> //')}; JUR=${JUR:-both}
ACCT=${CF_ACCOUNT_ID:-634ff28065e23b4f4a0b6200d62bc97b}
TOKFILE=${CF_ARTIFACTS_TOKEN_FILE:-$HOME/.config/kvkeys/secrets/kvmachines-cloudflare-artifacts.key}
TOK=${CF_ARTIFACTS_TOKEN:-$(cat "$TOKFILE" 2>/dev/null)}; [ -n "$TOK" ] || { echo "mirror:error -> no token: set CF_ARTIFACTS_TOKEN or write $TOKFILE (0600)"; exit 1; }
NAME=$(basename "$DIR"); [ -f "$DIR/meta.kv" ] || { echo "mirror:error -> $DIR has no meta.kv"; exit 1; }
case "$JUR" in us) NS="kvkeys-public-us";; eu) NS="kvkeys-public-eu";; both) NS="kvkeys-public-us kvkeys-public-eu";; *) echo "mirror:error -> jurisdiction $JUR is not us|eu|both"; exit 1;; esac
for ns in $NS; do
  code=$(curl -s -o /tmp/mirror.$$ -w '%{http_code}' -X POST "https://api.cloudflare.com/client/v4/accounts/$ACCT/artifacts/namespaces/$ns/repos" -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' -d "{\"name\":\"$NAME\"}")
  remote=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); r=d.get("result") or {}; print(r.get("remote") or "")' /tmp/mirror.$$ 2>/dev/null)
  [ -n "$remote" ] || remote="https://$ACCT.artifacts.cloudflare.net/git/$ns/$NAME.git"
  echo "mirror:$ns:repo -> $code $NAME"
  ( cd "$DIR" && { [ -d .git ] || { git init -q -b main && git add -A && git -c user.name=alex-kvm -c user.email=alex@kvmachines.com commit -q -m "public artifact $NAME"; }; } \
    && git -c http.extraHeader="Authorization: Bearer $TOK" push -q "$remote" HEAD:main 2>/tmp/mirror.err.$$ && echo "mirror:$ns:push -> ok $remote" || echo "mirror:$ns:push -> failed: $(sed 's/Bearer [^ ]*/Bearer <token>/g' /tmp/mirror.err.$$ | tail -1)" )
done
rm -f /tmp/mirror.$$ /tmp/mirror.err.$$
