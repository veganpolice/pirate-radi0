FROM node:22-slim AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci

FROM node:22-slim
WORKDIR /app
COPY --from=build /app/node_modules ./node_modules
COPY package*.json ./
COPY index.js db.js ./
COPY migrations ./migrations
EXPOSE 3000
CMD ["node", "index.js"]
