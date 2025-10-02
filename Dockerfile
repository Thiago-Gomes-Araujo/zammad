ARG RUBY_VERSION=3.4.6
ARG NODE_VERSION=22

# ===== Base Ruby =====
FROM ruby:$RUBY_VERSION-slim AS base

WORKDIR /opt/zammad

ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT="test development" \
    RAILS_LOG_TO_STDOUT=true \
    CERT_DIR=/opt/zammad/tmp/certs

# Pacotes essenciais para gems nativas e openssl
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      curl libpq5 postgresql-client-17 \
      build-essential git libyaml-dev libpq-dev \
      libxml2-dev libxslt1-dev zlib1g-dev \
      openssl fakeroot && \
    mkdir -p $CERT_DIR && \
    rm -rf /var/lib/apt/lists/*

# ===== Node.js =====
FROM node:$NODE_VERSION-slim AS node
RUN npm -g install corepack && corepack enable pnpm && \
    rm /usr/local/bin/yarn /usr/local/bin/yarnpkg

# ===== Build Stage =====
FROM base AS build

ARG COMMIT_SHA

# Copia Gemfile e lock
COPY Gemfile Gemfile.lock vendor ./

# Normaliza plataforma e instala gems
RUN bundle lock --add-platform x86_64-linux && \
    bundle install --jobs 4 --retry 3

# Copia Node.js e instala dependências JS
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=node /usr/local/bin /usr/local/bin

COPY package.json pnpm-lock.yaml ./
COPY .eslint-plugin-zammad/package.json .eslint-plugin-zammad/pnpm-lock.yaml .eslint-plugin-zammad/lib/ .eslint-plugin-zammad/
RUN pnpm install --frozen-lockfile

# Copia código da aplicação
COPY . .

# Precompila assets
RUN touch db/schema.rb && \
    ZAMMAD_SAFE_MODE=1 DATABASE_URL=postgresql://zammad:/zammad bundle exec rake assets:precompile

# ===== Final Image =====
FROM base

ENV POSTGRESQL_DB=zammad_production \
    POSTGRESQL_HOST=zammad-postgresql \
    POSTGRESQL_PORT=5432 \
    POSTGRESQL_USER=zammad \
    POSTGRESQL_PASS=zammad

# Cria usuário Zammad e diretórios
RUN groupadd --system --gid 1000 zammad && \
    useradd --create-home --home /opt/zammad --shell /bin/bash --uid 1000 --gid 1000 zammad && \
    mkdir -p /opt/zammad/storage /opt/zammad/tmp /opt/zammad/tmp/certs && \
    chown -R 1000:1000 /opt/zammad

# Copia artefatos do build
COPY --chown=1000:1000 --from=build /usr/local/bundle /usr/local/bundle
COPY --chown=1000:1000 --from=build /opt/zammad /opt/zammad

# Copia arquivos de certificado se existirem
COPY --chown=1000:1000 ["ca.cnf", "intermediate.cnf", "pass.secret", "$CERT_DIR/"]

USER 1000:1000
ENTRYPOINT ["/opt/zammad/bin/docker-entrypoint"]
