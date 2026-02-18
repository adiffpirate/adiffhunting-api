#!/bin/bash
script_path=$(dirname "$0")
set -eEo pipefail
trap '>&2 $script_path/_stacktrace.sh "$?" "$BASH_SOURCE" "$BASH_COMMAND" "$LINENO"' ERR

# ──────────────────────────────────────────────────────────────
#  parse_urls.sh — URLs Parser
#
#  Reads URLs from standard input and outputs one JSON record
#  per line (JSONLines format), suitable for database ingestion.
#
#  Usage:
#    cat urls_list.txt | ./parse_urls.sh
# ──────────────────────────────────────────────────────────────

REGEX_URL_PARSER='^((.*):\/\/)?([^\/?#]+)?([^?#]*)(\?([^#]*))?$'
REGEX_IP_DOMAIN='^([0-9]{1,3}\.){3}[0-9]{1,3}(:[0-9]*)?$' # Allow port
REGEX_VALID_DNS='^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}?$'

main(){
	# Read input from stdin
	if [[ -t 0 ]]; then
		$script_path/_log.sh 'error' 'No URLs were provided on input via stdin'
		exit 1
	else
		URLS_LIST="$(cat /dev/stdin)"
	fi

	# For each line
	$script_path/_log.sh 'info' 'Parsing URLs from stdin' "amount=$(echo "$URLS_LIST" | wc -l)"
	for url in $URLS_LIST; do
		# Breakdown url into capture groups using regex:
		# Group \1 = full protocol including "://" (e.g. "http://" or "https://")
		# Group \2 = protocol only (e.g. "http" or "https")
		# Group \3 = domain / host (e.g. "example.com")
		# Group \4 = path (e.g. "/foo/bar")
		# Group \5 = full query string including leading "?" (e.g. "?x=1&y=2")
		# Group \6 = query string without "?" (e.g. "x=1&y=2")
		local protocol_full="$(echo "$url" | sed -E "s|$REGEX_URL_PARSER|\\1|")"
		local protocol="$(echo "$url" | sed -E "s|$REGEX_URL_PARSER|\\2|")"
		local domain="$(echo "$url" | sed -E "s|$REGEX_URL_PARSER|\\3|")"
		local path="$(echo "$url" | sed -E "s|$REGEX_URL_PARSER|\\4|" | sed -E 's|/*$||')" # Remove trailing slash if present
		local args_full="$(echo "$url" | sed -E "s|$REGEX_URL_PARSER|\\5|")"
		local args="$(echo "$url" | sed -E "s|$REGEX_URL_PARSER|\\6|")"

		# Skip processing if URL is missing the domain
		if [[ -z "$domain" ]]; then
			$script_path/_log.sh 'warn' 'URL is missing the domain' "url=$url" "protocol=$protocol" "domain=$domain" "path=$path" "args=$args"
			continue
		fi

		# Skip processing if domain is invalid
		if [[ ! $domain =~ $REGEX_VALID_DNS ]] && [[ ! $domain =~ $REGEX_IP_DOMAIN ]]; then
			$script_path/_log.sh 'warn' 'Domain is invalid' "url=$url" "protocol=$protocol" "domain=$domain" "path=$path" "args=$args"
			continue
		fi

		# Normalize URL
		url_normalized="${protocol_full}${domain}${path}${args_full}"

		$script_path/_log.sh 'debug' 'Parsing URL' "url=$url" "protocol=$protocol" "domain=$domain" "path=$path" "args=$args"
		parse_url "$url_normalized" "$domain" "$path"
		parse_domain "$domain"
		parse_path "$path"

	done
}

parse_url(){
	local url="$1"
	local domain="$2"
	local path="$3"

	# Calculate randomSeed as the md5 hash of the url
	local url_random_seed="$(echo "$url" | md5sum | awk '{print $1}')"

	# Print parsed JSON
	jq -nc "{
		record_type: \"Url\",
		record_data: {
			value: \"$url\",
			domain: {value: \"$domain\"},
			$(if [[ -n "$path" ]]; then echo "path: {value: \"$path\"},"; fi)
			randomSeed: \"$url_random_seed\"
		}
	}"
}

parse_domain(){
	local domain="$1"
	local subdomain="$2"

	# Count the number of words delimeted by a dot
	local domain_level="$(echo "$domain" | awk -F. '{print NF}')"
	# Get the parent domain (e.g. for "foo.example.com" the parent_domain is "example.com")
	local parent_domain="$(echo "$domain" | sed -E 's|^([^\.]+\.)(.+)$|\2|')"

	# Determine domain type
	local domain_type=''
	if echo "$domain" | grep -Eq "$REGEX_IP_DOMAIN"; then # If domain is IP
		domain_type='ip'
	else # Everything else should be dns
		domain_type='dns'
	fi

	# Print parsed JSON with subdomain if provided
	# (without 'level' if domain is actually an IP)
	jq -nc "{
		record_type: \"Domain\",
		record_data: {
			value: \"$domain\",
			$(if [[ -n "$subdomain" ]]; then echo "subdomains:[{value: \"$subdomain\"}],"; fi)
			type: \"$domain_type\"
		}
	}"

	# Call this function recursively for DNS parent domains until it reachs TLD
	# if [[ $domain_type == "dns" ]] && [ $domain_level -gt 1 ]; then
	# 	parse_domain "$parent_domain" "$domain"
	# fi
}

parse_path(){
	local path="$1"
	local subpath="$2"

	# If path is empty set it to root
	if [[ -z "$path" ]]; then
		path='/'
	fi

	# Set path depth (0 if root, otherwise count the number of slashes)
	local path_depth=''
	if [[ "$path" == "/" ]]; then
		path_depth='0'
	else
		local path_depth="$(echo "$path" | grep -Eo '/' | wc -l)"
	fi

	# Get the parent path (e.g. for "/foo/bar" the parent_path is "/foo")
	local parent_path="$(echo "$path" | sed -E 's|(\/.+)?(\/[^\/]+)$|\1|')"
	# Handle root parent path edge case
	if [ -z "$parent_path" ]; then
		parent_path='/'
	fi

	# Print parsed JSON (with subpath if provided)
	jq -nc "{
		record_type: \"Path\",
		record_data: {
			value: \"$path\",
			depth: $path_depth,
			$(if [[ -n "$subpath" ]]; then echo "subpaths:[{value: \"$subpath\"}]"; fi)
		}
	}"

	# Call this function recursively for subpaths
	if [ $path_depth -gt 0 ]; then
		parse_path "$parent_path" "$path"
	fi
}

# Call main function
main
