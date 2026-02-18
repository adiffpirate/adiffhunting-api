#!/bin/bash
set -eEo pipefail
trap '$UTILS/_stacktrace.sh "$?" "$BASH_SOURCE" "$BASH_COMMAND" "$LINENO"' ERR

export OP_ID=$(uuidgen -r)
$UTILS/wait_for_db.sh

# Enable query logging
$UTILS/_log.sh 'info' "Enabling query logging"
curl --no-progress-meter $DGRAPH_ALPHA_HOST:$DGRAPH_ALPHA_HTTP_PORT/admin -H 'Content-Type: application/graphql' --data '
	mutation {
		config(input: {logDQLRequest: true}) {
			response {
				code
				message
			}
		}
	}
' | jq -c .

# Create schemas
$UTILS/_log.sh 'info' "Creating Schemas"
curl --no-progress-meter $DGRAPH_ALPHA_HOST:$DGRAPH_ALPHA_HTTP_PORT/admin/schema --data '
	type Url {
		id: ID!
		value: String! @id @search(by: [hash, regexp])
		randomSeed: String @search(by: [hash]) # Workaround so we can query for random domains since dgraph doesnt have that built-in

		domain: Domain @hasInverse(field: urls)
		path: Path @hasInverse(field: urls)
		httpResponses: [HttpResponse] @hasInverse(field: url)

		lastProbe: DateTime @search(by: [hour])
		lastExploit: DateTime @search(by: [hour])
	}

	type Domain {
		id: ID!
		value: String! @id @search(by: [hash, regexp])
		type: String @search(by: [hash, term])
		subdomains: [Domain]
		urls: [Url] @hasInverse(field: domain)
	}

	type Path {
		id: ID!
		value: String! @id @search(by: [hash, regexp])
		depth: Int @search
		subpaths: [Path]
		urls: [Url] @hasInverse(field: path)
	}

	type HttpResponse {
		id: ID!
		value: String! @id @search(by: [hash, regexp])
		url: Url @hasInverse(field: httpResponses)

		method: String @search(by: [hash, term])
		statusCode: Int @search
		category: String @search(by: [hash, term])
		location: String @search(by: [hash, regexp])
		contentType: String @search(by: [hash, term])
		contentLength: Int @search
		updatedAt: DateTime @search(by: [hour])
	}
' | jq -c .
