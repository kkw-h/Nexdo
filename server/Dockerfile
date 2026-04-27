FROM golang:1.26.2-alpine AS builder

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY cmd ./cmd
COPY internal ./internal

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /out/nexdo-api ./cmd/api

FROM alpine:3.20

WORKDIR /app

RUN addgroup -S nexdo && adduser -S -G nexdo nexdo

COPY --from=builder /out/nexdo-api /app/nexdo-api
COPY migrations /app/migrations

RUN mkdir -p /app/storage/audio && chown -R nexdo:nexdo /app

ENV APP_ENV=production
ENV APP_NAME=nexdo-server
ENV APP_ADDR=:8080
ENV DATABASE_URL=postgres://nexdo:nexdo@postgres:5432/nexdo?sslmode=disable
ENV AUDIO_STORAGE_DIR=/app/storage/audio
ENV AUTO_MIGRATE=true
ENV MIGRATIONS_DIR=/app/migrations

USER nexdo

EXPOSE 8080

CMD ["/app/nexdo-api"]
