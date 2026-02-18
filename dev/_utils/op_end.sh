#!/bin/bash

script_path=$(dirname "$0")

set -eEo pipefail
trap '>&2 $script_path/_stacktrace.sh "$?" "$BASH_SOURCE" "$BASH_COMMAND" "$LINENO"' ERR

# Get operation initial time that was saved earlier
OP_START_TIME=$(cat /tmp/adh-operation-start-time)
# Get current time and set as operation end time
OP_END_TIME=$(date +%s%3N)
# Calculate timespan
OP_TIMESPAN=$((OP_END_TIME - OP_START_TIME))

$script_path/_log.sh 'info' 'Operation end' "timespan_ms=$OP_TIMESPAN"
