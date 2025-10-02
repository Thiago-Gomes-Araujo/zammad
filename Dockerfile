ARG RUBY_VERSION=3.4.6

FROM ruby:$RUBY_VERSION-slim AS base

WORKDIR /opt/zammad

ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT="test development" \
    RAILS_LOG_TO_STDOUT=true

# Pacotes essenciais para gems nativas
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential git curl \
      libpq-dev libxml2-dev libxslt1-dev zlib1g-dev \
      libffi-dev libgmp-dev pkg-config nodejs npm && \
    rm -rf /var/lib/apt/lists/*

# Instala bundler
RUN gem install bundler -v 2.4.13

# Copia Gemfile e lock
COPY Gemfile Gemfile.lock ./

# Instala gems
RUN bundle lock --add-platform x86_64-linux && \
    bundle install --jobs 4 --retry 3

# Copia código da aplicação
COPY . .

# Precompila assets
RUN touch db/schema.rb && \
    bundle exec rake assets:precompile || true

# ===== Final Image =====
FROM base

RUN groupadd --system --gid 1000 zammad && \
    useradd --create-home --home /opt/zammad --shell /bin/bash --uid 1000 --gid 1000 zammad && \
    mkdir -p /opt/zammad/storage /opt/zammad/tmp && \
    chown -R 1000:1000 /opt/zammad

COPY --chown=1000:1000 --from=base /usr/local/bundle /usr/local/bundle
COPY --chown=1000:1000 --from=base /opt/zammad /opt/zammad

USER 1000:1000
ENTRYPOINT ["/opt/zammad/bin/docker-entrypoint"]
