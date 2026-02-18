import json
import os
import sys

def format_to_json(input_str):
    try:
        # If input is a valid JSON object, return the parsed JSON
        input_json = json.loads(input_str)
        return input_json
    except json.JSONDecodeError:
        # Return the input string as-is
        return input_str

def main():
    op_id = sys.argv[1]
    level = sys.argv[2]
    message = format_to_json(sys.argv[3]).strip('"')

    # Skip if it's a debug message but debug is not enabled
    if level == "debug" and os.getenv("DEBUG", "false").lower() == "false":
        sys.exit(0)

    # Create JSON body from arguments
    body = {}
    for arg in sys.argv[4:]:
        key, value = arg.split('=', 1)
        # If value is an absolute path to an existing file
        if value.startswith('/') and os.path.isfile(value):
            with open(value, 'r') as f:
                value = f.read().strip()
        body[key] = format_to_json(value)

    log_message = {
        "level": level,
        "operation_id": op_id,
        "message": message,
        "body": body
    }

    try:
        log_json = json.dumps(log_message, separators=(',', ':'))
        print(log_json, file=sys.stderr)
    except (TypeError, ValueError) as e:
        print(f'{{"level":"error","operation_id":"{op_id}","message":"Unable to create log message from provided arguments"}}', file=sys.stderr)
        if level == "error":
            sys.exit(1)

    if level == "error":
        sys.exit(1)

if __name__ == "__main__":
    main()
