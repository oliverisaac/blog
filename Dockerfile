FROM node:22-slim AS builder
WORKDIR /usr/src/app
COPY quartz/package.json .
COPY quartz/package-lock.json* .
RUN npm ci

FROM node:22-slim as build
WORKDIR /usr/src/app
COPY --from=builder /usr/src/app/ /usr/src/app/
COPY quartz .

RUN mkdir /content

COPY ./content /content

RUN npx quartz build --directory=/content --output=/public

CMD ["npx", "quartz", "build", "--serve"]

# Use a lightweight base image
FROM nginx:alpine as release

COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy the static website files to the Nginx document root
COPY --from=build /public /public

