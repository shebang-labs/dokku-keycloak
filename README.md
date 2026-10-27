# dokku-keycloak

[![CI](https://github.com/shebang-labs/dokku-keycloak/actions/workflows/ci.yml/badge.svg)](https://github.com/shebang-labs/dokku-keycloak/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A [Dokku](https://dokku.com) plugin that provisions and manages
[Keycloak](https://www.keycloak.org) end to end: a production-mode Keycloak
backed by its own PostgreSQL database, with a generated admin password,
hostname and proxy settings, Let's Encrypt TLS, realm export and import, and
upgrades that back up the database first.

```sh
sudo dokku plugin:install https://github.com/shebang-labs/dokku-keycloak.git keycloak
dokku keycloak:create auth
dokku keycloak:domains:set auth auth.example.com
dokku keycloak:letsencrypt auth --email ops@example.com
dokku keycloak:admin-credentials auth
```

Maintained by [Shebang Labs](https://shebanglabs.io).

## Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Command reference](#command-reference)
- [Configuration](#configuration)
- [Extensions (providers)](#extensions-providers)
- [Backup and restore](#backup-and-restore)
- [Upgrading](#upgrading)
- [Troubleshooting](#troubleshooting)
- [How it works](#how-it-works)
- [Development](#development)
- [Credits](#credits)
- [License](#license)

## Features

- **One command to a running instance.** `keycloak:create` makes the Dokku
  app, a dedicated PostgreSQL service, links them and deploys Keycloak.
- **Production mode.** Keycloak runs with `start --optimized` on an image
  built with PostgreSQL, health and metrics baked in. The embedded H2 database
  is never used.
- **Safe admin bootstrap.** A random 48-character admin password is generated
  and stored with mode `0600`. It is handed to Keycloak once, on stdin, and is
  never part of the app's config or a container's environment.
- **Correct behind Dokku's nginx.** `KC_PROXY_HEADERS=xforwarded`, a pinned
  hostname, and TLS through
  [dokku-letsencrypt](https://github.com/dokku/dokku-letsencrypt). Health and
  metrics stay off the public interface.
- **Zero-downtime changes.** Deploys and restarts wait for Keycloak's
  `/health/ready` before switching traffic.
- **Config that knows Keycloak.** Runtime options cost a restart. Build-time
  options such as `KC_FEATURES` trigger a rebuild automatically.
- **Extensions that stay installed.** Provider jars are checksum-verified,
  built into the image and kept across plugin updates and Keycloak upgrades.
- **Realm export and import** through Keycloak's own `kc.sh`, usable over ssh.
- **Upgrades with a safety net.** The database is dumped before every upgrade,
  and downgrades are refused.
- **Re-runnable commands.** Every command is safe to repeat. Failures exit
  non-zero with a message that says what to do.

## Requirements

| Requirement          | Version / notes                                                                 |
| -------------------- | ------------------------------------------------------------------------------- |
| Dokku                | **0.36.0 or newer** (tested on 0.36.0 and 0.38.31)                              |
| Host OS              | Ubuntu 24.04 tested; other Dokku-supported Ubuntu and Debian releases should work |
| Memory               | 2 GB per instance by default, plus PostgreSQL and the host (4 GB host minimum)  |
| dokku-postgres       | Required. `sudo dokku plugin:install https://github.com/dokku/dokku-postgres.git postgres` |
| dokku-letsencrypt    | Required for `keycloak:letsencrypt`. `sudo dokku plugin:install https://github.com/dokku/dokku-letsencrypt.git letsencrypt` |
| Keycloak             | **26.8.1** by default; 26.8.0 also tested. Other 26.x releases are accepted but untested. |

The plugin never installs other plugins for you. If one is missing, the
command that needs it fails and prints the exact install command.

### Verification status

Every command is covered by the test suites, which pass on Dokku 0.36.0 and
0.38.31 running on Ubuntu 24.04 (arm64). Two things are **not yet verified**
on a real server:

- **Let's Encrypt issuance.** The `keycloak:letsencrypt` checks and error
  handling are tested, and TLS behind Dokku's nginx is tested with a
  self-signed certificate. A real certificate from Let's Encrypt has not been
  requested yet.
- **x86_64 hosts.** All testing so far ran on arm64. The plugin is plain Bash
  and the Keycloak image is multi-architecture, so no difference is expected.

## Installation

```sh
sudo dokku plugin:install https://github.com/dokku/dokku-postgres.git postgres
sudo dokku plugin:install https://github.com/dokku/dokku-letsencrypt.git letsencrypt
sudo dokku plugin:install https://github.com/shebang-labs/dokku-keycloak.git keycloak
```

To pin a release of the plugin:

```sh
sudo dokku plugin:install https://github.com/shebang-labs/dokku-keycloak.git --committish v0.1.0 --name keycloak
```

To update the plugin later, run `sudo dokku plugin:update keycloak`.

## Quick start

1. Point a DNS record (for example `auth.example.com`) at the Dokku host.

2. Create the instance. The first run downloads Keycloak and takes a few minutes:

   ```sh
   dokku keycloak:create auth
   ```

3. Give it its public name. Keycloak issues tokens and redirects for this name only:

   ```sh
   dokku keycloak:domains:set auth auth.example.com
   ```

4. Enable HTTPS:

   ```sh
   dokku keycloak:letsencrypt auth --email ops@example.com
   dokku letsencrypt:cron-job --add   # once per host: renew certificates automatically
   ```

5. Log in at `https://auth.example.com/admin/` with:

   ```sh
   dokku keycloak:admin-credentials auth
   ```

   Keycloak marks this bootstrap admin as temporary. Create a permanent admin
   user in the `master` realm, then delete the bootstrap one.

## Command reference

`<name>` is the instance name. It is also the Dokku app name, so every
regular `dokku` command (`ps:report`, `logs`, `domains:report`,
`letsencrypt:list`, ...) works on it too.

| Command | Description |
| ------- | ----------- |
| `keycloak:create <name> [--version <tag>] [--memory <limit>]` | Create an instance with its own PostgreSQL database |
| `keycloak:destroy <name> [--force]` | Destroy an instance and its database |
| `keycloak:info <name>` | Show version, status, database, hostname and URLs |
| `keycloak:list` | List instances |
| `keycloak:start <name>` / `stop <name>` | Start or stop an instance |
| `keycloak:restart <name>` | Restart, rebuilding first if build-time options changed |
| `keycloak:logs <name> [-t] [-n <lines>]` | Show logs (`-t` to follow) |
| `keycloak:admin-credentials <name>` | Print the bootstrap admin username and password |
| `keycloak:domains:set <name> <domain> [<domain>...]` | Set domains and pin Keycloak's hostname to the first |
| `keycloak:letsencrypt <name> [--email <email>] [--force]` | Enable Let's Encrypt TLS |
| `keycloak:config:set <name> KEY=VALUE... [--no-restart]` | Set `KC_*` / `JAVA_OPTS*` options and apply them |
| `keycloak:config:get <name> <KEY>` | Print one option |
| `keycloak:config:unset <name> KEY... [--no-restart]` | Remove options and apply the change |
| `keycloak:export <name> [<realm>]` | Export one realm, or all, as JSON on stdout |
| `keycloak:import <name> <file\|-> [--override]` | Import realms from a JSON export |
| `keycloak:upgrade <name> [--version <tag>] [--force]` | Back up the database and move to another Keycloak release |
| `keycloak:providers:add <name> <https-url\|path> --sha256 <hex> [--no-restart]` | Install an extension jar and rebuild |
| `keycloak:providers:list <name>` | List installed extension jars with size and SHA-256 |
| `keycloak:providers:remove <name> <jar> [--no-restart]` | Remove an extension jar and rebuild |

`dokku keycloak:help` prints the same list.

### `keycloak:create`

```sh
dokku keycloak:create auth
dokku keycloak:create auth --version 26.8.1 --memory 3g
```

This command:

- creates the app `<name>` and the PostgreSQL service `<name>-db` on a private
  Docker network `keycloak-<name>`, and links them
- applies the defaults listed under [Configuration](#configuration)
- builds the optimized image and deploys it
- creates the temporary admin user with `kc.sh bootstrap-admin` in a one-off
  container, passing the password on stdin

`--memory` takes Docker's format (`2048m`, `3g`). Keycloak sizes its Java
heap from this limit.

If the command fails half way, for example because of a network error, run it
again. It resumes where it stopped. Running it again on a finished instance
fails with `already exists` and changes nothing. It also refuses to take over
an existing app that is not a Keycloak instance.

### `keycloak:destroy`

```sh
dokku keycloak:destroy auth          # asks you to type the name
dokku keycloak:destroy auth --force  # no prompt, for scripts
```

This removes the app, its database, its network and every realm and user in
it. Export
what you need first. Backups made by `keycloak:upgrade` are kept. If the app
is removed with plain `dokku apps:destroy`, the plugin forgets the instance
but leaves the database in place, and prints how to remove it.

### `keycloak:domains:set`

```sh
dokku keycloak:domains:set auth auth.example.com login.example.com
```

This sets the Dokku domains and pins `KC_HOSTNAME` to the **first** one, with
strict hostname checking. Every domain serves Keycloak, but tokens, issuer
URLs and redirects always use the first. No scheme is configured, so Keycloak
follows the `X-Forwarded-Proto` header from nginx. Enabling TLS later needs
no change here. Re-running with the same first domain does not restart.

### `keycloak:letsencrypt`

```sh
dokku keycloak:letsencrypt auth --email ops@example.com
dokku keycloak:letsencrypt auth --force    # replace a certificate that is still valid
```

`--email` is stored for the app. Without it, an app or global letsencrypt
email (`dokku letsencrypt:set --global email ...`) must already be set,
otherwise the command explains how to set one. Set the domain with
`keycloak:domains:set` first.

Requests are skipped while a valid certificate exists. `--force` requests a
new one anyway. Use it after testing against the Let's Encrypt staging
server, whose certificates browsers do not trust:

```sh
dokku letsencrypt:set auth server https://acme-staging-v02.api.letsencrypt.org/directory
dokku keycloak:letsencrypt auth --email ops@example.com     # staging certificate
dokku letsencrypt:set auth server                           # back to production
dokku keycloak:letsencrypt auth --force                     # replace it
```

### `keycloak:config:*`

```sh
dokku keycloak:config:set auth KC_LOG_LEVEL=INFO,org.keycloak.events:DEBUG
dokku keycloak:config:set auth KC_FEATURES=token-exchange
dokku keycloak:config:get auth KC_LOG_LEVEL
dokku keycloak:config:unset auth KC_LOG_LEVEL
```

- Only `KC_*` and `JAVA_OPTS*` keys are accepted. Use `dokku config:set` for
  anything else.
- `KC_DB` cannot be changed, because the image is built for PostgreSQL.
- `config:set` and `config:unset` print key names only, never values, so
  secrets such as SMTP or LDAP passwords are safe to set. `config:get`
  prints the one value you ask for.
- Setting a value that is already in place does nothing.
- [Build-time options](#build-time-and-runtime-options) rebuild the image
  and redeploy. All other options restart the instance. Both are zero-downtime.
- `--no-restart` only stores the change. The next `keycloak:restart`
  applies it, including any needed rebuild.

### `keycloak:export` and `keycloak:import`

```sh
dokku keycloak:export auth myrealm > myrealm.json      # one realm
dokku keycloak:export auth > all-realms.json           # every realm
ssh dokku@host keycloak:export auth myrealm > myrealm.json

dokku keycloak:import auth myrealm.json                # skips realms that exist
dokku keycloak:import auth myrealm.json --override     # replaces them
ssh dokku@host keycloak:import auth - < myrealm.json   # from stdin
```

Both commands run Keycloak's own `kc.sh export` / `kc.sh import` in a
throwaway container of the instance, so the format is the standard Keycloak
one. Exports include users with their password hashes and client secrets, so
store them like credentials. Import restarts the instance afterwards so the
running server picks up the new data.

Commands run as the `dokku` user. A file that only root can read must be
streamed instead: `dokku keycloak:import auth - < /root/realm.json`.

### `keycloak:upgrade`

```sh
dokku keycloak:upgrade auth                    # to the release this plugin pins
dokku keycloak:upgrade auth --version 26.8.1   # to a specific release
```

See [Upgrading](#upgrading).

### `keycloak:providers:*`

See [Extensions (providers)](#extensions-providers).

## Configuration

### Set by `keycloak:create`

| Setting | Value | Why |
| ------- | ----- | --- |
| Keycloak version | `26.8.1` (`--version`) | Pinned and tested with this plugin release |
| Memory limit | `2048m` (`--memory`) | Keycloak sizes its heap from the container limit |
| Start command | `start --optimized` | Production mode on a pre-built image |
| `KC_DB` (build time) | `postgres` | The linked dokku-postgres service |
| `KC_HEALTH_ENABLED`, `KC_METRICS_ENABLED` (build time) | `true` | `/health/*` and `/metrics` on management port 9000, not public |
| `KC_PROXY_HEADERS` | `xforwarded` | Trust nginx's `X-Forwarded-*` headers |
| `KC_HTTP_ENABLED` | `true` | TLS ends at nginx; Keycloak serves HTTP on 8080 |
| `KC_HOSTNAME_STRICT` | `false`, then `true` after `domains:set` | Usable before a domain exists, strict after |
| `KC_HOSTNAME` | first domain from `domains:set` | Stable issuer and redirect URLs |
| Port mapping | `http:80:8080` (`https:443:8080` added by Let's Encrypt) | Only the HTTP listener is published |
| Deploy healthcheck | `/health/ready` on port 9000 | Traffic switches only once Keycloak is ready |
| Network | `keycloak-<name>` | The database is reached over a private network instead of a deprecated docker link. The app also stays on the default bridge so Dokku's nginx can reach it, including on Docker-based Dokku installs |
| `DATABASE_URL` | set by `postgres:link` | Turned into `KC_DB_URL`/`KC_DB_USERNAME`/`KC_DB_PASSWORD` when the container starts |

To use an external database, set `KC_DB_URL`, `KC_DB_USERNAME` and
`KC_DB_PASSWORD` with `keycloak:config:set`. Explicit values win over
`DATABASE_URL`.

### Build-time and runtime options

Keycloak applies some options only when the image is built (`kc.sh build`).
The plugin recognises these and rebuilds automatically:

`KC_FEATURES`, `KC_FEATURES_DISABLED`, `KC_FEATURE_*`, `KC_DB_DRIVER`,
`KC_DB_KIND_*`, `KC_TRANSACTION_XA_ENABLED`, `KC_HTTP_RELATIVE_PATH`,
`KC_HTTPS_CLIENT_AUTH`, `KC_HEALTH_ENABLED`, `KC_METRICS_ENABLED`,
`KC_HTTP_MANAGEMENT_HEALTH_ENABLED`, `KC_HTTP_MANAGEMENT_RELATIVE_PATH`,
`KC_VAULT`, `KC_TRACING_ENABLED`, `KC_TELEMETRY_LOGS_ENABLED`,
`KC_FIPS_MODE` and `KC_OPENAPI_ENABLED`, among others. The complete list,
taken from `kc.sh build --help-all`, is `KEYCLOAK_BUILD_OPTIONS` in
[`config`](config).
Everything else, such as `KC_LOG_LEVEL`, `KC_SPI_*` or `JAVA_OPTS_APPEND`,
is a runtime option.

Changing `KC_HTTP_MANAGEMENT_RELATIVE_PATH` or disabling health moves or
removes `/health/ready`, which the deploy healthcheck relies on.

### Host-wide settings

Set these in a file under `/home/dokku/.dokkurc/`, which Dokku reads before
every command:

```sh
echo 'export KEYCLOAK_IMAGE_REPO=registry.example.com/keycloak/keycloak' | sudo tee /home/dokku/.dokkurc/keycloak
sudo chown dokku:dokku /home/dokku/.dokkurc/keycloak
```


| Variable | Default | Purpose |
| -------- | ------- | ------- |
| `KEYCLOAK_IMAGE_REPO` | `quay.io/keycloak/keycloak` | Use a mirror, for example on air-gapped hosts |

## Extensions (providers)

Some Keycloak extensions (SPIs such as event listeners, custom
authenticators or admin endpoints) must be part of the image: Keycloak only
loads jars that are in `/opt/keycloak/providers/` when `kc.sh build` runs.
`keycloak:providers:add` installs a jar for one instance and rebuilds it.

For example, the
[SCIM outbound provisioning extension](https://github.com/shebang-labs/scim-outbound-for-keycloak):

```sh
dokku keycloak:providers:add auth \
  https://github.com/shebang-labs/scim-outbound-for-keycloak/releases/download/v0.1.0/scim-outbound-for-keycloak-0.1.0.jar \
  --sha256 cb920b0b01f2f449fc506fcbb85131e624f2d4e682f029ea7cd50f52d9e28f09
dokku keycloak:providers:list auth
```

- `--sha256` is mandatory. An extension runs inside Keycloak with access to
  every realm, so use the checksum its author publishes, not one you computed
  from the download.
- Only `https://` URLs are accepted, redirects included. On a host without
  internet access, copy the jar there and pass its path instead of a URL. The
  `dokku` user must be able to read it.
- The jar is downloaded to a temporary file and installed only after the
  checksum, the jar format and the file name
  (`[A-Za-z0-9][A-Za-z0-9._-]*.jar`, taken from the URL or path) check out.
  On any failure nothing is installed.
- The instance is then rebuilt and deployed with the usual readiness check,
  so the change is zero-downtime. If the build or the readiness check fails,
  the jar is removed again and the running instance stays as it was.
- Adding a jar that is already installed with the same checksum does
  nothing. A different jar under the same name is refused: remove the old
  one first.
- `--no-restart` only installs the jar. The next `keycloak:restart` builds it
  in.

Jars are stored per instance in
`/var/lib/dokku/data/keycloak/<name>/providers/`, outside the plugin, so they
survive `dokku plugin:update` and are rebuilt into every new image,
including the one `keycloak:upgrade` builds. Check that an extension supports
the target Keycloak release before upgrading. `keycloak:destroy` deletes
them.

To roll an extension back, remove it. The instance is rebuilt without it:

```sh
dokku keycloak:providers:remove auth scim-outbound-for-keycloak-0.1.0.jar
```

Removing the jar does not remove data the extension wrote, such as its own
database tables or realm settings.

## Backup and restore

There are two levels, and production setups should use both.

**Database backups (everything).** The Keycloak database holds every realm,
user, session and setting. dokku-postgres can back it up on a schedule to
S3-compatible storage:

```sh
dokku postgres:backup-auth auth-db <aws-access-key-id> <aws-secret-access-key>
dokku postgres:backup-schedule auth-db "0 3 * * *" my-backup-bucket
dokku postgres:backup auth-db my-backup-bucket            # one-off
```

Or take a local dump and restore it:

```sh
dokku postgres:export auth-db > auth-db.dump
dokku keycloak:stop auth
dokku postgres:import auth-db < auth-db.dump
dokku keycloak:start auth
```

See the [dokku-postgres documentation](https://github.com/dokku/dokku-postgres)
for encryption and other storage options.

**Realm exports (portable).** `keycloak:export` produces Keycloak's JSON
format. Use it to copy realms between instances or environments, or to keep
realm configuration in version control (strip users and secrets first).

`keycloak:upgrade` also writes a database dump before every upgrade, to
`/var/lib/dokku/data/keycloak/<name>/backups/`.

## Upgrading

### Keycloak

1. Read the [Keycloak upgrading guide](https://www.keycloak.org/docs/latest/upgrading/)
   for every release between your version and the target.
2. Run the upgrade:

   ```sh
   dokku keycloak:upgrade auth
   ```

   With no flag, the target is the release pinned by the installed plugin.
   Update the plugin first (`sudo dokku plugin:update keycloak`) to get the
   newest tested release, or pass `--version` to choose one yourself.

3. The command:
   1. dumps the database to `/var/lib/dokku/data/keycloak/auth/backups/`
   2. builds the new image
   3. deploys it with the usual readiness check; Keycloak migrates the schema
      on first start
   4. prints where the backup is

If the new release does not become ready, the old container keeps serving,
the recorded version is put back, and the command prints the exact
`postgres:import` line to restore the backup if needed. Upgrading to the
version already running does nothing. Downgrades are refused, because an
older Keycloak cannot run on a migrated schema. Restore a backup instead.

### The plugin

```sh
sudo dokku plugin:update keycloak
```

Updating the plugin does not touch running instances. Their version only
changes when you run `keycloak:upgrade`.

When an update changes the image definition, as the release that added
[extensions](#extensions-providers) did, the next `keycloak:restart`, config
change, provider change or upgrade of each instance rebuilds its image once.
That rebuild is a zero-downtime deploy like any other. `keycloak:start`, a
host reboot or Dokku's own `ps:restart` keep the existing image.

## Troubleshooting

**`keycloak:create` takes a long time the first time.** The first build
downloads the Keycloak image (around 500 MB). Later builds are cached.

**The deploy fails with a failed healthcheck.** Check `dokku keycloak:logs
<name> -n 200`. Common causes:

- a memory limit that is too low; try `--memory 2048m` or more
- an invalid `KC_*` option
- a database that cannot be reached

Re-run the same command after fixing it. Creates resume and deploys retry.

**Login redirects to the wrong host, or `Invalid redirect uri`.** Tokens and
redirects always use the first domain passed to `keycloak:domains:set`.
Check it with `dokku keycloak:config:get <name> KC_HOSTNAME`.

**Issuer URLs use `http://` behind HTTPS.** Make sure TLS ends at Dokku's
nginx (`dokku letsencrypt:list`). If another proxy or load balancer sits in
front, it must send `X-Forwarded-Proto: https`, and nginx must be configured
to pass it through.

**`keycloak:letsencrypt` fails.** Let's Encrypt must reach the domain on
port 80 from the internet, so check the DNS record and firewall. The
detailed log is in the command output. The request is not repeated while a
valid certificate exists; add `--force` to replace it, for example a staging
certificate.

**`Cannot read <file> as the dokku user`.** Stream the file:
`dokku keycloak:import <name> - < <file>`.

**`Account is not fully set up` when a user logs in.** This is Keycloak's
user profile feature: the user is missing a required attribute such as email
or first name. Fill it in from the admin console.

**`WARNING: Keycloak is running inside a container, but is not PID 1`.** This
is harmless. Dokku runs containers with an init process, and `kc.sh` passes
stop signals on to Keycloak, so shutdowns stay graceful.

**Two `Strict-Transport-Security` headers.** Keycloak sends its own HSTS
header and Dokku's nginx adds one when TLS is enabled. Browsers use the
first. To keep only Keycloak's, run `dokku nginx:set <name> hsts false`.

**A deploy fails with `not attached to default bridge network`.** A docker
link to the database came back, for example after `dokku postgres:unlink`
and `dokku postgres:link`. The database is only on the instance's private
network, so containers with the link cannot start; the running container
keeps serving. `postgres:link` restarts the app itself, and that restart
fails while the command still exits 0. Fix it with:

```sh
dokku keycloak:restart <name>
```

`keycloak:restart`, `keycloak:start`, `keycloak:upgrade` and the
`keycloak:config:*` commands remove the stray link before starting
containers. When re-linking on purpose, pass `--no-restart` to
`postgres:link` and then run `keycloak:restart`.

**Debugging the plugin.** Prefix a command with `dokku --trace` to print
every step. Trace output includes configuration values such as the admin and
database passwords, so do not share it unedited.

## How it works

- An instance is a regular Dokku app with the same name, deployed with
  `git:from-image`. The plugin's state (version, database name, admin
  password, build hash) lives in Dokku's property store under
  `/var/lib/dokku/config/keycloak/<name>/`, with mode `0600`.
- The image is built from [`image/Dockerfile`](image/Dockerfile) in two
  stages: `kc.sh build` with the instance's build-time options and provider
  jars, then a clean runtime image. A hash of the inputs decides whether a change needs a
  rebuild or only a restart.
- The [entrypoint](image/docker-entrypoint.sh) turns `DATABASE_URL` into
  Keycloak's database settings when the container starts, so credentials never
  appear in extra config vars or logs.
- [`image/app.json`](image/app.json) declares the readiness healthcheck that
  Dokku waits for during deploys.
- Export and import start a detached one-off container of the app and drive
  it with `docker exec -i`. That passes stdin through, which `dokku run`
  does not without a TTY.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for the local VM setup (sslip.io
domains, self-signed TLS, Mailpit for email) and for how to run
`make lint`, `make test` and `make test-e2e`.

## License

[MIT](LICENSE) © [Shebang Labs](https://shebanglabs.io)
