# QA Autoplay

This repo now includes a minimal autonomous smoke-test runner that plays full runs with dumb decisions.

## What it does

- starts a fresh run with the warrior
- uses an isolated QA save path so it does not touch the normal `user://savegame.tres`
- picks map rooms automatically
- plays the first legal card each turn
- draws from backlog when possible
- ends turns, collects rewards, shops, rests, opens treasure, resolves events, and stamps approval cards
- exits with a non-zero code if a run times out or hits an action cap

## Command

```powershell
$env:QA_RUNS='1'
$env:QA_SEED='1234'
$env:QA_MAX_ACTIONS='0'
$env:QA_MAX_SECONDS='600'
C:\Users\Lucas\Godot\Godot_v4.6.1-stable_win64_console.exe --headless --path C:\Users\Lucas\Godot\Deck_Builder_Tutorial scenes/qa/qa_boot.tscn --quit-after 20000
```

`QA_MAX_ACTIONS='0'` means no internal action cap.
On this local Godot build, the boot scene exits immediately unless `--quit-after` is present, so keep that flag in the command.
Prefer the 4.6.1 console binary for QA. It behaves much better than the older 4.4.1 editor binary for headless autoplay.

## Tunables

Environment variables:

- `QA_RUNS`
- `QA_SEED`
- `QA_MAX_ACTIONS`
- `QA_MAX_SECONDS`
- `QA_ACTION_DELAY`
- `QA_QUIET=1`

The runner also understands `--runs=...`, `--seed=...`, and similar command-line values, but environment variables are the reliable path from PowerShell in this repo.

## Report

The runner writes its last summary to:

- `user://qa_autoplay_last_run.json`

On this machine that resolves under:

- `C:\Users\Lucas\AppData\Roaming\Godot\app_userdata\Deck Builder Tutorial\qa_autoplay_last_run.json`

Key fields:

- `last_action`: most recent action the bot attempted
- `current_view`: semantic scene name at snapshot time
- `action_log_tail`: recent step-by-step action history
- `room_history`: chosen map path so far
- `player_state`: HP, mana, block, gold, budget
- `pile_counts`: deck, draw, discard, backlog, hand sizes
- `hand_state`: current hand cards with cost, targeting, and playable/disabled flags
- `enemy_state`: visible enemies and their health/block/action presence
- `map_state`: whether map is visible, floors climbed, last room, next available rooms
- `battle_over`: last win/lose panel text and type if one fired

The report is refreshed on actions, view changes, battle-over events, and a heartbeat while the run is active, so it should stay useful even if the process is stopped externally.

## Current scope

This is a smoke harness, not a balance simulator.

- It does not try to play well.
- It is meant to catch broken room flow, runtime errors, stuck states, and obvious turn/targeting regressions.
- It is safest after gameplay/state changes, especially deck, backlog, reward, room, and save-related edits.
