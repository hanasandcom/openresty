#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
conf="$repo/nginx/conf.d/logs.conf"
test -f "$conf"

routes='
/api/migration/status
/api/migration/findings
/api/migration/findings/verify
/api/migration/receipts
/api/migration/linkage-archive
/api/migration/state
/api/migration/projection
'

while IFS= read -r path; do
    test -n "$path" || continue
    block=$(awk -v path="$path" '
        $0 == "    location = " path " {" { capture = 1; found++ }
        capture { print }
        capture && $0 == "    }" { capture = 0; exit }
        END { if (found != 1) exit 1 }
    ' "$conf") || { echo "Expected one exact location for $path." >&2; exit 1; }
    printf '%s\n' "$block" | grep -Fqx '        client_max_body_size 512k;'
    printf '%s\n' "$block" | grep -Fqx '        limit_except POST { deny all; }'
    printf '%s\n' "$block" | grep -Fqx "        proxy_pass http://127.0.0.1:18091$path;"
    printf '%s\n' "$block" | grep -Fqx '        include snippets/proxy-headers.conf;'
    printf '%s\n' "$block" | grep -Fqx '    }'
done <<EOF
$routes
EOF

for path in /api/ingest /api/organizations/sync /api/health; do
    test "$(grep -Fxc "    location = $path {" "$conf")" = 1
    test "$(grep -Fxc "        proxy_pass http://127.0.0.1:18091$path;" "$conf")" = 1
done
awk '/location = \/api\/ingest \{/,/^    \}/' "$conf" | grep -Fqx '        limit_except POST { deny all; }'
awk '/location = \/api\/organizations\/sync \{/,/^    \}/' "$conf" | grep -Fqx '        limit_except POST { deny all; }'
awk '/location = \/api\/health \{/,/^    \}/' "$conf" | grep -Fqx '        limit_except GET { deny all; }'

customer_routes='
/api/logs
/api/logs/search
/api/logs/realtime
/api/logs/services
/api/logs/services/summary
/api/logs/metrics
/api/logs/metrics/public
/api/logs/tuning
/api/logs/tuning/refresh
/api/logs/errors
/api/rules/hits
'
while IFS= read -r path; do
    test -n "$path" || continue
    block=$(awk -v path="$path" '
        $0 == "    location = " path " {" { capture = 1; found++ }
        capture { print }
        capture && $0 == "    }" { capture = 0; exit }
        END { if (found != 1) exit 1 }
    ' "$conf") || { echo "Expected one exact customer read location for $path." >&2; exit 1; }
    printf '%s\n' "$block" | grep -Fqx '        limit_except GET { deny all; }' || {
        if test "$path" != /api/logs/tuning/refresh; then echo "Expected GET-only access for $path." >&2; exit 1; fi
        printf '%s\n' "$block" | grep -Fqx '        limit_except POST { deny all; }'
    }
    printf '%s\n' "$block" | grep -Fqx "        proxy_pass http://127.0.0.1:18091$path;"
    printf '%s\n' "$block" | grep -Fqx '        include snippets/proxy-headers.conf;'
done <<EOF
$customer_routes
EOF

grep -Fqx '    location ~ ^/api/rules/([^/]+)/hits$ {' "$conf"
grep -Fqx '        limit_except GET { deny all; }' "$conf"
grep -Fqx '        proxy_pass http://127.0.0.1:18091/api/rules/$1/hits;' "$conf"

grep -Fqx '    location / {' "$conf"
grep -Fqx '        return 404;' "$conf"

# An exact route allowlist must not turn into a broad migration/API prefix.
if grep -Eq 'location[[:space:]]+\^~?[[:space:]]+/api/migration|location[[:space:]]+/api/' "$conf"; then
    echo 'A broad API or migration proxy location bypasses the exact route allowlist.' >&2
    exit 1
fi

echo 'Logs route tests passed: customer GET routes, seven exact POST-only migration paths, body limits, existing service routes, and 404 fallback.'
