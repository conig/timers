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

test_show_window_and_all() {
    tmp=$(mktemp -d)
    XDG_CACHE_HOME="$tmp/.cache" HOME="$tmp" "$script" -n 2s test 4s
    out=$(XDG_CACHE_HOME="$tmp/.cache" HOME="$tmp" "$script")
    [[ -z $out ]]
    out=$(XDG_CACHE_HOME="$tmp/.cache" HOME="$tmp" "$script" --all)
    [[ $out == *test* ]]
    out=$(XDG_CACHE_HOME="$tmp/.cache" HOME="$tmp" "$script" -a)
    [[ $out == *test* ]]
    sleep 3
    out=$(XDG_CACHE_HOME="$tmp/.cache" HOME="$tmp" "$script")
    [[ $out == *test* ]]
}

run_test show_window_and_all test_show_window_and_all

test_auto_alarm() {
    tmp=$(mktemp -d)
    target=$(date -d '1 minute' '+%H:%M')
    XDG_CACHE_HOME="$tmp/.cache" HOME="$tmp" "$script" test "$target"
    line=$(cat "$tmp/.cache/timers")
    [[ $line == *"ALARM"* ]]
}

run_test auto_alarm test_auto_alarm

test_alarm_rollover() {
    tmp=$(mktemp -d)
    target=$(date -d '1 minute ago' '+%H:%M')
    XDG_CACHE_HOME="$tmp/.cache" HOME="$tmp" "$script" test "$target" >"$tmp/out" 2>&1
    line=$(cat "$tmp/.cache/timers")
    grep -q "ALARM" "$tmp/.cache/timers"
    grep -q "Warning" "$tmp/out"
}

run_test alarm_rollover test_alarm_rollover

test_time_first_date() {
    tmp=$(mktemp -d)
    t=$(date -d '1 minute' '+%H:%M')
    d=$(date -d 'tomorrow' '+%Y-%m-%d')
    XDG_CACHE_HOME="$tmp/.cache" HOME="$tmp" "$script" test $t $d
    grep -q "ALARM" "$tmp/.cache/timers"
}

run_test time_first_date test_time_first_date

test_default_notifications() {
    tmp=$(mktemp -d)
    fakebin="$tmp/fakebin"
    mkdir -p "$fakebin"
    cat <<EOF > "$fakebin/notify-send"
#!/usr/bin/env bash
echo notify >> "$tmp/out"
EOF
    chmod +x "$fakebin/notify-send"
    PATH="$fakebin:$PATH" XDG_CACHE_HOME="$tmp/.cache" HOME="$tmp" \
        "$script" test 1s
    sleep 2
    [[ $(grep -c notify "$tmp/out" 2>/dev/null || true) -eq 1 ]]
}

run_test default_notifications test_default_notifications

test_disable_notifications() {
    tmp=$(mktemp -d)
    fakebin="$tmp/fakebin"
    mkdir -p "$fakebin"
    cat <<EOF > "$fakebin/notify-send"
#!/usr/bin/env bash
echo notify >> "$tmp/out"
EOF
    chmod +x "$fakebin/notify-send"
    mkdir -p "$tmp/.config/timers"
    cat <<EOF > "$tmp/.config/timers/config"
notify_on_create=1
notify_on_expire=0
EOF
    PATH="$fakebin:$PATH" XDG_CACHE_HOME="$tmp/.cache" HOME="$tmp" \
        "$script" test 1s
    sleep 2
    [[ $(grep -c notify "$tmp/out" 2>/dev/null || true) -eq 1 ]]
}

run_test disable_notifications test_disable_notifications

test_xdg_config_home() {
    tmp=$(mktemp -d)
    fakebin="$tmp/fakebin"
    mkdir -p "$fakebin"
    cat <<EOF > "$fakebin/notify-send"
#!/usr/bin/env bash
echo notify >> "$tmp/out"
EOF
    chmod +x "$fakebin/notify-send"
    mkdir -p "$tmp/conf/timers"
    cat <<EOF > "$tmp/conf/timers/config"
notify_on_create=1
notify_on_expire=0
EOF
    PATH="$fakebin:$PATH" XDG_CACHE_HOME="$tmp/.cache" HOME="$tmp" \
        XDG_CONFIG_HOME="$tmp/conf" "$script" test 1s
    sleep 2
    [[ $(grep -c notify "$tmp/out" 2>/dev/null || true) -eq 1 ]]
}

run_test xdg_config_home test_xdg_config_home

test_config_flag() {
    tmp=$(mktemp -d)
    fakebin="$tmp/fakebin"
    mkdir -p "$fakebin"
    cat <<EOF > "$fakebin/editor"
#!/usr/bin/env bash
echo "\$@" > "$tmp/out"
EOF
    chmod +x "$fakebin/editor"
    PATH="$fakebin:$PATH" EDITOR="$fakebin/editor" \
        XDG_CACHE_HOME="$tmp/.cache" XDG_CONFIG_HOME= HOME="$tmp" \
        "$script" --config
    grep -q "$tmp/.config/timers/config" "$tmp/out"
}

run_test config_flag test_config_flag

test_help_flag() {
    tmp=$(mktemp -d)
    XDG_CACHE_HOME="$tmp/.cache" HOME="$tmp" "$script" -h >"$tmp/out"
    grep -q "Usage" "$tmp/out"
}

run_test help_flag test_help_flag

test_json_output() {
    tmp=$(mktemp -d)
    XDG_CACHE_HOME="$tmp/.cache" HOME="$tmp" "$script" foo 5s
    out=$(XDG_CACHE_HOME="$tmp/.cache" HOME="$tmp" "$script" --json)
    echo "$out" | jq -e '.[0] | .name=="foo" and .label=="TIMER" and has("id") and has("emoji") and has("expiration") and has("sound")' >/dev/null
}

run_test json_output test_json_output

test_cleanup_on_start() {
    tmp=$(mktemp -d)
    mkdir -p "$tmp/.cache"
    old=$(( $(date +%s) - 86400 ))
    printf "%s ✔ old\n" "$old" > "$tmp/.cache/timers"
    XDG_CACHE_HOME="$tmp/.cache" HOME="$tmp" "$script" >/dev/null
    ! grep -q old "$tmp/.cache/timers"
}

run_test cleanup_on_start test_cleanup_on_start

test_bad_date_with_window() {
    tmp=$(mktemp -d)
    if XDG_CACHE_HOME="$tmp/.cache" HOME="$tmp" "$script" test 9:00 -n 30m >"$tmp/out" 2>&1; then
        return 1
    fi
    grep -q "Bad date." "$tmp/out"
}

run_test bad_date_with_window test_bad_date_with_window

run_test cleanup_age_config 

echo "All tests passed."
