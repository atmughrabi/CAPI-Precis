#!/usr/bin/env python3

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path


def fail(message):
    print(f"FAIL rtl_unit_suites {message}", file=sys.stderr)
    raise SystemExit(1)


def main():
    parser = argparse.ArgumentParser(
        description="Run every implemented RTL family from a coverage plan"
    )
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument(
        "--require-complete",
        action="store_true",
        help="fail if any family or non-module suite is not implemented",
    )
    args = parser.parse_args()

    repo_root = args.repo_root.resolve()
    plan_path = (repo_root / args.plan).resolve()
    try:
        plan_path.relative_to(repo_root)
        plan = json.loads(plan_path.read_text())
    except (ValueError, OSError, json.JSONDecodeError) as error:
        fail(f"cannot read coverage plan: {error}")

    owners = [*plan.get("families", []), *plan.get("non_module_suites", [])]
    incomplete = [
        owner["id"]
        for owner in owners
        if owner["implementation_status"] != "implemented"
    ]
    if args.require_complete and incomplete:
        fail("incomplete suites: " + ", ".join(sorted(incomplete)))

    runners = {}
    evidence_sets = plan.get("evidence_sets", {})
    for owner in owners:
        if owner["implementation_status"] != "implemented":
            continue
        evidence = owner.get("evidence")
        if evidence is None and owner.get("evidence_ref"):
            evidence = evidence_sets.get(owner["evidence_ref"])
        evidence = evidence or {}
        runner = evidence.get("runner")
        if not runner:
            fail(f"implemented owner has no runner: {owner['id']}")
        runners.setdefault(runner, []).append(owner["id"])

    if not runners:
        fail("coverage plan has no implemented suites")

    environment = os.environ.copy()
    environment.pop("MAKEFLAGS", None)
    environment.pop("MFLAGS", None)
    for runner, owner_ids in sorted(runners.items()):
        runner_path = (repo_root / runner).resolve()
        try:
            runner_path.relative_to(repo_root)
        except ValueError:
            fail(f"runner escapes repository root: {runner}")
        if not runner_path.is_file() or not os.access(runner_path, os.X_OK):
            fail(f"runner is unavailable: {runner}")
        print(
            f"RUN rtl_unit_suite runner={runner} "
            f"owners={','.join(sorted(owner_ids))}"
        )
        result = subprocess.run(
            [str(runner_path)],
            cwd=repo_root,
            env=environment,
            capture_output=True,
            text=True,
        )
        if result.stdout:
            print(result.stdout, end="")
        if result.stderr:
            print(result.stderr, end="", file=sys.stderr)
        if result.returncode:
            fail(f"runner failed: {runner}")
        reported_owners = set()
        for line in result.stdout.splitlines():
            if line.startswith("OWNERS:"):
                reported_owners.update(
                    owner for owner in line.split(":", 1)[1].split(",") if owner
                )
        expected_owners = set(owner_ids)
        if reported_owners != expected_owners:
            fail(
                f"runner owner mismatch: {runner} "
                f"expected={sorted(expected_owners)} "
                f"reported={sorted(reported_owners)}"
            )

    print(
        f"PASS rtl_unit_suites runners={len(runners)} "
        f"owners={sum(len(owner_ids) for owner_ids in runners.values())} "
        f"incomplete={len(incomplete)}"
    )


if __name__ == "__main__":
    main()
