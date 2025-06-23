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
CLEANUP_AGE=300        # seconds
TIMERS_VERSION="v2025-05-19"

# Ensure log file exists early so background grep calls never fail
mkdir -p "$(dirname "$TIMER_LOG")"
touch "$TIMER_LOG"

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
    [[ -s $tmpfile ]] && mv "$tmpfile" "$TIMER_LOG" || rm -f "$tmpfile"
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
# Arguments: stamp kind window message
schedule_entry() {
    local stamp=$1 kind=$2 window=$3 msg=$4
    local delay=$((stamp-$(date +%s)))
    (
        touch "$TIMER_LOG"
        sleep "$delay"
        remove_log_line "$stamp $kind $$ $window $msg"
        local t=$(date +%s)
        echo "$t $CHECKMARK_EMOJI $msg" >> "$TIMER_LOG"
        sleep "$CLEANUP_AGE"
        remove_log_line "$t $CHECKMARK_EMOJI $msg"
    ) &
    echo "$stamp $kind $! $window $msg" >> "$TIMER_LOG"
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
        if (( $(awk '{print NF}' <<<"$line") >= 5 )); then
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
    while getopts ":m:cn:" opt; do
        case $opt in
            m) msg=$OPTARG ;;
            c) cancel_timer; return ;;
            n) window=$(parse_duration "$OPTARG" 2>/dev/null) || { echo "Bad window."; return 1; } ;;
            *) echo "Usage: timers [-m msg] [msg] time [-c] [-n window]" ; return 1 ;;
        esac
    done
    shift $((OPTIND-1))

    if [[ -z $msg && $# -ge 2 ]]; then
        msg=$1
        shift
    fi

    time_spec=$1
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
        schedule_entry "$end" "TIMER" "$window" "$msg"

    else  # ALARM
        local epoch delay
        epoch=$(alarm_to_epoch "$time_spec") || { echo "Bad date."; return 1; }
        delay=$((epoch-$(date +%s)))
        (( delay>0 )) || { echo "Time is past."; return 1; }
        schedule_entry "$epoch" "ALARM" "$window" "$msg"
    fi
}

# --------------------------------------------------------------------
# Display
# --------------------------------------------------------------------
list_timers() {
    touch "$TIMER_LOG"
    local use_secs=0 vertical=0 show_all=0
    for arg in "$@"; do
        case $arg in
            -s) use_secs=1 ;;
            -1) vertical=1 ;;
            --all) show_all=1 ;;
        esac
    done

    cleanup_timers
    [[ ! -s $TIMER_LOG ]] && { [[ $vertical -eq 0 ]] && echo ""; return; }

    local now=$(date +%s) out=()
    while IFS= read -r line; do
        set -- $line            # splits into $1,$2,...
        local stamp=$1  kind=$2

        if [[ $kind == $CHECKMARK_EMOJI ]]; then
            out+=("$(cut -d' ' -f3- <<<"$line") $CHECKMARK_EMOJI")
            continue
        fi

        if [[ $kind == TIMER || $kind == ALARM ]]; then
            local fields msg window=0
            fields=$(awk '{print NF}' <<<"$line")
            if (( fields >= 5 )); then
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
                out+=("$icon $msg: $disp")
            else
                out+=("$msg $CHECKMARK_EMOJI")
            fi
        fi
    done < "$TIMER_LOG"

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
if [[ $# -eq 0 ]]; then
    list_timers
else
    only_flags=1
    for arg in "$@"; do
        case $arg in
            -s|-1|--all) ;;
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
