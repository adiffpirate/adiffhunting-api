FROM alpine:3.19.1

# Basic tools
RUN apk add --no-cache bash coreutils curl wget sed jq unzip python3 uuidgen

ENV UTILS=/src/_utils
COPY _utils $UTILS

COPY database/dgraph-init/* /src/
CMD /src/entrypoint.sh
