# syntax=docker/dockerfile:1

# For details, see https://github.com/devcontainers/images/tree/main/src/ruby
ARG RUBY_VERSION=4.0
ARG DISTRO_NAME=trixie
FROM mcr.microsoft.com/devcontainers/ruby:${RUBY_VERSION}-${DISTRO_NAME}

WORKDIR /app

# Install the Node.js version from .nvmrc via the pre-installed nvm
COPY .nvmrc /app/.nvmrc
RUN /bin/bash --login -i -c "nvm install"

# Common dependencies
# Using --mount to speed up build with caching, see https://github.com/moby/buildkit/blob/master/frontend/dockerfile/docs/reference.md#run---mount
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  --mount=type=tmpfs,target=/var/log \
  rm -f /etc/apt/apt.conf.d/docker-clean; \
  echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache; \
  apt-get update -qq && \
  DEBIAN_FRONTEND=noninteractive apt-get -yq dist-upgrade && \
  DEBIAN_FRONTEND=noninteractive apt-get install -yq --no-install-recommends \
    libicu-dev \
    libidn11-dev \
    ffmpeg \
    libvips42 \
    libpam-dev

# Disable download prompt for Corepack and activate the Yarn version from package.json
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0
RUN corepack enable && corepack prepare yarn@4.18.0 --activate

# Comment these lines if you want to install dependencies within a volume, not an image
COPY Gemfile Gemfile.lock /app/
RUN BUNDLE_FROZEN=true bundle install --jobs 4

# Use Bash as the default command
CMD ["/bin/bash"]
