#!/bin/bash

script_path=$(dirname "$0")

set -eEo pipefail
trap '>&2 $script_path/_stacktrace.sh "$?" "$BASH_SOURCE" "$BASH_COMMAND" "$LINENO"' ERR

# Save operation id
uuidgen -r > /tmp/adh-operation-id

# Wait for database to be available before starting operation
$script_path/wait_for_db.sh

$script_path/_log.sh 'info' 'Operation start'

# Save operation initial time
date +%s%3N > /tmp/adh-operation-start-time
