#!/bin/bash

script_path=$(dirname "$0")

set -eEo pipefail
trap '>&2 $script_path/_stacktrace.sh "$?" "$BASH_SOURCE" "$BASH_COMMAND" "$LINENO"' ERR

usage="$(basename "$0") [-h|q|f|t]

Query DGraph database.

flags:
	-h show this help text
	-q query
	-f query stored in file (mutually exclusive with -q)
	-t query type (optional) (can be: graphql or dql) (defaults to graphql)
	-o output file (optional) (use '/dev/stdout' to print to stdout) (defaults to none)
"

# Defaults
query_type="graphql"

while getopts ":h?q:f:t:o:" opt; do
	case "$opt" in
		h) echo -E "$usage" && exit 0 ;;
		q) arg_query=$OPTARG ;;
		f) query_file=$OPTARG ;;
		t) query_type=$OPTARG ;;
		o) output=$OPTARG ;;
	esac
done
if [ -z "$arg_query" ] && [ -z "$query_file" ]; then
	echo -E "$usage"
	exit 1
fi

if [ -z "$DGRAPH_ALPHA_HOST" ]; then
	>&2 echo -E "Please configure the DGRAPH_ALPHA_HOST environment variable"
	exit 1
fi
if [ -z "$DGRAPH_ALPHA_HTTP_PORT" ]; then
	>&2 echo -E "Please configure the DGRAPH_ALPHA_HTTP_PORT environment variable"
	exit 1
fi

# Determine if output should be printed to stdout based on flag
if [[ "$output" == '/dev/stdout' ]]; then
	print_output='true'
fi

# If output was not defined or is '/dev/stdout'
if [ -z "$output" ] || [[ "$print_output" == 'true' ]]; then
	output='/tmp/adh-utils-database_query-output'
fi

if [ -n "$arg_query" ]; then
	query="$arg_query"
else
	query=$(cat $query_file)
fi

# Prepare query
#   1. Turn into one line string, removing newlines and tabs
#   2. Escape backslashes
#   3. Remove quotes from keys
query=$(echo -E "$query" | while read -r line; do echo -nE "$line" | sed 's/\\/\\\\/g' | sed -E 's/"([^"]*)":/\1:/g'; done) # )

# Prepare request
if [[ "$query_type" == "graphql" ]] ; then
	body="{\"query\":\"$(echo -E "$query" | sed 's/"/\\"/g')\"}"
	content_type="application/json"
	path="graphql"
elif [[ "$query_type" == "dql" ]]; then
	body="$query"
	# Set content type and path based on body
	if [[ "$body" =~ ^( )*(upsert) ]]; then
		content_type="application/rdf"
		path="mutate?commitNow=true"
	else
		content_type="application/dql"
		path="query?ro=true"
	fi
else
	echo -E "$usage"
	exit 1
fi

# Save body to file
body_file=$(mktemp) && echo -E "$body" > $body_file

# Get start time
start_time=$(date +%s%3N)

while true; do # Loop to retry aborts

	$script_path/_log.sh 'debug' 'Querying database' "query=$body_file"

	until curl --no-progress-meter --fail \
		$DGRAPH_ALPHA_HOST:$DGRAPH_ALPHA_HTTP_PORT/$path \
		--header "Content-Type: $content_type" \
		--data "@$body_file" \
	; do
			$script_path/_log.sh 'info' 'Unable to reach database. Retrying in 5 seconds'
			sleep 5
	done > $output

	if grep 'Transaction has been aborted' $output > /dev/null 2>&1; then
		$script_path/_log.sh 'warn' 'Query has been aborted. Retrying in 5 seconds' "query=$body_file" "query_result=$output"
		sleep 5
	else
		break
	fi
done

# Parse output
if [[ "$(jq 'has("errors")' $output)" == "true" ]]; then
	$script_path/_log.sh 'error' 'Database query returned errors' "query=$body_file" "query_result=$output"
else
	$script_path/_log.sh 'debug' 'Database query successful' "query=$body_file" "query_result=$output"
fi

# Pretty print to stdout if output flag is '/dev/stdout'
if [[ "$print_output" == 'true' ]]; then
	jq '.' $output
fi

# Get end time
end_time=$(date +%s%3N)
# Calculate timespan
timespan=$((end_time - start_time))
