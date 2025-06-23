#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$script_dir/timers.sh"

run_test() {
    local name=$1; shift
    if "$@"; then
        echo "$name: ok"
    else
        echo "$name: fail" >&2
        exit 1
    fi
}

test_implicit_message() {
    tmp=$(mktemp -d)
    XDG_CACHE_HOME="$tmp/.cache" HOME="$tmp" "$script" test 1s
    line=$(cat "$tmp/.cache/timers")
    [[ $line == *"TIMER"* && $line == *" test" ]]
}

test_explicit_message() {
    tmp=$(mktemp -d)
    XDG_CACHE_HOME="$tmp/.cache" HOME="$tmp" "$script" -m foo 1s
    line=$(cat "$tmp/.cache/timers")
    [[ $line == *"TIMER"* && $line == *" foo" ]]
}

test_missing_args() {
    tmp=$(mktemp -d)
    if XDG_CACHE_HOME="$tmp/.cache" HOME="$tmp" "$script" 1s >"$tmp/out" 2>&1; then
        return 1
    fi
    grep -q "Msg and time required." "$tmp/out"
}

test_special_chars() {
    tmp=$(mktemp -d)
    XDG_CACHE_HOME="$tmp/.cache" HOME="$tmp" "$script" 'foo|bar' 1s >"$tmp/out" 2>&1
    sleep 2
    grep -q 'sed:' "$tmp/out" && return 1
    grep -q "✔" "$tmp/.cache/timers"
}

run_test implicit_message test_implicit_message
run_test explicit_message test_explicit_message
run_test missing_args test_missing_args
run_test special_chars test_special_chars

echo "All tests passed."
