# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `keycloak:create` provisions a Dokku app, a dedicated PostgreSQL database
  and a production-mode Keycloak (`start --optimized`) with a generated admin
  password. A failed create can be re-run to resume.
- `keycloak:destroy`, `keycloak:info`, `keycloak:list`, `keycloak:start`,
  `keycloak:stop`, `keycloak:restart` and `keycloak:logs`.
- `keycloak:admin-credentials`, the only command that prints the password.
- `keycloak:domains:set` pins Keycloak's hostname to the public domain, and
  `keycloak:letsencrypt` enables TLS through dokku-letsencrypt. Its `--force`
  flag replaces a certificate that is still valid, such as one from the
  staging server.
- `keycloak:config:set`, `config:get` and `config:unset` for `KC_*` and
  `JAVA_OPTS*` settings. Build-time options trigger an image rebuild.
- `keycloak:export` and `keycloak:import` for realm JSON, including over ssh
  through stdin.
- `keycloak:upgrade` backs up the database before moving to another Keycloak
  release, and refuses downgrades.
- Zero-downtime deploys gated on Keycloak's `/health/ready`.
- Keycloak 26.8.1 as the pinned default. Dokku 0.36.0 is the minimum.
- Test suites (bats) and a GitHub Actions workflow running them against
  Dokku in Docker.
- `keycloak:providers:add`, `providers:list` and `providers:remove` manage
  Keycloak extension jars per instance. A jar is installed only when it
  matches the given SHA-256 (https URLs or local paths), is built into the
  image, and survives plugin updates and `keycloak:upgrade`. A jar that
  breaks the build or the readiness check is removed again. Instances
  rebuild once on their next restart after updating the plugin, because the
  image definition changed.

### Fixed

- `keycloak:create` no longer prints the database password; the output of
  `postgres:create` and `postgres:link` contained it twice.
- Keycloak now runs as PID 1 in its container, so it no longer warns that
  graceful shutdown may not work.
- `keycloak:create` deploys once instead of twice. The admin user is created
  with `kc.sh bootstrap-admin`, reading the password from stdin, so it is
  never part of the app's config or a container's environment.
- Each instance gets its own Docker network (`keycloak-<name>`) shared with
  its database, so Docker no longer warns about links on the default bridge.
- Keycloak's deprecated sticky-session route is disabled, removing its
  startup warning.
- Config commands no longer report a set key as missing at random, and
  instances deploy on Docker-based Dokku installs and on Dokku 0.36.
- `keycloak:restart`, `start`, `upgrade` and the config commands remove a
  docker link to the database that came back (for example after a manual
  re-link), instead of failing to start the new container.

[Unreleased]: https://github.com/shebang-labs/dokku-keycloak/commits/main
