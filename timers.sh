#!/usr/bin/env bash
# --------------------------- timers ----------------------------------
# Minimal terminal timer & alarm utility
# Version 2025-05-19 — shows 📅 for ≥1 day, ⏱️ otherwise
# --------------------------------------------------------------------

set -euo pipefail

TIMER_LOG="$HOME/.timers"
STOPWATCH_EMOJI="⏱️"
CALENDAR_EMOJI="📅"
CHECKMARK_EMOJI="✔"
CLEANUP_AGE=300        # seconds
TIMERS_VERSION="v2025-05-19"

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
parse_time() {
    local s=0 input=$1
    while [[ $input =~ ([0-9]*\.?[0-9]+)([hms]) ]]; do
        num=${BASH_REMATCH[1]} unit=${BASH_REMATCH[2]}
        case $unit in
            h) s=$(bc -l <<<"$s+$num*3600") ;;
            m) s=$(bc -l <<<"$s+$num*60")  ;;
            s) s=$(bc -l <<<"$s+$num")     ;;
        esac
        input=${input#${BASH_REMATCH[0]}}
    done
    [[ -n $input ]] && { echo "Could not parse '$input'." >&2; return 1; }
    echo "${s%.*}"
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
        ($2=="TIMER"||$2=="ALARM"){ if ($1     >= now) print; next }
        { print }
    ' "$TIMER_LOG" > "$tmpfile"
    [[ -s $tmpfile ]] && mv "$tmpfile" "$TIMER_LOG" || rm -f "$tmpfile"
}

# --------------------------------------------------------------------
# Cancel menu
# --------------------------------------------------------------------
cancel_timer() {
    cleanup_timers
    [[ ! -s $TIMER_LOG ]] && { echo "No active timers."; return; }

    echo "Select a timer to cancel:"
    local i=1 line pid
    declare -A map
    while IFS= read -r line; do
        [[ $line =~ (TIMER|ALARM) ]] || continue
        map[$i]="$line"
        echo "$i) $(cut -d' ' -f4- <<<"$line")"
        ((i++))
    done < "$TIMER_LOG"

    (( i==1 )) && { echo "Nothing to cancel."; return; }
    read -rp "> " choice
    [[ ${map[$choice]+_} ]] || { echo "Invalid."; return; }
    pid=$(awk '{print $3}' <<<"${map[$choice]}")
    [[ $pid =~ ^[0-9]+$ ]] && kill "$pid" 2>/dev/null
    sed -i "\|^${map[$choice]}$|d" "$TIMER_LOG"
    echo "Cancelled."
}

# --------------------------------------------------------------------
# Schedule timer/alarm
# --------------------------------------------------------------------
schedule_timer() {
    local mode=TIMER msg="" time_spec=""
    while getopts ":m:ac" opt; do
        case $opt in
            m) msg=$OPTARG ;;
            a) mode=ALARM ;;
            c) cancel_timer; return ;;
            *) echo "Usage: timers [-m msg] duration|date [-a] [-c]" ; return 1 ;;
        esac
    done
    shift $((OPTIND-1))
    time_spec=$1
    [[ -z $msg || -z $time_spec ]] && { echo "Msg and time required."; return 1; }

    if [[ $mode == TIMER ]]; then
        local secs=$(parse_time "$time_spec") || return
        (( secs>0 )) || { echo "Duration must be >0."; return 1; }
        local end=$(( $(date +%s)+secs ))
        (
            sleep "$secs"
            sed -i "\|^$end TIMER $$ $msg$|d" "$TIMER_LOG"
            local t=$(date +%s)
            echo "$t $CHECKMARK_EMOJI $msg" >> "$TIMER_LOG"
            sleep "$CLEANUP_AGE"
            sed -i "\|^$t $CHECKMARK_EMOJI $msg$|d" "$TIMER_LOG"
        ) &
        echo "$end TIMER $! $msg" >> "$TIMER_LOG"

    else  # ALARM
        local epoch delay now
        epoch=$(alarm_to_epoch "$time_spec") || { echo "Bad date."; return 1; }
        now=$(date +%s)
        delay=$((epoch-now))
        (( delay>0 )) || { echo "Time is past."; return 1; }
        (
            sleep "$delay"
            sed -i "\|^$epoch ALARM $$ $msg$|d" "$TIMER_LOG"
            local t=$(date +%s)
            echo "$t $CHECKMARK_EMOJI $msg" >> "$TIMER_LOG"
            sleep "$CLEANUP_AGE"
            sed -i "\|^$t $CHECKMARK_EMOJI $msg$|d" "$TIMER_LOG"
        ) &
        echo "$epoch ALARM $! $msg" >> "$TIMER_LOG"
    fi
}

# --------------------------------------------------------------------
# Display
# --------------------------------------------------------------------
list_timers() {
    local flag=${1:-} use_secs=0 vertical=0
    [[ $flag == -s ]] && use_secs=1
    [[ $flag == -1 ]] && vertical=1

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
            local remain=$((stamp-now))
            local msg=$(cut -d' ' -f4- <<<"$line")
            if (( remain>0 )); then
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

    if (( vertical )); then printf '%s\n' "${out[@]}"; else
        local IFS=", "; echo "${out[*]}"
    fi
}

# --------------------------------------------------------------------
# Entry
# --------------------------------------------------------------------
if [[ $# -eq 0 ]]; then
    list_timers
elif [[ $1 == -s && $# -eq 1 ]]; then
    list_timers -s
elif [[ $1 == -1 && $# -eq 1 ]]; then
    list_timers -1
else
    schedule_timer "$@"
fi

# Show version in interactive shells for sanity-checking
[[ -t 1 && ${TIMERS_NO_BANNER:-} != 1 ]] && echo "(timers $TIMERS_VERSION)" >&2
