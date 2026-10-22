# Derived sandbox image: ubuntu:24.04 + the few pure-text/compute tools the
# subject scripts need REAL: bc (version compares), jq (JSON), mikefarah yq v4
# (local YAML editing; NOT stubbed so merge-compose.sh / compose edits are exercised for real).
# Build once:  docker build -t miniprem-harness:latest harness/
# (network during the image build is the only network use; runs use --network none.)
FROM ubuntu:24.04
ARG YQ_VERSION=v4.44.3
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends bc jq curl ca-certificates util-linux \
 && arch=$(dpkg --print-architecture) \
 && curl -fsSL -o /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${arch}" \
 && chmod 755 /usr/local/bin/yq \
 && apt-get purge -y curl ca-certificates && apt-get autoremove -y \
 && rm -rf /var/lib/apt/lists/*
