FROM node:18-alpine

WORKDIR /app

COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile

COPY . .
COPY ./.env.example ./.env
RUN yarn build

CMD mkdir -p /artifacts-bind/server && cp -r \
  build/ \
  node_modules/ \
  package.json/ \
  /artifacts-bind/server/
