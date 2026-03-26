# Stage 1: Build
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY . .
RUN go build -o main .

# Stage 2: Run
FROM alpine:latest
WORKDIR /root/
COPY --from=builder /app/main .
COPY --from=builder /app/db/migrations ./db/migrations
CMD ["./main"]