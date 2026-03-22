FROM golang:1.25-alpine AS build

RUN apk add --no-cache make

WORKDIR /src
COPY src/ .

RUN go mod init woodpecker-config-service && \
    go mod tidy && \
    CGO_ENABLED=0 go build -o /out/config-service .

FROM scratch

COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=build /out/config-service /config-service
COPY templates/ /templates/

HEALTHCHECK CMD ["/config-service", "ping"]
ENTRYPOINT ["/config-service"]
