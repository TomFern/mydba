#!/usr/bin/env bash
# usage: dump.sh ... | filter-upgrade-dump.sh | load.sh ...


cat <<EOF
set @__filter_upgrade_log_bin_trust = @@log_bin_trust_function_creators;
EOF

sed 's/ROW_FORMAT=FIXED//g'

cat <<EOF
set GLOBAL log_bin_trust_function_creators = @__filter_upgrade_log_bin_trust;
EOF

