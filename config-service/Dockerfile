FROM golang:1.25-alpine AS build

RUN apk add --no-cache make

WORKDIR /src
COPY src/ .
COPY templates/ /templates/

# Pin woodpecker/v3 to the last release that builds on Go 1.25 (the base image).
# woodpecker/v3 >= v3.14.0 bumped its `go` directive to 1.26.0, which makes an
# unpinned `go mod tidy` fail here with GOTOOLCHAIN=local. The config service
# only uses the stable server/model structs (Repo/Pipeline/Netrc), so pinning is
# safe. To adopt Go 1.26+, bump the base image AND this pin together.
RUN go mod init woodpecker-config-service && \
    go get go.woodpecker-ci.org/woodpecker/v3@v3.13.0 && \
    go mod tidy && \
    go test ./... && \
    CGO_ENABLED=0 go build -o /out/config-service .

FROM scratch

COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=build /out/config-service /config-service
COPY templates/ /templates/

HEALTHCHECK CMD ["/config-service", "ping"]
ENTRYPOINT ["/config-service"]
