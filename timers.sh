#!/bin/bash

TIMER_LOG="$HOME/.timers"
STOPWATCH_EMOJI="⏱️"
CHECKMARK_EMOJI="✔"
CLEANUP_AGE=300  # in seconds

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
        local h
        h=$(echo "scale=1; $r/3600" | bc)
        printf "%sh" "$h"
    elif (( r < 604800 )); then
        # Days with one decimal place
        local d
        d=$(echo "scale=1; $r/86400" | bc)
        printf "%sd" "$d"
    elif (( r < 31536000 )); then
        # Weeks with one decimal place
        local w
        w=$(echo "scale=1; $r/604800" | bc)
        printf "%sw" "$w"
    else
        # Years with one decimal place
        local y
        y=$(echo "scale=1; $r/31536000" | bc)
        printf "%sy" "$y"
    fi
}

# Parse strings like "1h15m" properly, returning total seconds.
parse_time() {
    local input="$1"
    local total=0

    # Loop over all occurrences of <number><unit>.
    while [[ $input =~ ([0-9]*\.?[0-9]+)([hms]) ]]; do
        local num="${BASH_REMATCH[1]}"
        local unit="${BASH_REMATCH[2]}"

        case "$unit" in
            h) total=$(echo "$total + $num*3600" | bc) ;;
            m) total=$(echo "$total + $num*60"   | bc) ;;
            s) total=$(echo "$total + $num"      | bc) ;;
        esac

        input="${input#${BASH_REMATCH[0]}}"
    done

    # If leftover text remains, treat that as an error.
    if [[ -n "$input" ]]; then
        echo "Unparsed leftover in time string: '$input'" >&2
        return 1
    fi

    # Convert total to integer (drop decimals).
    echo "${total%.*}"
}

# Remove:
#  - Checkmark entries older than CLEANUP_AGE.
#  - Timer/Alarm entries whose times are in the past.
cleanup_timers() {
    [ -f "$TIMER_LOG" ] || return
    local now
    now=$(date +%s)

    awk -v now="$now" -v cutoff="$CLEANUP_AGE" -v check="$CHECKMARK_EMOJI" '{
        # Timer/Alarm lines: end_time type pid message...
        # Checkmark lines:   timestamp checkmark message...
        if ($2 == check) {
            # Checkmark line: keep only if not too old
            if ($1 + cutoff >= now) {
                print
            }
        } else if ($2 == "TIMER" || $2 == "ALARM") {
            # Keep if still in the future
            if ($1 >= now) {
                print
            }
        } else {
            # Unrecognised line; keep it
            print
        }
    }' "$TIMER_LOG" > "${TIMER_LOG}.tmp"
    mv "${TIMER_LOG}.tmp" "$TIMER_LOG"
}

# Cancel timers or alarms by selecting from a list.
cancel_timer() {
    cleanup_timers
    if [[ ! -f "$TIMER_LOG" || ! -s "$TIMER_LOG" ]]; then
        echo "No active timers to cancel."
        return
    fi

    echo "Select a timer to cancel:"
    local i=1
    declare -A line_map

    # Only let the user cancel lines with "TIMER" or "ALARM" as $2.
    while IFS= read -r full_line; do
        local type
        type="$(echo "$full_line" | awk '{print $2}')"
        if [[ "$type" == "TIMER" || "$type" == "ALARM" ]]; then
            line_map[$i]="$full_line"
            # Show the message portion (field 4 onward).
            local msg
            msg="$(echo "$full_line" | cut -d ' ' -f 4-)"
            echo "$i) $msg"
            ((i++))
        fi
    done < "$TIMER_LOG"

    if (( i == 1 )); then
        echo "No active timers/alarms to cancel."
        return
    fi

    read -p "Enter number to cancel: " choice

    local selected_line="${line_map[$choice]}"
    if [[ -n "$selected_line" ]]; then
        # Parse out the PID (third field).
        local pid
        pid="$(echo "$selected_line" | awk '{print $3}')"
        # Kill the background process if valid.
        if [[ "$pid" =~ ^[0-9]+$ ]]; then
            kill "$pid" 2>/dev/null
        fi
        # Remove from the log.
        sed -i "\|^$selected_line\$|d" "$TIMER_LOG"
        echo "Cancelled: $(echo "$selected_line" | cut -d ' ' -f 4-)"
    else
        echo "Invalid selection."
    fi
}

# Schedules a timer or alarm.
schedule_timer() {
    local mode="TIMER"
    local msg=""
    local time_spec=""

    # Parse options (-m message, -a for alarm, -c to cancel).
    while getopts ":m:ac" opt; do
        case "$opt" in
            m) msg="$OPTARG" ;;
            a) mode="ALARM" ;;
            c)
                cancel_timer
                return 0
                ;;
            *)
                echo "Usage: timers [-m \"message\"] [time] [-a for alarm] [-c to cancel timers]"
                return 1
                ;;
        esac
    done
    shift $((OPTIND - 1))
    time_spec="$1"

    if [[ -z "$msg" || -z "$time_spec" ]]; then
        echo "Usage: timers [-m \"message\"] [time] [-a for alarm] [-c to cancel timers]"
        return 1
    fi

    if [[ "$mode" == "TIMER" ]]; then
        # Convert e.g. "1h15m" into total seconds.
        local seconds
        seconds="$(parse_time "$time_spec")" || {
            echo "Invalid timer format: '$time_spec'"
            return 1
        }
        if (( seconds <= 0 )); then
            echo "Invalid timer duration: '$time_spec'"
            return 1
        fi
        local end_time=$(( $(date +%s) + seconds ))

        # Fork off a background process that sleeps, then updates the log.
        (
            sleep "$seconds"
            sed -i "\|^$end_time TIMER $$ $msg\$|d" "$TIMER_LOG"
            local checkmark_time
            checkmark_time=$(date +%s)
            echo "$checkmark_time $CHECKMARK_EMOJI $msg" >> "$TIMER_LOG"
            sleep 300
            sed -i "\|^$checkmark_time $CHECKMARK_EMOJI $msg\$|d" "$TIMER_LOG"
        ) &
        local pid=$!
        echo "$end_time TIMER $pid $msg" >> "$TIMER_LOG"

    else
        # Alarm mode: parse user’s time as a future date/time.
        local alarm_epoch
        if ! alarm_epoch=$(date -d "$time_spec" +%s 2>/dev/null); then
            echo "Invalid time format: '$time_spec'"
            return 1
        fi
        local now
        now=$(date +%s)
        local delay=$(( alarm_epoch - now ))
        if (( delay <= 0 )); then
            echo "Time is in the past!"
            return 1
        fi

        (
            sleep "$delay"
            sed -i "\|^$alarm_epoch ALARM $$ $msg\$|d" "$TIMER_LOG"
            local checkmark_time
            checkmark_time=$(date +%s)
            echo "$checkmark_time $CHECKMARK_EMOJI $msg" >> "$TIMER_LOG"
            sleep 300
            sed -i "\|^$checkmark_time $CHECKMARK_EMOJI $msg\$|d" "$TIMER_LOG"
        ) &
        local pid=$!
        echo "$alarm_epoch ALARM $pid $msg" >> "$TIMER_LOG"
    fi
}

# Lists active timers/alarms.
# By default, prints all entries in one line separated by " | ".
# If –1 is passed, prints each entry on its own line.
# If –s is passed, uses HH:MM:SS format for remaining time.
timers() {
    local flag="$1"
    local use_seconds=0
    local vertical=0
    if [[ "$flag" == "-s" ]]; then
         use_seconds=1
    elif [[ "$flag" == "-1" ]]; then
         vertical=1
    fi

    cleanup_timers  # remove stale entries
    if [[ ! -f "$TIMER_LOG" || ! -s "$TIMER_LOG" ]]; then
         echo ""
         return
    fi

    local now
    now=$(date +%s)
    local output_lines=()
    while IFS= read -r line; do
         local first second
         first="$(echo "$line" | awk '{print $1}')"
         second="$(echo "$line" | awk '{print $2}')"

         if [[ "$second" == "$CHECKMARK_EMOJI" ]]; then
              local msg
              msg="$(echo "$line" | cut -d ' ' -f 3-)"
              output_lines+=("$msg $CHECKMARK_EMOJI")
         elif [[ "$second" == "TIMER" || "$second" == "ALARM" ]]; then
              local end_time="$first"
              local pid
              pid="$(echo "$line" | awk '{print $3}')"
              local msg
              msg="$(echo "$line" | cut -d ' ' -f 4-)"
              local remaining=$(( end_time - now ))
              if (( remaining > 0 )); then
                   local formatted
                   if (( use_seconds == 1 )); then
                        formatted="$(format_seconds "$remaining")"
                   else
                        formatted="$(format_remaining "$remaining")"
                   fi
                   output_lines+=("$STOPWATCH_EMOJI $msg: $formatted")
              else
                   output_lines+=("$msg $CHECKMARK_EMOJI")
              fi
         else
              output_lines+=("$line")
         fi
    done < "$TIMER_LOG"

    if (( vertical == 1 )); then
         # Vertical listing.
         for entry in "${output_lines[@]}"; do
              echo "$entry"
         done
    else
         # Horizontal listing: manually join with " , ".
         local joined=""
         for entry in "${output_lines[@]}"; do
              if [[ -z "$joined" ]]; then
                   joined="$entry"
              else
                   joined="$joined, $entry"
              fi
         done
         echo "$joined"
    fi
}

# Main entry point.
if [[ $# -eq 0 ]]; then
    timers
else
    if [[ "$1" == "-s" && $# -eq 1 ]]; then
        timers "-s"
    elif [[ "$1" == "-1" && $# -eq 1 ]]; then
        timers "-1"
    else
        schedule_timer "$@"
    fi
fi
