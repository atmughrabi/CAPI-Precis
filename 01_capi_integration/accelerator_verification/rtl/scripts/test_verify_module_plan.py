#!/usr/bin/env python3

import json
import subprocess
import tempfile
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[3]
VALIDATOR = SCRIPT_DIR / "verify_module_plan.py"
INVENTORY = (
    REPO_ROOT /
    "01_capi_integration/accelerator_verification/rtl/manifests/"
    "rtl-inventory.json"
)
PLAN = (
    REPO_ROOT /
    "01_capi_integration/accelerator_verification/rtl/manifests/"
    "coverage-plan.json"
)


def run(inventory, plan, output, write):
    command = [
        str(VALIDATOR),
        "--repo-root",
        str(REPO_ROOT),
        "--inventory",
        str(inventory.relative_to(REPO_ROOT)),
        "--plan",
        str(plan.relative_to(REPO_ROOT)),
        "--output",
        str(output.relative_to(REPO_ROOT)),
    ]
    if write:
        command.append("--write")
    return subprocess.run(command, capture_output=True, text=True)


def expect_failure(result, name):
    if result.returncode == 0:
        raise SystemExit(f"FAIL validator accepted {name}")


def main():
    inventory_payload = json.loads(INVENTORY.read_text())
    plan_payload = json.loads(PLAN.read_text())
    with tempfile.TemporaryDirectory(
        prefix=".module-plan-test-",
        dir=SCRIPT_DIR,
    ) as temporary:
        root = Path(temporary)
        inventory = root / "inventory.json"
        plan = root / "plan.json"
        output = root / "matrix.json"

        inventory.write_text(json.dumps(inventory_payload))
        plan.write_text(json.dumps(plan_payload))
        baseline = run(inventory, plan, output, True)
        if baseline.returncode:
            raise SystemExit(baseline.stderr or baseline.stdout)

        mutation = json.loads(json.dumps(plan_payload))
        mutation["families"].pop()
        plan.write_text(json.dumps(mutation))
        expect_failure(run(inventory, plan, output, True), "missing family")

        mutation = json.loads(json.dumps(plan_payload))
        mutation["families"][1]["match"] = mutation["families"][0]["match"]
        plan.write_text(json.dumps(mutation))
        expect_failure(run(inventory, plan, output, True), "overlapping family")

        mutation = json.loads(json.dumps(plan_payload))
        mutation["families"][0]["implementation_status"] = "implemented"
        plan.write_text(json.dumps(mutation))
        expect_failure(run(inventory, plan, output, True), "status without evidence")

        mutation_inventory = json.loads(json.dumps(inventory_payload))
        mutation_inventory["schema_version"] = 1
        inventory.write_text(json.dumps(mutation_inventory))
        plan.write_text(json.dumps(plan_payload))
        expect_failure(run(inventory, plan, output, True), "old inventory schema")

        inventory.write_text(json.dumps(inventory_payload))
        mutation = json.loads(json.dumps(plan_payload))
        mutation["waivers"] = [{
            "reason": "test",
            "owner": "test",
            "issue": "test",
            "affected_metric": "test",
            "affected_items": ["test"],
            "expiry": "2000-01-01",
            "approval": "test",
        }]
        plan.write_text(json.dumps(mutation))
        expect_failure(run(inventory, plan, output, True), "expired waiver")

        plan.write_text(json.dumps(plan_payload))
        if run(inventory, plan, output, True).returncode:
            raise SystemExit("FAIL could not regenerate baseline matrix")
        mutation = json.loads(json.dumps(plan_payload))
        mutation["families"][0]["required_scenarios"].append("digest mutation")
        plan.write_text(json.dumps(mutation))
        expect_failure(run(inventory, plan, output, False), "stale plan digest")

    print("PASS verify_module_plan_regressions")


if __name__ == "__main__":
    main()
