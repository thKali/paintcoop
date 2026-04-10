# Stage 1: build Flutter web
FROM ghcr.io/cirruslabs/flutter:stable AS builder

WORKDIR /app
COPY pubspec.* ./
RUN flutter pub get

COPY . .

ARG API_URL=http://localhost:8080
RUN flutter build web --dart-define=API_URL=$API_URL

# Stage 2: serve with nginx
FROM nginx:alpine
COPY --from=builder /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
