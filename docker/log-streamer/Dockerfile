FROM node:23-alpine

WORKDIR /app

# Install curl and wget
RUN apk update && apk add --no-cache curl wget

# Copy package.json and package-lock.json
COPY package*.json ./

# Install dependencies
RUN npm install

# Copy source code
COPY server.js .

# Expose port
EXPOSE 8082

# Command to run the application
CMD ["node", "server.js"]