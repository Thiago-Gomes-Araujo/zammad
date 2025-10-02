ARG RUBY_VERSION=3.4.6
ARG NODE_VERSION=22

FROM ruby:$RUBY_VERSION-slim AS base

WORKDIR /opt/zammad

ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT="test development" \
    RAILS_LOG_TO_STDOUT=true

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libpq5 postgresql-client-17 build-essential git libyaml-dev libpq-dev && \
    rm -rf /var/lib/apt/lists/*

# Node.js
FROM node:$NODE_VERSION-slim AS node
RUN npm -g install corepack && corepack enable pnpm && rm /usr/local/bin/yarn /usr/local/bin/yarnpkg

# Build stage
FROM base AS build

ARG COMMIT_SHA

COPY Gemfile Gemfile.lock vendor ./
RUN bundle install

COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=node /usr/local/bin /usr/local/bin

COPY package.json pnpm-lock.yaml ./
COPY .eslint-plugin-zammad/package.json .eslint-plugin-zammad/pnpm-lock.yaml .eslint-plugin-zammad/lib/ .eslint-plugin-zammad/
RUN pnpm install --frozen-lockfile

COPY . .

RUN touch db/schema.rb && \
    ZAMMAD_SAFE_MODE=1 DATABASE_URL=postgresql://zammad:/zammad bundle exec rake assets:precompile

# Final image
FROM base

ENV POSTGRESQL_DB=zammad_production \
    POSTGRESQL_HOST=zammad-postgresql \
    POSTGRESQL_PORT=5432 \
    POSTGRESQL_USER=zammad \
    POSTGRESQL_PASS=zammad

RUN groupadd --system --gid 1000 zammad && \
    useradd --create-home --home /opt/zammad --shell /bin/bash --uid 1000 --gid 1000 zammad && \
    mkdir -p /opt/zammad/storage /opt/zammad/tmp && \
    chown -R 1000:1000 /opt/zammad

COPY --chown=1000:1000 --from=build /usr/local/bundle /usr/local/bundle
COPY --chown=1000:1000 --from=build /opt/zammad /opt/zammad

USER 1000:1000
ENTRYPOINT ["/opt/zammad/bin/docker-entrypoint"]
