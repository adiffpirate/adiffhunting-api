FROM alpine:3.19.1

# Basic tools
RUN apk add --no-cache bash coreutils curl wget sed jq unzip python3 uuidgen

# HTTPX
ARG HTTPX_VERSION="1.8.1"
RUN wget https://github.com/projectdiscovery/httpx/releases/download/v${HTTPX_VERSION}/httpx_${HTTPX_VERSION}_linux_386.zip -O httpx.zip \
	&& unzip httpx.zip -d httpx \
	&& mv httpx/httpx /usr/bin/httpx \
	&& chmod +x /usr/bin/httpx \
	&& rm -rfv httpx*

ENV UTILS=/src/_utils
COPY _utils $UTILS

ENV SCAN_COOLDOWN="1 week"

COPY recon/probe-urls/* /src/
CMD /src/entrypoint.sh
