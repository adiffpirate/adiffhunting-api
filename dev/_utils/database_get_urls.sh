#!/bin/bash

script_path=$(dirname "$0")

set -eEo pipefail
trap '>&2 $script_path/_stacktrace.sh "$?" "$BASH_SOURCE" "$BASH_COMMAND" "$LINENO"' ERR

usage="$(basename "$0") [-h|a|f|d]

Get URLs from DGraph using DQL

flags:
	-h show this help text
	-a args (optional)
	-f filter (optional)
"

while getopts ":h?a:f:d:" opt; do
	case "$opt" in
		h) echo "$usage" && exit 0 ;;
		a) args=$OPTARG ;;
		f) filter=$OPTARG ;;
	esac
done

query_result=/tmp/adh-utils-database_get_urls-output

# Get URLs that have the skipScans flag on its Domain set to false
$script_path/database_query.sh -o $query_result -t dql -q "
	{
		results(func: has(Url.value), orderasc: Url.randomSeed $(if [ -n "$args" ]; then echo ",$args"; fi))
		@filter($(if [ -n "$filter" ]; then echo "$filter"; fi))
		@cascade
		{
			Url.value,
			Url.domain @filter(not eq(Domain.skipScans, true)) { Domain.value }
		}
	}
"

# Try to get urls. If it fails, print the query output to stderr
jq -c -r '.data.results | .[] | ."Url.value"' $query_result 2>/dev/null || >&2 jq -c '.' $query_result
