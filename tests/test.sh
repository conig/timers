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

test_pipe_delimiter() {
    tmp=$(mktemp -d)
    XDG_CACHE_HOME="$tmp/.cache" HOME="$tmp" "$script" foo 2s
    XDG_CACHE_HOME="$tmp/.cache" HOME="$tmp" "$script" bar 2s
    out=$(XDG_CACHE_HOME="$tmp/.cache" HOME="$tmp" "$script" -s)
    [[ $out == *" | "* ]]
}

run_test pipe_delimiter test_pipe_delimiter

test_no_duplicate_checkmarks() {
    tmp=$(mktemp -d)
    fakebin="$tmp/fakebin"
    mkdir -p "$fakebin"
    cat <<'EOF' > "$fakebin/date"
#!/usr/bin/env bash
if [[ $1 == '+%s' ]]; then
    echo 1000
else
    /usr/bin/date "$@"
fi
EOF
    chmod +x "$fakebin/date"

    mkdir -p "$tmp/.cache"
    cat <<'EOF' > "$tmp/.cache/timers"
1000 TIMER 123 test
1000 ✔ test
EOF

    PATH="$fakebin:$PATH" XDG_CACHE_HOME="$tmp/.cache" HOME="$tmp" \
        "$script" >"$tmp/out"
    [[ $(grep -c 'test ✔' "$tmp/out") -eq 1 ]]
}

run_test no_duplicate_checkmarks test_no_duplicate_checkmarks

echo "All tests passed."
