#!/usr/bin/env bash
# --------------------------- timers ----------------------------------
# Minimal terminal timer & alarm utility
# Version 2025-05-19 — shows 📅 for ≥1 day, ⏱️ otherwise
# --------------------------------------------------------------------

set -euo pipefail

TIMER_LOG="${XDG_CACHE_HOME:-$HOME/.cache}/timers"
STOPWATCH_EMOJI="⏱️"
CALENDAR_EMOJI="📅"
CHECKMARK_EMOJI="✔"
CLEANUP_AGE=600        # seconds
TIMERS_VERSION="v2025-05-19"


# Display usage information
print_help() {
    cat <<'EOF'
Usage: timers [-m "msg"] [msg] time [-c] [-n window]
       timers [-s] [-1] [-a|--all] [--json]
       timers [--config]

Options:
  -m msg        Set the timer or alarm message
  -c            Cancel a timer or alarm
  -n duration   Show timer when less than duration remains
  -p            Play a sound when the timer finishes
  -s            Show remaining time in HH:MM:SS
  -1            Output one item per line
  -a, --all     Show all timers regardless of window
  --json        Output timers as JSON
  --config      Edit the configuration file
  -h, --help    Show this help message
EOF
}

# Ensure log file exists early so background grep calls never fail
mkdir -p "$(dirname "$TIMER_LOG")"
touch "$TIMER_LOG"

# Config ---------------------------------------------------------------
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/timers"
CONFIG_FILE="$CONFIG_DIR/config"

# Defaults: notify on expiration only, no sound
NOTIFY_CREATE=0
NOTIFY_EXPIRE=1
PLAY_SOUND=0
SOUND_FILE=""

# Load config if present
if [[ -f $CONFIG_FILE ]]; then
    while IFS='=' read -r key val; do
        key=${key//[[:space:]]/}
        val=${val//[[:space:]]/}
        [[ $key = \#* || -z $key ]] && continue
        case $key in
            notify_on_create) NOTIFY_CREATE=$val ;;
            notify_on_expire) NOTIFY_EXPIRE=$val ;;
            sound_on_expire)  PLAY_SOUND=$val ;;
            sound_file)       SOUND_FILE=$val ;;
            cleanup_age)      CLEANUP_AGE=$val ;;
        esac
    done < "$CONFIG_FILE"
fi

# Open the config file in the user's editor
open_config() {
    mkdir -p "$CONFIG_DIR"
    if [[ ! -s $CONFIG_FILE ]]; then
        cat > "$CONFIG_FILE" <<'EOF'
# notify_on_create=0
# notify_on_expire=1
# cleanup_age=600
# sound_on_expire=0
# sound_file=/path/to/sound.oga
EOF
    fi
    local editor="${EDITOR:-${VISUAL:-vi}}"
    "$editor" "$CONFIG_FILE"
}

# Send a desktop notification if possible
notify() {
    local title=$1 body=$2
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "$title" "$body" >/dev/null 2>&1
    elif command -v makoctl >/dev/null 2>&1; then
        makoctl send -t "$title" -s "$body" >/dev/null 2>&1
    fi
}

# Play a sound if a command is available
play_sound() {
    local file=$1
    if [[ -n $file && -f $file ]]; then
        if command -v paplay >/dev/null 2>&1; then
            paplay "$file" >/dev/null 2>&1 &
        elif command -v aplay >/dev/null 2>&1; then
            aplay "$file" >/dev/null 2>&1 &
        elif command -v afplay >/dev/null 2>&1; then
            afplay "$file" >/dev/null 2>&1 &
        elif command -v play >/dev/null 2>&1; then
            play -q "$file" >/dev/null 2>&1 &
        elif command -v mpg123 >/dev/null 2>&1; then
            mpg123 -q "$file" >/dev/null 2>&1 &
        fi
    else
        printf '\a'
    fi
}

# --------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------

# seconds → HH:MM:SS
format_seconds() {
    local r=$1
    printf "%02d:%02d:%02d" $((r/3600)) $(((r%3600)/60)) $((r%60))
}

# seconds → natural size (s, m, h, d, w, y)
format_remaining() {
    local r=$1
    if   (( r < 60        )); then printf "%ds"  "$r"
    elif (( r < 3600      )); then printf "%dm"  $((r/60))
    elif (( r < 86400     )); then printf "%.1fh" "$(bc -l <<<"$r/3600")"
    elif (( r < 604800    )); then printf "%.1fd" "$(bc -l <<<"$r/86400")"
    elif (( r < 31536000  )); then printf "%.1fw" "$(bc -l <<<"$r/604800")"
    else                          printf "%.1fy" "$(bc -l <<<"$r/31536000")"
    fi
}

# 1h20m10s → seconds
parse_duration() {
    local s=0 input=$1
    while [[ $input =~ ([0-9]*\.?[0-9]+)([hms]) ]]; do
        num=${BASH_REMATCH[1]} unit=${BASH_REMATCH[2]}
        case $unit in
            h) s=$(awk -v s="$s" -v n="$num" 'BEGIN{print s+n*3600}') ;;
            m) s=$(awk -v s="$s" -v n="$num" 'BEGIN{print s+n*60}')  ;;
            s) s=$(awk -v s="$s" -v n="$num" 'BEGIN{print s+n}')     ;;
        esac
        input=${input#${BASH_REMATCH[0]}}
    done
    [[ -n $input ]] && { echo "Could not parse '$input'." >&2; return 1; }
    printf '%d' "${s%.*}"
}

# “YYYY-MM-DD” or “YYYY-MM-DD HH:MM” → epoch
alarm_to_epoch() {
    [[ $1 =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && set -- "$1 00:00"
    date -d "$1" +%s 2>/dev/null
}

# Prune old/stale log lines
cleanup_timers() {
    [[ -f $TIMER_LOG ]] || return
    local now=$(date +%s)
    local tmpfile
    tmpfile=$(mktemp "${TIMER_LOG}.XXXXXX")
    awk -v now="$now" -v age="$CLEANUP_AGE" -v ok="$CHECKMARK_EMOJI" '
        ($2==ok)                   { if ($1+age >= now) print; next }
        ($2=="TIMER"||$2=="ALARM"){ if ($1     >  now) print; next }
        { print }
    ' "$TIMER_LOG" > "$tmpfile"
    mv "$tmpfile" "$TIMER_LOG"
}

# Safely remove an exact log line regardless of special characters
remove_log_line() {
    local line="$1"
    local tmpfile
    tmpfile=$(mktemp "${TIMER_LOG}.XXXXXX")
    grep -Fv -x -- "$line" "$TIMER_LOG" > "$tmpfile" || true
    mv "$tmpfile" "$TIMER_LOG"
}

# Schedule a timer or alarm that triggers at an absolute epoch time.
# Arguments: stamp kind window msg sound
schedule_entry() {
    local stamp=$1 kind=$2 window=$3 msg=$4 sound=$5
    local delay=$((stamp-$(date +%s)))
    (
        touch "$TIMER_LOG"
        sleep "$delay"
        remove_log_line "$stamp $kind $$ $window $sound $msg"
        local t=$(date +%s)
        echo "$t $CHECKMARK_EMOJI $msg" >> "$TIMER_LOG"
        if (( NOTIFY_EXPIRE )); then
            notify "$msg" "$kind finished"
        fi
        if (( sound )); then
            play_sound "$SOUND_FILE"
        fi
        sleep "$CLEANUP_AGE"
        remove_log_line "$t $CHECKMARK_EMOJI $msg"
    ) &
    echo "$stamp $kind $! $window $sound $msg" >> "$TIMER_LOG"
    if (( NOTIFY_CREATE )); then
        notify "$msg" "$kind set"
    fi
}

# --------------------------------------------------------------------
# Cancel menu
# --------------------------------------------------------------------
cancel_timer() {
    touch "$TIMER_LOG"
    cleanup_timers
    [[ ! -s $TIMER_LOG ]] && { echo "No active timers."; return; }

    echo "Select a timer to cancel:"
    local i=1 line pid
    declare -A map
    while IFS= read -r line; do
        [[ $line =~ (TIMER|ALARM) ]] || continue
        map[$i]="$line"
        local fields
        fields=$(awk '{print NF}' <<<"$line")
        if (( fields >= 6 )); then
            echo "$i) $(cut -d' ' -f6- <<<"$line")"
        elif (( fields >=5 )); then
            echo "$i) $(cut -d' ' -f5- <<<"$line")"
        else
            echo "$i) $(cut -d' ' -f4- <<<"$line")"
        fi
        ((i++))
    done < "$TIMER_LOG"

    (( i==1 )) && { echo "Nothing to cancel."; return; }
    read -rp "> " choice
    [[ ${map[$choice]+_} ]] || { echo "Invalid."; return; }
    pid=$(awk '{print $3}' <<<"${map[$choice]}")
    [[ $pid =~ ^[0-9]+$ ]] && kill "$pid" 2>/dev/null
    remove_log_line "${map[$choice]}"
    echo "Cancelled."
}

# --------------------------------------------------------------------
# Schedule timer/alarm
# --------------------------------------------------------------------
schedule_timer() {
    touch "$TIMER_LOG"
    local mode msg="" time_spec="" window=0
    while getopts ":m:cn:p" opt; do
        case $opt in
            m) msg=$OPTARG ;;
            c) cancel_timer; return ;;
            n) window=$(parse_duration "$OPTARG" 2>/dev/null) || { echo "Bad window."; return 1; } ;;
            p) PLAY_SOUND=1 ;;
            *) echo "Usage: timers [-m msg] [msg] time [-c] [-n window] [-p]" ; return 1 ;;
        esac
    done
    shift $((OPTIND-1))

    if [[ -z $msg && $# -ge 2 ]]; then
        msg=$1
        shift
    fi

    time_spec="$*"
    [[ -z $msg || -z $time_spec ]] && { echo "Msg and time required."; return 1; }

    local secs parsed=0
    secs=$(parse_duration "$time_spec" 2>/dev/null) && parsed=1

    if (( parsed )); then
        mode=TIMER
    else
        mode=ALARM
    fi

    if [[ $mode == TIMER ]]; then
        (( parsed )) || { echo "Could not parse '$time_spec'."; return 1; }
        (( secs>0 )) || { echo "Duration must be >0."; return 1; }
        local end=$(( $(date +%s)+secs ))
        schedule_entry "$end" "TIMER" "$window" "$msg" "$PLAY_SOUND"

    else  # ALARM
        local epoch delay
        epoch=$(alarm_to_epoch "$time_spec") || { echo "Bad date."; return 1; }
        delay=$((epoch-$(date +%s)))
        if (( delay<=0 )) && [[ $time_spec =~ ^[0-9]{1,2}:[0-9]{2}$ ]]; then
            echo "Warning: time has passed today; scheduling for tomorrow." >&2
            epoch=$((epoch+86400))
            delay=$((epoch-$(date +%s)))
        fi
        (( delay>0 )) || { echo "Time is past."; return 1; }
        schedule_entry "$epoch" "ALARM" "$window" "$msg" "$PLAY_SOUND"
    fi
}

# --------------------------------------------------------------------
# Display
# --------------------------------------------------------------------
json_escape() {
    local s=${1//\\/\\\\}
    s=${s//"/\\"}
    s=${s//$'\n'/\\n}
    printf '%s' "$s"
}

list_timers() {
    touch "$TIMER_LOG"
    local use_secs=0 vertical=0 show_all=0 json=0
    for arg in "$@"; do
        case $arg in
            -s) use_secs=1 ;;
            -1) vertical=1 ;;
            -a|--all) show_all=1 ;;
            --json) json=1 ;;
        esac
    done

    cleanup_timers
    if [[ ! -s $TIMER_LOG ]]; then
        if (( json )); then
            echo "[]"
        elif (( vertical==0 )); then
            echo ""
        fi
        return
    fi

    local now=$(date +%s) out=()
    if (( json )); then
        printf '['
    fi
    local first=1
    while IFS= read -r line; do
        set -- $line            # splits into $1,$2,...
        local stamp=$1  kind=$2

        if [[ $kind == $CHECKMARK_EMOJI ]]; then
            local msg=$(cut -d' ' -f3- <<<"$line")
            if (( json )); then
                (( first==0 )) && printf ','
                first=0
                printf '\n  {"id":"done-%s","name":"%s","label":"done","emoji":"%s","expiration":%s,"sound":0}' \
                    "$stamp" "$(json_escape "$msg")" "$CHECKMARK_EMOJI" "$stamp"
            else
                out+=("$msg $CHECKMARK_EMOJI")
            fi
            continue
        fi

        if [[ $kind == TIMER || $kind == ALARM ]]; then
            local fields msg window=0 sound=0 pid=$3
            fields=$(awk '{print NF}' <<<"$line")
            if (( fields >= 6 )); then
                window=$4
                sound=$5
                msg=$(cut -d' ' -f6- <<<"$line")
            elif (( fields == 5 )); then
                window=$4
                msg=$(cut -d' ' -f5- <<<"$line")
            else
                msg=$(cut -d' ' -f4- <<<"$line")
            fi
            local remain=$((stamp-now))
            if (( remain>0 )); then
                if (( show_all==0 && window>0 && remain>window )); then
                    continue
                fi
                local disp icon
                if (( use_secs )); then
                    disp=$(format_seconds "$remain")
                    icon=$STOPWATCH_EMOJI
                else
                    disp=$(format_remaining "$remain")
                    icon=$([[ $remain -ge 86400 ]] && echo "$CALENDAR_EMOJI" || echo "$STOPWATCH_EMOJI")
                fi
                if (( json )); then
                    (( first==0 )) && printf ','
                    first=0
                    printf '\n  {"id":"%s-%s","name":"%s","label":"%s","emoji":"%s","expiration":%s,"sound":%s}' \
                        "$stamp" "$pid" "$(json_escape "$msg")" "$kind" "$icon" "$stamp" "$sound"
                else
                    out+=("$icon $msg: $disp")
                fi
            else
                if (( json )); then
                    (( first==0 )) && printf ','
                    first=0
                    printf '\n  {"id":"%s-%s","name":"%s","label":"%s","emoji":"%s","expiration":%s,"sound":%s}' \
                        "$stamp" "$pid" "$(json_escape "$msg")" "$kind" "$CHECKMARK_EMOJI" "$stamp" "$sound"
                else
                    out+=("$msg $CHECKMARK_EMOJI")
                fi
            fi
        fi
    done < "$TIMER_LOG"

    if (( json )); then
        echo
        printf ']'
        echo
        return
    fi

    if (( vertical )); then
        printf '%s\n' "${out[@]}"
    else
        if [[ ${#out[@]} -gt 0 ]]; then
            printf '%s' "${out[0]}"
            for item in "${out[@]:1}"; do
                printf ' | %s' "$item"
            done
            echo
        fi
    fi
}

# --------------------------------------------------------------------
# Entry
# --------------------------------------------------------------------
cleanup_timers
for arg in "$@"; do
    case $arg in
        -h|--help)
            print_help
            exit 0
            ;;
    esac
done

if [[ $# -eq 0 ]]; then
    list_timers
elif [[ $# -eq 1 && $1 == --config ]]; then
    open_config
else
    only_flags=1
    for arg in "$@"; do
        case $arg in
            -s|-1|-a|--all|--json) ;;
            *) only_flags=0; break ;;
        esac
    done
    if (( only_flags )); then
        list_timers "$@"
    else
        schedule_timer "$@"
    fi
fi

# Version output disabled to keep display clean
