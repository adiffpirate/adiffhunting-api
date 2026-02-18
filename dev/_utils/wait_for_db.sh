#!/bin/bash

script_path=$(dirname "$0")

curl_return=/tmp/adh-wait-for-db-curl-return
until curl --no-progress-meter --fail $DGRAPH_ALPHA_HOST:$DGRAPH_ALPHA_HTTP_PORT/health > /dev/null 2>$curl_return; do
	$script_path/_log.sh 'info' 'Waiting Alpha Server to be ready' \
		"db_host=$DGRAPH_ALPHA_HOST" "db_port=$DGRAPH_ALPHA_HTTP_PORT" "curl_return=$curl_return"
	sleep 1
done

sleep 5
