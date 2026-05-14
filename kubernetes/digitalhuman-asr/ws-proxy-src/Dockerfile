FROM node:22-alpine
WORKDIR /app
COPY package.json .
RUN npm install --omit=dev
COPY server.js .
COPY protos /protos
EXPOSE 8000
ENV PROTO_DIR=/protos
CMD ["node", "server.js"]
