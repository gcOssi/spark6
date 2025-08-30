FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --no-audit --no-fund && apk add --no-cache curl
COPY . .
ENV NODE_ENV=production
ENV PORT=4000
EXPOSE 4000
CMD ["node", "server.js"]
