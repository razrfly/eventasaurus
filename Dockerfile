# Find eligible builder and runner images on Docker Hub. We use Ubuntu/Debian
# instead of Alpine to avoid DNS resolution issues in production.
#
# https://hub.docker.com/r/hexpm/elixir/tags?page=1&name=ubuntu
# https://hub.docker.com/_/ubuntu?tab=tags
#
# This file is based on these images:
#
#   - https://hub.docker.com/r/hexpm/elixir/tags - for the build image
#   - https://hub.docker.com/_/debian?tab=tags&page=1&name=bullseye-20250428-slim - for the release image
#   - https://pkgs.org/ - resource for finding needed packages
#   - Ex: hexpm/elixir:1.18.3-erlang-27.3.3-debian-bullseye-20250428-slim
#
ARG ELIXIR_VERSION=1.18.3
ARG OTP_VERSION=27.3.3
ARG DEBIAN_VERSION=bullseye-20250428-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} as builder

# install build dependencies (including Node.js for npm, libbsd for geocoding, and patch for applying fixes)
RUN apt-get update -y && apt-get install -y build-essential git curl libbsd-dev patch \
    && curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Patch geocoding library to use getline instead of fgetln for Linux compatibility
COPY docker/patches/geocoding_fix.patch ./docker/patches/
RUN if [ -f deps/geocoding/c_src/GeocodingDriver.cpp ]; then \
    echo "=== BEFORE PATCH ===" && \
    grep -n "char\* end = line" deps/geocoding/c_src/GeocodingDriver.cpp && \
    cd deps/geocoding && \
    patch -p1 < ../../docker/patches/geocoding_fix.patch && \
    echo "=== AFTER PATCH ===" && \
    grep -n "char\* end = line" c_src/GeocodingDriver.cpp && \
    echo "=== Geocoding patch applied successfully ==="; \
else \
    echo "ERROR: GeocodingDriver.cpp not found!"; \
    exit 1; \
fi

# Fix Makefile to link math library and correct library order
RUN if [ -f deps/geocoding/c_src/Makefile ]; then \
    sed -i 's/LDFLAGS+=-lstdc++/LDFLAGS+=-lm/' deps/geocoding/c_src/Makefile && \
    sed -i 's/\${CC} \${LDFLAGS} -o \$@ \$< \${LIBS}/\${CC} -o \$@ \$< \${LDFLAGS} \${LIBS} -lstdc++/' deps/geocoding/c_src/Makefile; \
fi

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/clerk.exs config/
RUN mix deps.compile

# Download and install TzWorld timezone geodata
# This creates the DETS file in deps/tz_world/priv/ which is then bundled in the release
# Without this, TzWorld.Backend.DetsWithIndexCache will fail with :enoent errors
RUN mix tz_world.update

COPY priv priv

COPY lib lib

COPY assets assets

# install npm dependencies
RUN cd assets && npm install

# compile assets
RUN mix assets.deploy

# Compile the release
RUN mix compile

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
  apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates librsvg2-bin \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

# set runner ENV
ENV MIX_ENV="prod"

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/eventasaurus ./

# Also copy all compiled static assets from the build stage (including CSS, JS, and images)
COPY --from=builder --chown=nobody:root /app/priv/static ./priv/static

USER nobody

# If using an environment that doesn't automatically reap zombie processes, it is
# advised to add an init process such as tini via `apt-get install`
# above and adding an entrypoint. See https://github.com/krallin/tini for details
# ENTRYPOINT ["/tini", "--"]

CMD ["/app/bin/server"]
