# Build local monorepo image
FROM node:20-alpine
RUN apk add --update libc6-compat python3 make g++
# needed for pdfjs-dist
RUN apk add --no-cache build-base cairo-dev pango-dev
# Install Chromium
RUN apk add --no-cache chromium
#install PNPM globaly
RUN npm install -g pnpm
ENV PUPPETEER_SKIP_DOWNLOAD=true
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser
ENV NODE_OPTIONS=--max-old-space-size=8192
WORKDIR /usr/src

# Clone the repository
RUN apk add --no-cache git
RUN git clone https://github.com/FlowiseAI/Flowise.git .

# Install dependencies and build
RUN pnpm install
RUN pnpm build

EXPOSE 3000
CMD [ "pnpm", "start" ]
