#!/usr/bin/env bash
# Échoue si un module lib/parse/*.hvn redéfinit un nom de lib/heaven_parse.hvn.
defs() { grep -oE '^[a-z_][A-Za-z0-9_]*' "$1" | grep -vx 'data' | sort -u; }
rc=0
for f in lib/parse/*.hvn; do
  c=$(comm -12 <(defs "$f") <(defs lib/heaven_parse.hvn))
  if [ -n "$c" ]; then echo "COLLISION $f :"; echo "$c"; rc=1; fi
done
exit $rc
