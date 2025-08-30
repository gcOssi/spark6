# Build stage
FROM node:18-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci --no-audit --no-fund
COPY . .
ARG REACT_APP_API_URL
ENV REACT_APP_API_URL=${REACT_APP_API_URL}
RUN npm run build

# Serve with nginx and basic auth
FROM nginx:1.25-alpine
COPY --from=build /app/build /usr/share/nginx/html
COPY docker/default.conf.template /tmp/default.conf
COPY docker/entrypoint.sh /entrypoint.sh
EXPOSE 80
ENTRYPOINT ["/entrypoint.sh"]
