# Build context used by the keycloak plugin. The plugin supplies
# KEYCLOAK_IMAGE, writes build.env with the instance's build-time options and
# fills providers/ with the instance's extension jars (empty without any).
ARG KEYCLOAK_IMAGE=quay.io/keycloak/keycloak:26.8.1

FROM ${KEYCLOAK_IMAGE} AS builder
ENV KC_DB=postgres \
    KC_HEALTH_ENABLED=true \
    KC_METRICS_ENABLED=true
COPY build.env /tmp/build.env
# Keycloak only registers providers that are present at `kc.sh build`.
COPY providers/ /opt/keycloak/providers/
# `start --optimized` only works on an image whose build-time options were
# fixed here, so they are applied before `kc.sh build`.
RUN set -a && . /tmp/build.env && set +a && /opt/keycloak/bin/kc.sh build

FROM ${KEYCLOAK_IMAGE}
# Dokku's nginx does not route by session, and Keycloak keeps sessions in its
# shared cache and database, so the node route in the session cookie is not
# needed. Keycloak deprecates the option and asks for it to be disabled.
# Overridable with keycloak:config:set.
ENV KC_SPI_STICKY_SESSION_ENCODER__INFINISPAN__SHOULD_ATTACH_ROUTE=false
COPY --from=builder /opt/keycloak/ /opt/keycloak/
COPY docker-entrypoint.sh /opt/keycloak/bin/dokku-entrypoint.sh
# Dokku reads app.json from the image WORKDIR for image deploys; upstream
# leaves WORKDIR at /.
COPY app.json /app.json
ENTRYPOINT ["/opt/keycloak/bin/dokku-entrypoint.sh"]
CMD ["start", "--optimized"]
