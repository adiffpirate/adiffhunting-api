#!/bin/bash

script_path=$(dirname "$0")

# HOW TO USE:
#
# ./_log.sh <LEVEL> <MESSAGE> <ARG1> <ARG2> <ARGN> ...
# 
# LEVEL: Log level, can be 'info', 'debug', 'warn', 'error'
# MESSAGE: Short text explaining what this log is about
# ARGN: Arguments, used to add more info into the log.
# 			The format of each argument should be 'key=value' with value being a short text or an absolute filepath (used for long texts).

OP_ID=$(cat /tmp/adh-operation-id 2>/dev/null)
python3 $script_path/_log.py "$OP_ID" "${@:1}"
