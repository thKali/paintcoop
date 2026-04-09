# Stage 1: compile to native binary
FROM dart:stable AS builder

WORKDIR /app
COPY pubspec.* ./
RUN dart pub get

COPY . .
RUN dart compile exe bin/server.dart -o bin/server

# Stage 2: minimal runtime (no Dart SDK needed)
FROM debian:bookworm-slim
COPY --from=builder /app/bin/server /server
EXPOSE 8080
CMD ["/server"]
