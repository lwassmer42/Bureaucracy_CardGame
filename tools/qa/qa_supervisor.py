from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any


DEFAULT_POLICIES = "normal,dumb,backlog_heavy,coverage_heavy"
DEFAULT_PROFILES = (
    {"max_actions": 40, "max_seconds": 20},
    {"max_actions": 120, "max_seconds": 60},
    {"max_actions": 300, "max_seconds": 180},
)
DEFAULT_IDLE_SECONDS = 5.0
DEFAULT_ACTION_DELAY = 0.02
DEFAULT_RUNS = 4
DEFAULT_SEED = 7000
REPORT_NAME = "qa_autoplay_last_run.json"
SUPERVISOR_REPORT_NAME = "qa_autoplay_supervisor_last_run.json"
QA_BOOT_SCENE = "scenes/qa/qa_boot.tscn"


@dataclass
class PassResult:
    pass_index: int
    seed: int
    max_actions: int
    max_seconds: int
    exit_code: int
    status: str
    coverage_complete: bool
    investigation_queue: list[dict[str, Any]]
    next_pass_recommendations: list[str]
    missing_room_types: list[str]
    missing_views: list[str]
    missing_mechanics: list[str]
    output_issues: list[dict[str, Any]]
    output_tail: list[str]
    report_path: str
    summary_path: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run autonomous QA smoke-test batches and stop only when a real investigation signal appears."
    )
    parser.add_argument("--project-path", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--godot-exe", type=Path, default=None)
    parser.add_argument("--project-name", default=None)
    parser.add_argument("--runs", type=int, default=DEFAULT_RUNS)
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
    parser.add_argument("--policies", default=DEFAULT_POLICIES)
    parser.add_argument("--max-idle", type=float, default=DEFAULT_IDLE_SECONDS)
    parser.add_argument("--delay", type=float, default=DEFAULT_ACTION_DELAY)
    parser.add_argument("--max-passes", type=int, default=len(DEFAULT_PROFILES))
    parser.add_argument("--profiles", default=None,
                        help="Comma-separated action:seconds profiles, e.g. 40:20,120:60,300:180")
    parser.add_argument("--quiet-godot", action="store_true", default=True)
    parser.add_argument("--print-json", action="store_true")
    return parser.parse_args()


def load_project_name(project_path: Path) -> str:
    project_file = project_path / "project.godot"
    text = project_file.read_text(encoding="utf-8")
    match = re.search(r'^config/name="(.+)"$', text, flags=re.MULTILINE)
    if not match:
        raise RuntimeError(f"Could not determine Godot project name from {project_file}")
    return match.group(1)


def default_userdata_dir(project_name: str) -> Path:
    appdata = os.environ.get("APPDATA")
    if not appdata:
        raise RuntimeError("APPDATA is not set; cannot determine Godot app_userdata path on Windows.")
    return Path(appdata) / "Godot" / "app_userdata" / project_name


def detect_godot_exe(project_path: Path) -> Path:
    env_path = os.environ.get("GODOT_QA_EXE")
    if env_path:
        candidate = Path(env_path)
        if candidate.exists():
            return candidate

    sibling_dir = project_path.parent
    preferred = sibling_dir / "Godot_v4.6.1-stable_win64_console.exe"
    if preferred.exists():
        return preferred

    console_candidates = sorted(sibling_dir.glob("Godot*_console.exe"))
    if console_candidates:
        return console_candidates[-1]

    exe_candidates = sorted(sibling_dir.glob("Godot*.exe"))
    if exe_candidates:
        return exe_candidates[-1]

    raise RuntimeError(
        "Could not locate a Godot executable. Pass --godot-exe or set GODOT_QA_EXE."
    )


def parse_profiles(raw_profiles: str | None, max_passes: int) -> list[dict[str, int]]:
    if not raw_profiles:
        return [dict(profile) for profile in DEFAULT_PROFILES[:max_passes]]

    profiles: list[dict[str, int]] = []
    for chunk in raw_profiles.split(","):
        token = chunk.strip()
        if not token:
            continue
        try:
            actions_text, seconds_text = token.split(":", 1)
            profiles.append({
                "max_actions": max(0, int(actions_text)),
                "max_seconds": max(1, int(seconds_text)),
            })
        except ValueError as exc:
            raise RuntimeError(f"Invalid profile '{token}'. Expected action:seconds.") from exc

    if not profiles:
        raise RuntimeError("No valid QA profiles were supplied.")
    return profiles[:max_passes]


def build_quit_after_msec(max_seconds: int) -> int:
    return max(20_000, int((max_seconds + 15) * 1000))


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def actionable_investigations(queue: list[dict[str, Any]]) -> list[dict[str, Any]]:
    actionable: list[dict[str, Any]] = []
    for item in queue:
        source = str(item.get("source", ""))
        category = str(item.get("category", ""))
        priority = str(item.get("priority", ""))
        if source == "invariant_warning":
            actionable.append(item)
            continue
        if category in {"preflight", "stall", "timeout", "other_failure"}:
            actionable.append(item)
            continue
        if priority == "high":
            actionable.append(item)
    return actionable


def detect_output_issues(stdout: str, stderr: str) -> list[dict[str, Any]]:
    combined = "\n".join(part for part in [stdout, stderr] if part)
    issues: list[dict[str, Any]] = []

    def _first_matching_line(pattern: str) -> str:
        match = re.search(pattern, combined, flags=re.MULTILINE)
        return match.group(0).strip() if match else ""

    parse_error_line = _first_matching_line(r"^SCRIPT ERROR: Parse Error: .+$")
    if parse_error_line:
        issues.append({
            "source": "godot_output",
            "category": "script_parse_error",
            "priority": "high",
            "sample": parse_error_line,
            "hint": "Fix GDScript parse errors first; later runtime evidence is not trustworthy until scripts load cleanly.",
        })

    compile_error_line = _first_matching_line(r"^SCRIPT ERROR: Compile Error: .+$")
    if compile_error_line:
        issues.append({
            "source": "godot_output",
            "category": "script_compile_error",
            "priority": "high",
            "sample": compile_error_line,
            "hint": "Fix GDScript compile failures in dependent scripts before trusting gameplay QA.",
        })

    load_error_line = _first_matching_line(r"^ERROR: Failed to load script .+$")
    if load_error_line:
        issues.append({
            "source": "godot_output",
            "category": "script_load_failure",
            "priority": "high",
            "sample": load_error_line,
            "hint": "A scene is instantiating fallback base nodes because one or more scripts failed to load.",
        })

    invalid_assignment_line = _first_matching_line(r"^SCRIPT ERROR: Invalid assignment of property or key .+$")
    if invalid_assignment_line:
        issues.append({
            "source": "godot_output",
            "category": "runtime_invalid_assignment",
            "priority": "high",
            "sample": invalid_assignment_line,
            "hint": "Inspect typed exports/onready vars and scene wiring; this usually indicates a script-class mismatch or null handoff.",
        })

    invalid_call_line = _first_matching_line(r"^SCRIPT ERROR: Invalid call\. .+$")
    if invalid_call_line:
        issues.append({
            "source": "godot_output",
            "category": "runtime_invalid_call",
            "priority": "medium",
            "sample": invalid_call_line,
            "hint": "Inspect method availability on runtime-owned nodes/resources; a dependency likely fell back to a base type or null.",
        })

    invalid_access_line = _first_matching_line(r"^SCRIPT ERROR: Invalid access to property or key .+$")
    if invalid_access_line:
        issues.append({
            "source": "godot_output",
            "category": "runtime_invalid_access",
            "priority": "medium",
            "sample": invalid_access_line,
            "hint": "Inspect null ownership or unexpected fallback objects before treating later failures as separate bugs.",
        })

    if "Lambda capture at index 0 was freed" in combined:
        issues.append({
            "source": "godot_output",
            "category": "lambda_capture_freed",
            "priority": "medium",
            "hint": "Inspect timer/tween anonymous callbacks that outlive node teardown; prefer bound methods over inline lambdas.",
        })
    if "ObjectDB instances leaked at exit" in combined:
        issues.append({
            "source": "godot_output",
            "category": "objectdb_leak",
            "priority": "low",
            "hint": "Inspect teardown paths for lingering nodes, timers, or tweens that survive quit.",
        })
    if re.search(r"ERROR:\s+\d+\s+resources still in use at exit", combined):
        issues.append({
            "source": "godot_output",
            "category": "resource_still_in_use",
            "priority": "low",
            "hint": "Inspect resources retained across quit; this often pairs with leaked tweens or nodes in headless teardown.",
        })
    if "applied true str form" in combined:
        issues.append({
            "source": "godot_output",
            "category": "debug_print_noise",
            "priority": "low",
            "hint": "Remove stray debug prints from gameplay scripts before trusting QA console output.",
        })
    return issues


def actionable_output_issues(issues: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [issue for issue in issues if str(issue.get("priority", "low")) in {"medium", "high"}]


def run_pass(
    *,
    godot_exe: Path,
    project_path: Path,
    report_path: Path,
    pass_index: int,
    runs: int,
    seed: int,
    policies: str,
    max_actions: int,
    max_seconds: int,
    max_idle: float,
    action_delay: float,
    quiet_godot: bool,
) -> PassResult:
    env = os.environ.copy()
    env["QA_RUNS"] = str(runs)
    env["QA_SEED"] = str(seed)
    env["QA_POLICIES"] = policies
    env["QA_MAX_ACTIONS"] = str(max_actions)
    env["QA_MAX_SECONDS"] = str(max_seconds)
    env["QA_MAX_IDLE_SECONDS"] = str(max_idle)
    env["QA_ACTION_DELAY"] = str(action_delay)
    if quiet_godot:
        env["QA_QUIET"] = "1"

    quit_after_msec = build_quit_after_msec(max_seconds)
    command = [
        str(godot_exe),
        "--headless",
        "--path",
        str(project_path),
        QA_BOOT_SCENE,
        "--quit-after",
        str(quit_after_msec),
    ]

    started_at = time.time()
    completed = subprocess.run(
        command,
        env=env,
        cwd=project_path,
        timeout=max_seconds + 45,
        check=False,
        capture_output=True,
        text=True,
    )
    elapsed = time.time() - started_at

    if not report_path.exists():
        raise RuntimeError(f"QA report was not written: {report_path}")

    report = load_json(report_path)
    suite_summary = report.get("suite_summary", {})
    investigation_queue = suite_summary.get("investigation_queue", []) or []
    coverage = suite_summary.get("coverage", {}) or {}
    coverage_complete = bool(coverage.get("complete", False))
    output_issues = detect_output_issues(completed.stdout or "", completed.stderr or "")
    output_tail = [
        line
        for line in (completed.stdout or "").splitlines()[-20:] + (completed.stderr or "").splitlines()[-20:]
        if line.strip()
    ][-20:]

    result = PassResult(
        pass_index=pass_index,
        seed=seed,
        max_actions=max_actions,
        max_seconds=max_seconds,
        exit_code=int(report.get("exit_code", completed.returncode)),
        status=str(report.get("status", "unknown")),
        coverage_complete=coverage_complete,
        investigation_queue=investigation_queue,
        next_pass_recommendations=list(suite_summary.get("next_pass_recommendations", []) or []),
        missing_room_types=list(suite_summary.get("missing_room_types", []) or []),
        missing_views=list(suite_summary.get("missing_views", []) or []),
        missing_mechanics=list(suite_summary.get("missing_mechanics", []) or []),
        output_issues=output_issues,
        output_tail=output_tail,
        report_path=str(report_path),
        summary_path="",
    )
    print(
        "[QA-SUPERVISOR] pass=%s seed=%s actions=%s seconds=%s elapsed=%.2fs exit=%s coverage_complete=%s actionable=%s"
        % (
            pass_index,
            seed,
            max_actions,
            max_seconds,
            elapsed,
            result.exit_code,
            result.coverage_complete,
            len(actionable_investigations(investigation_queue)) + len(actionable_output_issues(output_issues)),
        )
    )
    return result


def build_supervisor_summary(
    *,
    status: str,
    project_path: Path,
    godot_exe: Path,
    report_path: Path,
    supervisor_report_path: Path,
    policies: str,
    results: list[PassResult],
    final_report: dict[str, Any],
) -> dict[str, Any]:
    return {
        "status": status,
        "project_path": str(project_path),
        "godot_exe": str(godot_exe),
        "qa_report_path": str(report_path),
        "supervisor_report_path": str(supervisor_report_path),
        "policies": policies.split(","),
        "passes_run": len(results),
        "passes": [asdict(result) for result in results],
        "final_investigation_queue": final_report.get("suite_summary", {}).get("investigation_queue", []),
        "final_output_issues": results[-1].output_issues if results else [],
        "final_output_tail": results[-1].output_tail if results else [],
        "final_next_pass_recommendations": final_report.get("suite_summary", {}).get("next_pass_recommendations", []),
        "final_missing_room_types": final_report.get("suite_summary", {}).get("missing_room_types", []),
        "final_missing_views": final_report.get("suite_summary", {}).get("missing_views", []),
        "final_missing_mechanics": final_report.get("suite_summary", {}).get("missing_mechanics", []),
        "final_failure_category_totals": final_report.get("suite_summary", {}).get("failure_category_totals", {}),
        "final_coverage": final_report.get("suite_summary", {}).get("coverage", {}),
    }


def main() -> int:
    args = parse_args()
    project_path = args.project_path.resolve()
    project_name = args.project_name or load_project_name(project_path)
    godot_exe = args.godot_exe.resolve() if args.godot_exe else detect_godot_exe(project_path)
    userdata_dir = default_userdata_dir(project_name)
    report_path = userdata_dir / REPORT_NAME
    supervisor_report_path = userdata_dir / SUPERVISOR_REPORT_NAME
    profiles = parse_profiles(args.profiles, args.max_passes)

    pass_results: list[PassResult] = []
    final_report: dict[str, Any] = {}
    final_status = "max_passes_reached"

    for index, profile in enumerate(profiles, start=1):
        seed = args.seed + ((index - 1) * args.runs)
        result = run_pass(
            godot_exe=godot_exe,
            project_path=project_path,
            report_path=report_path,
            pass_index=index,
            runs=args.runs,
            seed=seed,
            policies=args.policies,
            max_actions=profile["max_actions"],
            max_seconds=profile["max_seconds"],
            max_idle=args.max_idle,
            action_delay=args.delay,
            quiet_godot=args.quiet_godot,
        )
        result.summary_path = str(supervisor_report_path)
        pass_results.append(result)
        final_report = load_json(report_path)

        actionable = actionable_investigations(result.investigation_queue)
        actionable_output = actionable_output_issues(result.output_issues)
        if actionable or actionable_output:
            final_status = "investigate"
            break
        if result.coverage_complete:
            final_status = "coverage_complete"
            break

        only_action_limit = bool(result.investigation_queue) and all(
            str(item.get("category", "")) == "action_limit"
            for item in result.investigation_queue
        )
        if only_action_limit and index < len(profiles):
            continue

        if not result.investigation_queue and index < len(profiles):
            continue

    summary = build_supervisor_summary(
        status=final_status,
        project_path=project_path,
        godot_exe=godot_exe,
        report_path=report_path,
        supervisor_report_path=supervisor_report_path,
        policies=args.policies,
        results=pass_results,
        final_report=final_report,
    )
    write_json(supervisor_report_path, summary)

    if args.print_json:
        print(json.dumps(summary, indent=2))
    else:
        print(
            "[QA-SUPERVISOR] status=%s passes=%s report=%s"
            % (final_status, len(pass_results), supervisor_report_path)
        )

    return 1 if final_status == "investigate" else 0


if __name__ == "__main__":
    sys.exit(main())
