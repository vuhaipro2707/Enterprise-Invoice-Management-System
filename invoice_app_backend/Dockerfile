# Stage 1: Build
FROM golang:alpine AS builder
WORKDIR /app
COPY . .
RUN go build -o main .

# Stage 2: Run
FROM alpine:latest
RUN apk add --no-cache postgresql16-client tzdata
WORKDIR /root/
COPY --from=builder /app/main .
COPY --from=builder /app/db/migrations ./db/migrations
COPY --from=builder /app/fonts ./fonts
COPY --from=builder /app/ward_map.json ./ward_map.json
CMD ["./main"]