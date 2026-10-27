#!/usr/bin/env bats

load test_helper

# Providers tests need an instance that exists. A stand-in with only the
# plugin's version property passes verify_keycloak_name without deploying
# anything; every command below runs with --no-restart.
STANDIN="$TEST_APP-providers"

plugin_fn() {
  bash -c '
    export PLUGIN_CORE_AVAILABLE_PATH="${PLUGIN_CORE_AVAILABLE_PATH:-/var/lib/dokku/core-plugins/available}"
    export PLUGIN_ENABLED_PATH="${PLUGIN_ENABLED_PATH:-/var/lib/dokku/plugins/enabled}"
    export DOKKU_LIB_ROOT="${DOKKU_LIB_ROOT:-/var/lib/dokku}"
    source "$1/functions"
    shift
    "$@"
  ' _ "$BATS_TEST_DIRNAME/.." "$@"
}

create_standin() {
  plugin_fn fn-keycloak-set "$STANDIN" version 26.8.1
  # the dokku user runs the commands and must be able to read the sources
  SRC="$(mktemp -d /tmp/kc-providers.XXXXXX)"
  chmod 755 "$SRC"
  printf 'PK\003\004 not a real jar\n' >"$SRC/demo.jar"
  chmod 644 "$SRC/demo.jar"
}

sha256_of() {
  sha256sum "$1" | cut -d' ' -f1
}

providers_dir() {
  plugin_fn fn-keycloak-providers-dir "$STANDIN"
}

teardown() {
  [[ -n "$SRC" ]] || return 0
  rm -rf "$SRC" "$(dirname "$(providers_dir)")"
  plugin_fn fn-plugin-property-destroy keycloak "$STANDIN"
}

@test "(keycloak:help) lists the plugin" {
  run dokku keycloak:help
  assert_success
  assert_output_contains "Manage Keycloak instances"
}

@test "(help) includes keycloak in the global listing" {
  run dokku help
  assert_success
  assert_output_contains "keycloak"
}

@test "(keycloak:create) requires a name" {
  run dokku keycloak:create
  assert_failure
  assert_output_contains "Please specify a name"
}

@test "(keycloak:create) rejects invalid names" {
  run dokku keycloak:create "Bad_Name"
  assert_failure
  assert_output_contains "App name must begin with lowercase"
}

@test "(keycloak:create) rejects unknown flags and missing flag values" {
  run dokku keycloak:create "$TEST_APP" --bogus
  assert_failure
  assert_output_contains "Unknown flag: --bogus"

  run dokku keycloak:create "$TEST_APP" --version
  assert_failure
  assert_output_contains "--version requires a value"
}

@test "(keycloak:create) rejects unsafe or unsupported versions" {
  run dokku keycloak:create "$TEST_APP" --version '26.0;rm'
  assert_failure
  assert_output_contains "Invalid Keycloak version"

  run dokku keycloak:create "$TEST_APP" --version 24.0.5
  assert_failure
  assert_output_contains "not supported"
}

@test "(keycloak:create) rejects an invalid memory limit" {
  run dokku keycloak:create "$TEST_APP" --memory lots
  assert_failure
  assert_output_contains "Invalid memory limit"
}

@test "(keycloak:create) refuses to take over an existing app" {
  dokku apps:create "$TEST_APP-plain"
  run dokku keycloak:create "$TEST_APP-plain"
  dokku --force apps:destroy "$TEST_APP-plain"
  assert_failure
  assert_output_contains "not a Keycloak instance"
}

@test "(keycloak:create) leaves no state behind after a validation failure" {
  run dokku keycloak:create "$TEST_APP" --memory lots
  assert_failure
  run dokku keycloak:list
  refute_output_contains "$TEST_APP"
}

@test "(keycloak:info) fails for an unknown instance" {
  run dokku keycloak:info does-not-exist
  assert_failure
  assert_output_contains "Keycloak instance does-not-exist does not exist"
}

@test "(keycloak:info) requires a name" {
  run dokku keycloak:info
  assert_failure
  assert_output_contains "Please specify a Keycloak instance name"
}

@test "(keycloak:list) succeeds and ignores apps not managed by the plugin" {
  dokku apps:create "$TEST_APP-plain"
  run dokku keycloak:list
  dokku --force apps:destroy "$TEST_APP-plain"
  assert_success
  refute_output_contains "$TEST_APP-plain"
}

@test "(lifecycle) every instance command rejects an unknown instance" {
  local subcommand
  for subcommand in start stop restart logs destroy admin-credentials domains:set letsencrypt config:set config:get config:unset export import upgrade providers:add providers:list providers:remove; do
    run dokku "keycloak:$subcommand" does-not-exist
    assert_failure
    assert_output_contains "Keycloak instance does-not-exist does not exist"
  done
}

@test "(keycloak:destroy) rejects unknown flags" {
  run dokku keycloak:destroy does-not-exist --yes
  assert_failure
  assert_output_contains "Unknown flag: --yes"
}

@test "(keycloak:letsencrypt) rejects unknown flags and an empty email" {
  run dokku keycloak:letsencrypt does-not-exist --staging
  assert_failure
  assert_output_contains "Unknown flag: --staging"

  run dokku keycloak:letsencrypt does-not-exist --email
  assert_failure
  assert_output_contains "--email requires a value"
}

@test "(keycloak:config:set) rejects flags it does not know" {
  run dokku keycloak:config:set does-not-exist KC_LOG_LEVEL=INFO --restart-now
  assert_failure
  assert_output_contains "Unknown flag: --restart-now"
}

@test "(keycloak:import) rejects unknown flags" {
  run dokku keycloak:import does-not-exist realm.json --merge
  assert_failure
  assert_output_contains "Unknown flag: --merge"
}

@test "(keycloak:upgrade) rejects unknown flags and a missing version value" {
  run dokku keycloak:upgrade does-not-exist --latest
  assert_failure
  assert_output_contains "Unknown flag: --latest"

  run dokku keycloak:upgrade does-not-exist --version
  assert_failure
  assert_output_contains "--version requires a value"
}

@test "(keycloak:help) every entry has exactly one comma separating usage from description" {
  # the help table is split on commas, so a comma inside a description
  # breaks its columns
  source "$BATS_TEST_DIRNAME/../help-functions"
  run fn-keycloak-help-content
  assert_success
  local line
  while IFS= read -r line; do
    [[ "$(tr -cd ',' <<<"$line")" == "," ]] || { echo "bad help line: $line" >&2; return 1; }
  done <<<"$output"
}

@test "(keycloak:letsencrypt) accepts --force" {
  # reaching the instance check proves the flag parsed
  run dokku keycloak:letsencrypt does-not-exist --email ops@example.com --force
  assert_failure
  refute_output_contains "Unknown flag"
  assert_output_contains "Keycloak instance does-not-exist does not exist"
}

@test "(functions) config key lookup is not fooled by SIGPIPE under pipefail" {
  # a writer that keeps printing after the match makes 'cmd | grep -q' fail
  # with SIGPIPE under pipefail; the helper must still find the key
  run bash -c '
    export PLUGIN_CORE_AVAILABLE_PATH="${PLUGIN_CORE_AVAILABLE_PATH:-/var/lib/dokku/core-plugins/available}"
    export PLUGIN_ENABLED_PATH="${PLUGIN_ENABLED_PATH:-/var/lib/dokku/plugins/enabled}"
    export DOKKU_LIB_ROOT="${DOKKU_LIB_ROOT:-/var/lib/dokku}"
    source "$1/functions"
    set -o pipefail
    dokku() { echo KC_WANTED; seq 1 200000; }
    fn-keycloak-has-config-key app KC_WANTED && echo found
    dokku config:keys app | grep -qx KC_WANTED || echo "plain pipe fails too"
  ' _ "$BATS_TEST_DIRNAME/.."
  assert_success
  assert_output_contains "found"
  # proves the stub really triggers the failure the helper avoids
  assert_output_contains "plain pipe fails too"
}

@test "(keycloak:providers:add) requires --sha256" {
  create_standin
  run dokku keycloak:providers:add "$STANDIN" "$SRC/demo.jar"
  assert_failure
  assert_output_contains "--sha256 is required"

  run dokku keycloak:providers:add "$STANDIN" "$SRC/demo.jar" --sha256
  assert_failure
  assert_output_contains "--sha256 requires a value"

  run dokku keycloak:providers:add "$STANDIN" "$SRC/demo.jar" --sha256 abc123
  assert_failure
  assert_output_contains "Invalid --sha256"
}

@test "(keycloak:providers:add) refuses anything but https URLs" {
  create_standin
  run dokku keycloak:providers:add "$STANDIN" http://example.com/demo.jar --sha256 "$(sha256_of "$SRC/demo.jar")" --no-restart
  assert_failure
  assert_output_contains "Only https URLs are allowed"

  run dokku keycloak:providers:add "$STANDIN" ftp://example.com/demo.jar --sha256 "$(sha256_of "$SRC/demo.jar")" --no-restart
  assert_failure
  assert_output_contains "Only https URLs are allowed"
}

@test "(keycloak:providers:add) installs nothing when the checksum does not match" {
  create_standin
  run dokku keycloak:providers:add "$STANDIN" "$SRC/demo.jar" --sha256 "$(printf '0%.0s' {1..64})" --no-restart
  assert_failure
  assert_output_contains "Checksum mismatch"
  assert_output_contains "Nothing was installed"

  # no jar and no temporary file left behind
  run ls -A "$(providers_dir)"
  [[ -z "$output" ]]
  run dokku keycloak:providers:list "$STANDIN"
  assert_output_contains "No providers installed"
}

@test "(keycloak:providers:add) refuses a file that is not a jar" {
  create_standin
  echo "plain text" >"$SRC/text.jar"
  chmod 644 "$SRC/text.jar"
  run dokku keycloak:providers:add "$STANDIN" "$SRC/text.jar" --sha256 "$(sha256_of "$SRC/text.jar")" --no-restart
  assert_failure
  assert_output_contains "text.jar is not a jar file"

  run ls -A "$(providers_dir)"
  [[ -z "$output" ]]
}

@test "(keycloak:providers:add) refuses unsafe file names" {
  create_standin
  local name
  for name in 'bad;name.jar' '.hidden.jar' 'demo.zip'; do
    cp "$SRC/demo.jar" "$SRC/$name"
    chmod 644 "$SRC/$name"
    run dokku keycloak:providers:add "$STANDIN" "$SRC/$name" --sha256 "$(sha256_of "$SRC/demo.jar")" --no-restart
    assert_failure
    assert_output_contains "Invalid provider file name"
  done

  run dokku keycloak:providers:add "$STANDIN" "https://example.com/a%2F..%2Fb.jar" --sha256 "$(sha256_of "$SRC/demo.jar")" --no-restart
  assert_failure
  assert_output_contains "Invalid provider file name"
}

@test "(keycloak:providers:remove) fails for a jar that is not installed or has an unsafe name" {
  create_standin
  run dokku keycloak:providers:remove "$STANDIN" missing.jar --no-restart
  assert_failure
  assert_output_contains "Provider missing.jar is not installed in $STANDIN"

  run dokku keycloak:providers:remove "$STANDIN" ../../etc/passwd.jar --no-restart
  assert_failure
  assert_output_contains "Invalid provider file name"

  run dokku keycloak:providers:remove "$STANDIN"
  assert_failure
  assert_output_contains "Please specify the jar to remove"
}

@test "(keycloak:providers) add, list and remove a local jar without restarting" {
  create_standin
  local sum
  sum="$(sha256_of "$SRC/demo.jar")"

  run dokku keycloak:providers:add "$STANDIN" "$SRC/demo.jar" --sha256 "${sum^^}" --no-restart
  assert_success
  assert_output_contains "Installed demo.jar in $STANDIN"
  assert_output_contains "Skipping restart"
  run stat -c %a "$(providers_dir)/demo.jar"
  [[ "$output" == "644" ]]

  run dokku keycloak:providers:list "$STANDIN"
  assert_success
  assert_output_contains "demo.jar $(wc -c <"$SRC/demo.jar") $sum"

  # the same jar again is a no-op, a different one under that name is refused
  run dokku keycloak:providers:add "$STANDIN" "$SRC/demo.jar" --sha256 "$sum" --no-restart
  assert_success
  assert_output_contains "already installed"
  mkdir -m 755 "$SRC/other"
  printf 'PK\003\004 another build\n' >"$SRC/other/demo.jar"
  chmod 644 "$SRC/other/demo.jar"
  run dokku keycloak:providers:add "$STANDIN" "$SRC/other/demo.jar" --sha256 "$(sha256_of "$SRC/other/demo.jar")" --no-restart
  assert_failure
  assert_output_contains "A different demo.jar is already installed"

  run dokku keycloak:providers:remove "$STANDIN" demo.jar --no-restart
  assert_success
  assert_output_contains "Removed demo.jar from $STANDIN"
  run dokku keycloak:providers:list "$STANDIN"
  assert_output_contains "No providers installed"
}
