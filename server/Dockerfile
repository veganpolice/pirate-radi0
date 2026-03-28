FROM node:22-alpine
RUN apk add --no-cache python3 make g++
WORKDIR /app
COPY package*.json ./
RUN npm ci --production
COPY index.js db.js monitor.html ./
EXPOSE 3000
CMD ["node", "index.js"]
