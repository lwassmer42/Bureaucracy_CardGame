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

## Supervisor Loop

There is now an outer Python supervisor that can run several QA passes with larger budgets and stop only when something looks like a real defect:

```powershell
python tools\qa\qa_supervisor.py
```

Useful flags:

- `--godot-exe C:\Users\Lucas\Godot\Godot_v4.6.1-stable_win64_console.exe`
- `--profiles 40:20,120:60,300:180`
- `--seed 7000`
- `--runs 4`
- `--print-json`

Supervisor behavior:

- starts with a shorter batch and increases `QA_MAX_ACTIONS` / `QA_MAX_SECONDS` across passes
- reruns automatically when the only signal is truncated coverage like `action_limit`
- stops with `status=investigate` when the investigation queue contains real runtime signals such as:
  - invariant warnings
  - `preflight`
  - `stall`
  - `timeout`
  - `other_failure`
- also parses Godot stdout/stderr for known engine-side signatures such as:
  - `script_parse_error`
  - `script_compile_error`
  - `script_load_failure`
  - `runtime_invalid_assignment`
  - `runtime_invalid_call`
  - `runtime_invalid_access`
  - `lambda_capture_freed`
  - `objectdb_leak`
  - `resource_still_in_use`
- writes its own summary to:
  - `C:\Users\Lucas\AppData\Roaming\Godot\app_userdata\Deck Builder Tutorial\qa_autoplay_supervisor_last_run.json`

## Tunables

Environment variables:

- `QA_RUNS`
- `QA_SEED`
- `QA_POLICY`
- `QA_POLICIES`
- `QA_MAX_ACTIONS`
- `QA_MAX_SECONDS`
- `QA_MAX_IDLE_SECONDS`
- `QA_ACTION_DELAY`
- `QA_QUIET=1`

The runner also understands `--runs=...`, `--seed=...`, `--policy=...`, `--policies=...`, `--max-idle=...`, and similar command-line values, but environment variables are the reliable path from PowerShell in this repo.

Current policies:

- `normal`: sensible smoke-test traversal
- `dumb`: random-valid choices to force off-happy-path coverage
- `backlog_heavy`: biases reward/play decisions toward Backlog mechanics
- `coverage_heavy`: biases room and card decisions toward under-seen mechanics and room types in the current suite

Batch usage:

- set `QA_POLICIES='normal,dumb,backlog_heavy'`
- keep `QA_RUNS` as the total number of runs
- the runner rotates through the configured policies in order while seeds continue incrementing by run

## Report

The runner writes its last summary to:

- `user://qa_autoplay_last_run.json`

On this machine that resolves under:

- `C:\Users\Lucas\AppData\Roaming\Godot\app_userdata\Deck Builder Tutorial\qa_autoplay_last_run.json`

Key fields:

- `last_action`: most recent action the bot attempted
- `policy`: active decision policy for the run
- `configured_policies`: active policy rotation for the suite
- `current_view`: semantic scene name at snapshot time
- `idle_seconds`: how long it has been since the last action or view change
- `preflight_errors`: broken promoted-card resources detected before a run starts
- `action_log_tail`: recent step-by-step action history
- `room_history`: chosen map path so far
- `player_state`: HP, mana, block, gold, budget
- `pile_counts`: deck, draw, discard, backlog, hand sizes
- `hand_state`: current hand cards with cost, targeting, and playable/disabled flags
- `enemy_state`: visible enemies and their health/block/action presence
- `map_state`: whether map is visible, floors climbed, last room, next available rooms
- `battle_over`: last win/lose panel text and type if one fired
- `run_summaries`: per-run seed/policy/outcome summaries for the whole suite
- `suite_summary`: aggregate counts by policy, failure category, room type, view, mechanic, and invariant warning category
- `invariant_warnings`: suspicious state warnings such as negative resources or duplicate live-zone card identities

Coverage-focused suite fields:

- `run_summaries[*].failure_category`: normalized bucket such as `victory`, `combat_loss`, `stall`, `timeout`, `action_limit`, or `preflight`
- `suite_summary.coverage_targets`: explicit target lists for rooms, views, and mechanics
- `suite_summary.by_policy`: per-policy totals, coverage gaps, failure buckets, and exclusive coverage
- `suite_summary.missing_room_types`: room types not exercised in the suite
- `suite_summary.missing_views`: view types not exercised in the suite
- `suite_summary.missing_mechanics`: mechanic tags not exercised in the suite
- `suite_summary.coverage`: per-domain completion summary with target count, covered count, and completeness flag
- `suite_summary.failure_category_totals`: aggregate run outcomes by normalized failure bucket
- `suite_summary.next_pass_recommendations`: plain-language suggestions for what kind of QA run to do next
- `suite_summary.investigation_queue`: machine-readable list of failure/warning categories with sample evidence and hints

Per-policy usefulness fields:

- `suite_summary.by_policy[*].room_type_totals`, `view_totals`, `mechanic_totals`
- `suite_summary.by_policy[*].missing_room_types`, `missing_views`, `missing_mechanics`
- `suite_summary.by_policy[*].exclusive_room_types`, `exclusive_views`, `exclusive_mechanics`
- `suite_summary.by_policy[*].failure_category_totals`
- `suite_summary.by_policy[*].coverage.has_unique_coverage`

The report is refreshed on actions, view changes, battle-over events, and a heartbeat while the run is active, so it should stay useful even if the process is stopped externally.

## Current scope

This is a smoke harness, not a balance simulator.

- It does not try to play well.
- It is meant to catch broken room flow, runtime errors, stuck states, and obvious turn/targeting regressions.
- It is safest after gameplay/state changes, especially deck, backlog, reward, room, and save-related edits.
