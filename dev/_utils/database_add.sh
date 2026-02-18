#!/bin/bash
script_path=$(dirname "$0")
set -eEo pipefail
trap '>&2 $script_path/_stacktrace.sh "$?" "$BASH_SOURCE" "$BASH_COMMAND" "$LINENO"' ERR

# ──────────────────────────────────────────────────────────────
#  database_add.sh — Generic database add
#
#  Reads JSONLines generic database records from standard input
#  and add them to the database. Input should be like the example below:
#
#  {"record_type":"Domain","record_data":{"value":"foo.example.com",...}}
#  {"record_type":"Domain","record_data":{"value":"example.com",...}}
#  {"record_type":"Domain","record_data":{"value":"com",...}}
#
#  Usages:
#    cat generic_records.json | ./database_add.sh
#    echo "foo.example.com" | ./parse_urls.sh | ./database_add.sh
# ──────────────────────────────────────────────────────────────

# Read input from stdin
if [[ -t 0 ]]; then
	$script_path/_log.sh 'error' 'No database records were provided on input via stdin'
	exit 1
else
	RECORDS_LIST="$(cat /dev/stdin)"
fi

# For each line
$script_path/_log.sh 'info' 'Adding records into the database' "amount=$(echo "$RECORDS_LIST" | wc -l)"
for record in $RECORDS_LIST; do
	# Get record type and data
	record_type="$(echo "$record" | jq -rc '.record_type')"
	record_type_capitalized="${record_type^}"
	record_type_uppercase="${record_type^^}"
	record_type_lowercase="${record_type,,}"
	record_data="$(echo "$record" | jq -rc '.record_data')"
	# Add record on database
	$script_path/database_query.sh -q "
		mutation {
			add$record_type_capitalized(input: [$record_data], upsert: true){
				$record_type_lowercase {
					id
				}
			}
		}
	"
done
