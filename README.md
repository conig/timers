# Timers: Command-Line Timers and Alarms

## Overview
**Timers** is a simple Bash script that allows users to set timers and alarms from the command line. The script prints plain text so it can be used with a variety of status bars or scripts, including **i3blocks**, **Waybar**, or any other tool that can run a command. Timers logs timers and alarms to a file and provides an easy way to list, cancel, and manage them.

## Features
- **Command-line timers**: Set countdown timers (e.g., "5m" for 5 minutes) that automatically remove themselves upon completion.
- **Alarms**: Schedule an alarm for a specific time (e.g., "17:30").
- **Checkmark notifications**: Once a timer or alarm completes, it is marked with a checkmark (`🮱`) in the logs.
- **Status bar integration**: Output can be piped into i3blocks, Waybar, or any bar that runs shell commands.
- **Graceful error handling**: Prevents invalid inputs from being passed to `date`.

## Usage
```
Usage: timers [-m "message"] [message] [time] [-c to cancel timers] [-s to list timers] [-n duration] [--all] [--config]
```

### Arguments
| Option | Description |
|--------|-------------|
| `-m "message"` | A message to associate with the timer or alarm. |
| `[time]` | The duration for a timer (e.g., `5m`, `1h`, `30s`) or the specific time for an alarm (`HH:MM`). |
| `-c` | Cancels an existing timer or alarm via a numbered list. |
| `-s` | Display remaining timers in HH:MM:SS. |
| `-n <duration>` | Only show the timer when less than this duration remains. |
| `--all` | List all timers regardless of their show window. |
| `--config` | Open the configuration file in the default editor. |

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

#### Timer with a Show Window
```bash
timers "pick up Harry" 16:00 -n 30m
```
The timer will only appear in the list 30 minutes before 4:00 PM.

#### Listing Active Timers and Alarms
```bash
timers
```
Displays active timers and alarms in a user-friendly format.
Use `--all` to show every timer regardless of its window.
When more than one timer is active, they are separated by `|`.

### Show Active Timers in HH:MM:SS
```bash
timers -s
```

#### Cancelling a Timer
```bash
timers -c
```
Prompts the user to select a timer or alarm to cancel.

## Status Bar Integration
Timers outputs plain text, making it easy to embed in any bar that can execute a command.

### i3blocks
Add a block to `~/.config/i3blocks/config`:
```ini
[timers]
command=timers
interval=20
```

### Waybar
Add a custom module in your Waybar configuration:
```json
"custom/timers": {
    "exec": "timers",
    "interval": 20
}
```

## Log File
Timers and alarms are stored in `$XDG_CACHE_HOME/timers` (default `~/.cache/timers`).
The script periodically cleans up expired entries.

## Notifications
If `notify-send` or `makoctl` is available, Timers can display desktop
notifications. Configuration is read from
`$XDG_CONFIG_HOME/timers/config` (default `~/.config/timers/config`). The
script honours `$XDG_CONFIG_HOME` if set and falls back to `~/.config`
otherwise. The file supports two optional settings:

```
notify_on_create=0
notify_on_expire=1
```

Set each value to `1` to enable or `0` to disable the corresponding
alert. By default creation alerts are disabled and expiration alerts
are enabled.
Use `timers --config` to create or edit this file in your preferred editor.

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
