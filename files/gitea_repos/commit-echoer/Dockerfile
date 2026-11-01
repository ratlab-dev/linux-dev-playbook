# Multi-stage Dockerfile: builds a pure static binary and packages it into scratch
FROM golang:1.23-alpine AS builder

ARG COMMIT_ID=development

WORKDIR /src
COPY main.go .

# Statically compile with no cgo dependencies and strip symbols
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags "-s -w -X main.CommitID=${COMMIT_ID}" -o /echo-commit main.go

# Minimal runtime from scratch
FROM scratch

COPY --from=builder /echo-commit /echo-commit

ENTRYPOINT ["/echo-commit"]
