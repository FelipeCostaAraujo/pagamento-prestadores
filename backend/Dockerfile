FROM golang:1.26-alpine AS build
WORKDIR /src

# Copy manifests first so dependency download is cached across code changes.
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/api ./cmd/api

# Alpine rather than distroless: the image needs a shell so accounts can be
# managed on the VM with `docker compose exec api /api user add <nome>`.
FROM alpine:3.20
RUN apk add --no-cache ca-certificates && adduser -D -u 65532 nonroot
COPY --from=build /out/api /api
EXPOSE 8081
USER nonroot:nonroot
ENTRYPOINT ["/api"]
