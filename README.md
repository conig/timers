# Timers: Command-Line Timers and Alarms for i3blocks

## Overview
**Timers** is a simple Bash script that allows users to set timers and alarms from the command line. It is designed to be compatible with **i3blocks**, making it easy to integrate with the i3 window manager for visual notifications. The script logs timers and alarms to a file and provides an easy way to list, cancel, and manage them.

## Features
- **Command-line timers**: Set countdown timers (e.g., "5m" for 5 minutes) that automatically remove themselves upon completion.
- **Alarms**: Schedule an alarm for a specific time (e.g., "17:30").
- **Checkmark notifications**: Once a timer or alarm completes, it is marked with a checkmark (`🮱`) in the logs.
- **i3blocks compatibility**: Easily integrate with i3blocks to display active timers and alarms in the i3bar.
- **Graceful error handling**: Prevents invalid inputs from being passed to `date`.

## Usage
```
Usage: timers [-m "message"] [message] [time] [-c to cancel timers] [-s to list timers]
```

### Arguments
| Option | Description |
|--------|-------------|
| `-m "message"` | A message to associate with the timer or alarm. |
| `[time]` | The duration for a timer (e.g., `5m`, `1h`, `30s`) or the specific time for an alarm (`HH:MM`). |
| `-a` | (Optional) Force treating the input as an alarm. Normally the script detects whether the time is a countdown or clock time. |
| `-c` | Cancels an existing timer or alarm via a numbered list. |
| `-s` | Display remaining timers in HH:MM:SS. |

### Examples
#### Setting a Timer
```bash
timers "Break time" 10m
```
Starts a **10-minute timer** with the message "Break time".

#### Setting an Alarm
```bash
timers "Meeting" 14:30
```
Schedules an **alarm for 2:30 PM** with the message "Meeting".

#### Listing Active Timers and Alarms
```bash
timers
```
Displays all active timers and alarms in a user-friendly format.

### Show Active Timers in HH:MM:SS
```bash
timers -s
```

#### Cancelling a Timer
```bash
timers -c
```
Prompts the user to select a timer or alarm to cancel.

## i3blocks Integration
To display active timers and alarms in **i3blocks**, create a new block entry in your `~/.config/i3blocks/config`:
```ini
[timers]
command=timers
interval=20
```
This will refresh the display every 20 seconds, showing currently active timers in the i3bar.

## Log File
Timers and alarms are stored in `$XDG_CACHE_HOME/timers` (default `~/.cache/timers`).
The script periodically cleans up expired entries.

## Error Handling
- If an invalid time format is provided, the script returns an error instead of passing it to `date`.
- If the provided time is in the past, the script notifies the user instead of scheduling an invalid alarm.

## Installation

Clone the repo and run:

```bash
make install
```

## Running Tests

Run the shell test suite locally with:

```bash
make test
```

These tests are also executed automatically on GitHub via
[GitHub Actions](https://docs.github.com/actions) for every push
and pull request.
