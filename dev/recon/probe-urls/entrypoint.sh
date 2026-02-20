#!/bin/bash
set -eEo pipefail
trap '$UTILS/_stacktrace.sh "$?" "$BASH_SOURCE" "$BASH_COMMAND" "$LINENO"' ERR
TMP_DIR="$(mktemp -d)"

probe(){
	local urls=$1
	local http_method=$2
	local http_method_uppercase=$(echo -E "$http_method" | tr '[:lower:]' '[:upper:]')

	# Run HTTPX and print its output as JSON Lines according to database schema
	httpx -x $http_method -list $urls -silent -threads 1 -json -include-response-header \
	| while read -r line; do
		# Skip HTML responses
		if echo -E "$line" | jq -e '."content_type" == "text/html"' > /dev/null; then
			$UTILS/_log.sh 'debug' 'Response is most likely not from an API. Skipping' "output=$line"
			continue
		fi
		# Parse response to match HttpResponse database record
		$UTILS/_log.sh 'debug' 'Parsing output' "output=$line"
		echo -E "$line" | jq -c '{
			value: ( (."status_code" | tostring) + " " + .method + " " + .url ),
			statusCode: ."status_code",
			method: .method,
			url: { value: .url },
			contentType: ."content_type",
			contentLength: ."content_length",
			headerAllow: ((.header.allow // "") | split(", ")),
			updatedAt: .timestamp
		}' || $UTILS/_log.sh 'error' 'Error while parsing output' "output=$line"
	done
}

probe_and_save(){
	local urls=$1
	local http_method=$2

	# Probe and save responses on database, one at a time
	probe $urls $http_method | while read -r line; do
		$UTILS/_log.sh 'debug' 'Saving response on database' "response=$line"
		$UTILS/database_query.sh -q "
			mutation {
				addHttpResponse(input: [$line], upsert: true){
					httpResponse { value }
				}
			}
		"
	done
}

while true; do
	$UTILS/op_start.sh

	urls=$TMP_DIR/urls

	# Get 100 urls without the "lastProbe" field
	$UTILS/database_get_urls.sh -f "not has(Url.lastProbe)" -a 'first: 100' > $urls
	# If all urls have "lastProbe", get 100 oldests that are at least older than $SCAN_COOLDOWN
	if [ ! -s "$urls" ]; then
		$UTILS/database_get_urls.sh \
			-f "lt(Url.lastProbe, \"$(date -Iseconds -d "-$SCAN_COOLDOWN")\")" \
			-a 'first: 100, orderasc: Url.lastProbe' \
		> $urls
	fi

	# Stop if urls file is empty
	if [ ! -s "$urls" ]; then
		$UTILS/_log.sh 'info' "No targets to probe. Trying again in 1 minute."
		sleep 60
		continue
	fi

	# Save to file the urls list as JSON so it looks better on logs
	urls_json=$urls.json
	jq -R -s 'split("\n") | map(select(length > 0))' $urls > $urls_json

	# Update lastProbe field for all urls
	$UTILS/_log.sh 'debug' 'Updating lastProbe field' "urls=$urls_json"
	cat $urls | while read -r url; do
		$UTILS/database_query.sh -q "
			mutation {
				updateUrl(input: {
					filter: { value: { eq: \"$url\" } },
					set: { lastProbe: \"$(date -Iseconds)\"} }
				){
					url { value }
				}
			}
		"
	done

	# Probe urls and save httpResponse on database
	for http_method in 'get' 'options'; do
		$UTILS/_log.sh 'info' 'Running: HTTPX' "http_method=$(echo -E "$http_method" | tr '[:lower:]' '[:upper:]')" "urls=$urls_json"
		probe_and_save $urls $http_method
	done

	$UTILS/op_end.sh
done
