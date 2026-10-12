#!/usr/bin/env bash
# Usage: URL=https://<app>.<region>.azurecontainerapps.io KEY=... scripts/check.sh
# Run after the app has scaled to zero to measure the real cold start.
set -u
: "${URL:?set URL}"; : "${KEY:?set KEY}"
now() { date +%s.%N; }

t0=$(now)
until [ "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $KEY" "$URL/health")" = 200 ]; do sleep 0.5; done
t1=$(now)
echo "cold start to /health 200: $(echo "$t1 - $t0" | bc) s"

body='{"inputs":["quanto custa um site?"],"normalize":true}'
t2=$(now)
curl -s -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' -d "$body" "$URL/embed" \
  | python3 -c 'import sys,json; v=json.load(sys.stdin); print("vectors:", len(v), "dims:", len(v[0]))'
t3=$(now)
echo "first /embed: $(echo "$t3 - $t2" | bc) s"

t4=$(now)
curl -s -o /dev/null -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' -d "$body" "$URL/embed"
t5=$(now)
echo "warm /embed: $(echo "$t5 - $t4" | bc) s"

batch=$(python3 -c 'import json; print(json.dumps({"inputs": ["texto %d" % i for i in range(32)], "normalize": True}))')
curl -s -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' -d "$batch" "$URL/embed" \
  | python3 -c 'import sys,json; v=json.load(sys.stdin); print("batch of 32 ->", len(v), "vectors of", len(v[0]))'

echo "no key:    $(curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -d "$body" "$URL/embed")"
echo "wrong key: $(curl -s -o /dev/null -w '%{http_code}' -H 'Authorization: Bearer nope' -H 'Content-Type: application/json' -d "$body" "$URL/embed")"
