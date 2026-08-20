#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TEST_DIR/.." && pwd)"
TEMP_ROOT="$(mktemp -d)"
readonly TEST_DIR PLUGIN_ROOT TEMP_ROOT
trap 'rm -rf -- "$TEMP_ROOT"' EXIT

readonly MOCK_BIN="$TEMP_ROOT/bin"
readonly CASE_ROOT="$TEMP_ROOT/case"
readonly PLUGIN_DIR="$CASE_ROOT/plugin"
readonly CONFIG_PATH="$CASE_ROOT/ilyazar-btop.conf"
readonly BACKUP_PATH="$CONFIG_PATH.before-plugin"
readonly ABSENT_PATH="$CONFIG_PATH.absent-before-plugin"
readonly STATE_PATH="$CASE_ROOT/plugin-state"

mkdir -p "$MOCK_BIN"

extract_command() {
  local property="$1"

  sed -n "/readonly property string ${property}: \[/,/  \].join(\"\\\\n\")/p" \
    "$PLUGIN_ROOT/Service.qml" |
    sed -n 's/^[[:space:]]*\(".*"\),\{0,1\}$/\1/p' |
    jq -Rr fromjson
}

baseline_command="$(extract_command baselineCommand)"
teardown_command="$(extract_command teardownCommand)"
readonly baseline_command teardown_command

[[ -n $baseline_command && -n $teardown_command ]]
bash -n <<<"$baseline_command"
bash -n <<<"$teardown_command"
grep -Fq 'Component.onDestruction: root.teardown()' \
  "$PLUGIN_ROOT/Service.qml"

cat >"$MOCK_BIN/omarchy" <<'MOCK'
#!/bin/bash

set -euo pipefail

state="$(cat "$BTOP_TEST_STATE_PATH")"
case "$state" in
enabled | disabled)
  enabled=false
  [[ $state == enabled ]] && enabled=true
  printf '[{"id":"ilyazar.btop","enabled":%s}]\n' "$enabled"
  ;;
disappears)
  rm -rf -- "$BTOP_TEST_PLUGIN_DIR"
  exit 1
  ;;
fail)
  exit 1
  ;;
*)
  exit 2
  ;;
esac
MOCK
chmod 0755 "$MOCK_BIN/omarchy"

export BTOP_TEST_PLUGIN_DIR="$PLUGIN_DIR"
export BTOP_TEST_STATE_PATH="$STATE_PATH"

reset_case() {
  rm -rf -- "$CASE_ROOT"
  mkdir -p "$PLUGIN_DIR"
  printf 'disabled\n' >"$STATE_PATH"
}

run_baseline() {
  bash -c "$baseline_command" btop-runtime-baseline \
    "$CONFIG_PATH" "$BACKUP_PATH" "$ABSENT_PATH"
}

run_teardown() {
  PATH="$MOCK_BIN:$PATH" bash -c "$teardown_command" \
    btop-runtime-teardown "$PLUGIN_DIR" ilyazar.btop \
    "$CONFIG_PATH" "$BACKUP_PATH" "$ABSENT_PATH" 2 0
}

assert_metadata_absent() {
  [[ ! -e $BACKUP_PATH && ! -L $BACKUP_PATH ]]
  [[ ! -e $ABSENT_PATH && ! -L $ABSENT_PATH ]]
}

assert_absent_baseline_restored() {
  reset_case
  run_baseline

  [[ -e $ABSENT_PATH ]]
  printf 'plugin settings\n' >"$CONFIG_PATH"
  run_teardown

  [[ ! -e $CONFIG_PATH ]]
  assert_metadata_absent
}

assert_existing_baseline_restored() {
  reset_case
  printf 'original settings\n' >"$CONFIG_PATH"
  chmod 0640 "$CONFIG_PATH"
  run_baseline

  printf 'plugin settings\n' >"$CONFIG_PATH"
  chmod 0600 "$CONFIG_PATH"
  run_teardown

  [[ $(<"$CONFIG_PATH") == "original settings" ]]
  [[ $(stat -c '%a' "$CONFIG_PATH") == 640 ]]
  assert_metadata_absent
}

assert_restart_preserves_baseline() {
  reset_case
  printf 'original settings\n' >"$CONFIG_PATH"
  run_baseline
  printf 'plugin settings\n' >"$CONFIG_PATH"
  printf 'enabled\n' >"$STATE_PATH"

  run_teardown

  [[ $(<"$CONFIG_PATH") == "plugin settings" ]]
  [[ -e $BACKUP_PATH ]]

  printf 'disabled\n' >"$STATE_PATH"
  run_teardown

  [[ $(<"$CONFIG_PATH") == "original settings" ]]
  assert_metadata_absent
}

assert_unknown_state_defers_cleanup() {
  reset_case
  printf 'original settings\n' >"$CONFIG_PATH"
  run_baseline
  printf 'plugin settings\n' >"$CONFIG_PATH"
  printf 'fail\n' >"$STATE_PATH"

  run_teardown

  [[ $(<"$CONFIG_PATH") == "plugin settings" ]]
  [[ -e $BACKUP_PATH ]]

  rm -rf -- "$PLUGIN_DIR"
  run_teardown

  [[ $(<"$CONFIG_PATH") == "original settings" ]]
  assert_metadata_absent
}

assert_checkout_removal_cleans_up() {
  reset_case
  run_baseline
  printf 'plugin settings\n' >"$CONFIG_PATH"
  printf 'disappears\n' >"$STATE_PATH"

  run_teardown

  [[ ! -e $PLUGIN_DIR ]]
  [[ ! -e $CONFIG_PATH ]]
  assert_metadata_absent
}

assert_absent_baseline_restored
assert_existing_baseline_restored
assert_restart_preserves_baseline
assert_unknown_state_defers_cleanup
assert_checkout_removal_cleans_up

printf 'ok - runtime config lifecycle\n'
