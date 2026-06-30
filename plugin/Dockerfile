# Base image: lightweight Alpine with all release tools
FROM alpine:3.21 AS base

# Pin versions for reproducibility
ARG COG_VERSION=7.0.0
ARG GH_VERSION=2.67.0

RUN apk add --no-cache \
    bash \
    git \
    gnupg \
    jq \
    curl \
    openssl \
    zip \
    openssh-client

# Install cocogitto (cog)
RUN curl -sL "https://github.com/cocogitto/cocogitto/releases/download/${COG_VERSION}/cocogitto-${COG_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
    | tar xz -C /tmp \
    && mv /tmp/x86_64-unknown-linux-musl/cog /usr/local/bin/cog \
    && chmod +x /usr/local/bin/cog \
    && rm -rf /tmp/*

# Install GitHub CLI
RUN curl -sL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" \
    | tar xz -C /tmp \
    && mv /tmp/gh_${GH_VERSION}_linux_amd64/bin/gh /usr/local/bin/gh \
    && chmod +x /usr/local/bin/gh \
    && rm -rf /tmp/*

COPY lib/ /plugin/lib/
COPY entrypoint.sh /plugin/entrypoint.sh
# WAL-70: vendor the GitHub App token minter so release steps can mint a
# short-lived, down-scoped installation token instead of carrying the shared PAT.
COPY mint-installation-token.sh /plugin/mint-installation-token.sh
COPY profiles.env /plugin/profiles.env
RUN chmod +x /plugin/entrypoint.sh /plugin/lib/*.sh /plugin/mint-installation-token.sh

ENTRYPOINT ["/plugin/entrypoint.sh"]

# Go variant: adds Go toolchain for cross-compilation
FROM base AS go

ARG GO_VERSION=1.25.0

RUN curl -sL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" \
    | tar xz -C /usr/local

ENV PATH="/usr/local/go/bin:${PATH}"
ENV GOPATH="/go"
ENV PATH="${GOPATH}/bin:${PATH}"
