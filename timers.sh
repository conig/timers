#!/bin/bash

TIMER_LOG="$HOME/.timers"
STOPWATCH_EMOJI="⏱️"
CHECKMARK_EMOJI="🮱"
CLEANUP_AGE=60  # 60 seconds (1 minute)

# Helper function to format seconds as HH:MM:SS.
format_seconds() {
    local r=$1
    local h m s
    h=$(( r / 3600 ))
    m=$(( (r % 3600) / 60 ))
    s=$(( r % 60 ))
    printf "%02d:%02d:%02d" "$h" "$m" "$s"
}

# Helper function to format remaining time for non-granular display.
# The smallest resolution here is minutes.
format_remaining() {
    local r=$1
    if (( r < 60 )); then
        # For values under a minute, round up to 1 minute.
        printf "%dm" 1
    elif (( r < 3600 )); then
        printf "%dm" $(( r / 60 ))
    elif (( r < 86400 )); then
        # Hours with one decimal place
        local h=$(echo "scale=1; $r/3600" | bc)
        printf "%sh" "$h"
    elif (( r < 604800 )); then
        # Days with one decimal place
        local d=$(echo "scale=1; $r/86400" | bc)
        printf "%sd" "$d"
    elif (( r < 31536000 )); then
        # Weeks with one decimal place
        local w=$(echo "scale=1; $r/604800" | bc)
        printf "%sw" "$w"
    else
        # Years with one decimal place
        local y=$(echo "scale=1; $r/31536000" | bc)
        printf "%sy" "$y"
    fi
}

# Cleanup function to remove expired checkmark entries.
cleanup_timers() {
    [ -f "$TIMER_LOG" ] || return
    local now
    now=$(date +%s)
    awk -v now="$now" -v cutoff="$CLEANUP_AGE" -v check="$CHECKMARK_EMOJI" '{
        if ($2 == check) {
            if ($1 + cutoff >= now) {
                print
            }
        } else {
            print
        }
    }' "$TIMER_LOG" > "${TIMER_LOG}.tmp"
    mv "${TIMER_LOG}.tmp" "$TIMER_LOG"
}

# Function to cancel timers.
cancel_timer() {
    cleanup_timers  # Clean up before cancelling.
    if [[ ! -f "$TIMER_LOG" || ! -s "$TIMER_LOG" ]]; then
        echo "No active timers to cancel."
        return
    fi

    echo "Select a timer to cancel:"
    local i=1
    declare -A timer_map
    while read -r end_time type msg_rest; do
        echo "$i) $msg_rest"
        timer_map[$i]="$msg_rest"
        ((i++))
    done < "$TIMER_LOG"

    read -p "Enter number to cancel: " choice

    if [[ -n "${timer_map[$choice]}" ]]; then
        sed -i "\|${timer_map[$choice]}|d" "$TIMER_LOG"
        echo "Cancelled timer: ${timer_map[$choice]}"
    else
        echo "Invalid selection."
    fi
}

# Unified function for scheduling timers and alarms.
schedule_timer() {
    local mode="TIMER"
    local msg=""
    local time=""

    # Parse options for scheduling (–s is reserved for listing).
    while getopts ":m:ac" opt; do
        case "$opt" in
            m) msg="$OPTARG" ;;
            a) mode="ALARM" ;;
            c)
                cancel_timer
                return 0
                ;;
            *) echo "Usage: timers [-m \"message\"] [time] [-a for alarm] [-c to cancel timers]"; return 1 ;;
        esac
    done
    shift $((OPTIND - 1))
    time="$1"

    if [[ -z "$msg" || -z "$time" ]]; then
        echo "Usage: timers [-m \"message\"] [time] [-a for alarm] [-c to cancel timers]"
        return 1
    fi

    if [[ "$mode" == "TIMER" ]]; then
        # Convert time input by replacing m/h/s.
        local numeric_time
        numeric_time="$(echo "$time" | sed 's/m/*60/g; s/h/*3600/g; s/s//g')"

        # Validate numeric_time (it should be a number after evaluation).
        if ! [[ "$numeric_time" =~ ^[0-9\*\+\/\ \.\-]+$ ]]; then
            echo "Invalid timer format: '$time'"
            return 1
        fi

        # Evaluate the expression.
        # Use bc to compute the numeric value.
        local seconds
        seconds=$(echo "$numeric_time" | bc 2>/dev/null)
        if [[ -z "$seconds" || "$seconds" -eq 0 ]]; then
            echo "Invalid timer duration: '$time'"
            return 1
        fi

        local end_time=$(( $(date +%s) + seconds ))
        echo "$end_time TIMER $msg" >> "$TIMER_LOG"
        (
            sleep "$seconds"
            sed -i "\|^$end_time TIMER $msg\$|d" "$TIMER_LOG"
            checkmark_time=$(date +%s)
            echo "$checkmark_time $CHECKMARK_EMOJI $msg" >> "$TIMER_LOG"
            sleep 300
            sed -i "\|^$checkmark_time $CHECKMARK_EMOJI $msg\$|d" "$TIMER_LOG"
        ) &
    else
        # ALARM mode: validate that $time can be parsed.
        if ! alarm_epoch=$(date -d "$time" +%s 2>/dev/null); then
            echo "Invalid time format: '$time'"
            return 1
        fi

        local now
        now=$(date +%s)
        local delay=$(( alarm_epoch - now ))
        if (( delay > 0 )); then
            echo "$alarm_epoch ALARM $msg" >> "$TIMER_LOG"
            (
                sleep "$delay"
                sed -i "\|^$alarm_epoch ALARM $msg\$|d" "$TIMER_LOG"
                checkmark_time=$(date +%s)
                echo "$checkmark_time $CHECKMARK_EMOJI $msg" >> "$TIMER_LOG"
                sleep 300
                sed -i "\|^$checkmark_time $CHECKMARK_EMOJI $msg\$|d" "$TIMER_LOG"
            ) &
        else
            echo "Time is in the past!"
            return 1
        fi
    fi
}

# Function to list active timers.
# If seconds_mode is non-empty, display in HH:MM:SS; otherwise use the alternative display.
timers() {
    local seconds_mode="$1"
    cleanup_timers  # Run cleanup before listing timers.
    if [[ -f "$TIMER_LOG" && -s "$TIMER_LOG" ]]; then
        local results=()
        local now
        now=$(date +%s)
        while read -r token type msg_rest; do
            if [[ "$token" =~ ^[0-9]+$ && "$type" != "ALARM" && "$type" != "TIMER" ]]; then
                # This is a checkmark entry with a timestamp.
                results+=( "$msg_rest $CHECKMARK_EMOJI" )
            elif [[ "$token" =~ ^[0-9]+$ ]]; then
                local remaining=$(( token - now ))
                if (( remaining > 0 )); then
                    if [[ -n "$seconds_mode" ]]; then
                        # Show full HH:MM:SS format.
                        local formatted
                        formatted=$(format_seconds "$remaining")
                    else
                        # Use the higher-level display (minutes is the smallest resolution).
                        local formatted
                        formatted=$(format_remaining "$remaining")
                    fi
                    results+=( "$STOPWATCH_EMOJI $msg_rest - $formatted" )
                else
                    results+=( "$msg_rest $CHECKMARK_EMOJI" )
                fi
            else
                results+=( "$token $type $msg_rest" )
            fi
        done < "$TIMER_LOG"
        IFS='|'
        echo "${results[*]}"
        unset IFS
    else
        echo ""
    fi
}

# Main entry point.
# If invoked with -s as the sole argument (or with -s followed by other listing flags), use seconds mode.
if [[ $# -eq 0 ]]; then
    timers
else
    # If the first argument is -s and no scheduling time is provided, treat it as a request for a seconds‐resolution display.
    if [[ "$1" == "-s" && $# -eq 1 ]]; then
        timers "-s"
    else
        schedule_timer "$@"
    fi
fi
