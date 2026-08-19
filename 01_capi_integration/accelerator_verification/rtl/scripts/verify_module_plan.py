#!/usr/bin/env python3

import argparse
import hashlib
import json
import re
import subprocess
import sys
from collections import Counter
from datetime import date
from pathlib import Path


REQUIRED_PROFILE_FIELDS = (
    "stimulus",
    "oracle",
    "assertions",
    "backpressure",
    "coverage",
    "failure_artifacts",
)
REQUIRED_FAMILY_FIELDS = (
    "id",
    "test_id",
    "priority",
    "profile",
    "oracle_id",
    "implementation_status",
    "match",
    "required_scenarios",
)
VALID_STATUSES = {"planned", "in_progress", "implemented", "blocked"}
VALID_PRIORITIES = {"P0", "P1", "P2"}
VALID_MATCH_FIELDS = {
    "verification_units",
    "module_names",
    "path_regex",
    "module_regex",
}


def fail(message):
    print(f"FAIL {message}", file=sys.stderr)
    raise SystemExit(1)


def load_json(path):
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read {path}: {error}")


def matches(family, module):
    match = family["match"]
    unknown = set(match) - VALID_MATCH_FIELDS
    if unknown:
        fail(f"family {family['id']} has unknown match fields: {sorted(unknown)}")
    checks = []
    if "verification_units" in match:
        checks.append(module["verification_unit"] in match["verification_units"])
    if "module_names" in match:
        checks.append(module["module"] in match["module_names"])
    if "path_regex" in match:
        checks.append(
            any(re.search(pattern, module["path"]) for pattern in match["path_regex"])
        )
    if "module_regex" in match:
        checks.append(
            any(
                re.fullmatch(pattern, module["module"])
                for pattern in match["module_regex"]
            )
        )
    if not checks:
        fail(f"family {family['id']} has no supported matcher")
    return all(checks)


def validate_policy(plan):
    policy = plan.get("coverage_policy", {})
    required_targets = {
        "module_mapping_percent": 100,
        "reachable_statement_percent": 100,
        "reachable_branch_percent": 100,
        "fsm_state_percent": 100,
        "fsm_transition_percent": 100,
        "functional_bin_percent": 100,
        "assertion_goal_percent": 100,
        "reachable_control_toggle_percent": 100,
        "context_execution_percent": 100,
    }
    targets = policy.get("closure_targets", {})
    for name, expected in required_targets.items():
        if targets.get(name) != expected:
            fail(f"coverage target {name} must be {expected}")
    if policy.get("execution_granularity") not in {
        "module_declaration",
        "distinct_source_hash_with_all_contexts",
    }:
        fail("coverage policy has invalid execution_granularity")
    waiver_fields = set(policy.get("waiver_required_fields", []))
    required_waiver_fields = {
        "reason",
        "owner",
        "issue",
        "affected_metric",
        "affected_items",
        "expiry",
        "approval",
    }
    if waiver_fields != required_waiver_fields:
        fail("coverage waiver fields are incomplete")
    waivers = plan.get("waivers")
    if not isinstance(waivers, list):
        fail("coverage plan must contain a waivers array")
    for waiver in waivers:
        if set(waiver) != required_waiver_fields:
            fail("coverage waiver record has missing or extra fields")
        if not all(waiver[field] for field in required_waiver_fields):
            fail("coverage waiver fields must be nonempty")
        try:
            expiry = date.fromisoformat(waiver["expiry"])
        except ValueError:
            fail("coverage waiver expiry must use YYYY-MM-DD")
        if expiry < date.today():
            fail(f"coverage waiver expired: {waiver['issue']}")


def validate_profiles(plan):
    profiles = plan.get("strategy_profiles", {})
    if not profiles:
        fail("coverage plan has no strategy profiles")
    for profile_id, profile in profiles.items():
        for field in REQUIRED_PROFILE_FIELDS:
            values = profile.get(field)
            if not isinstance(values, list) or not values:
                fail(f"profile {profile_id} has no {field}")
    return profiles


def active_modules(inventory, prefixes):
    modules = []
    for item in inventory.get("files", []):
        if item.get("status") != "active":
            continue
        if not any(item["path"].startswith(prefix) for prefix in prefixes):
            continue
        for declaration in item.get("declarations", []):
            if declaration.get("kind") != "module":
                continue
            modules.append({
                "path": item["path"],
                "module": declaration["name"],
                "sha256": item["sha256"],
                "verification_unit": item["verification_unit"],
                "contexts": sorted(
                    membership.get("layout") or membership.get("manifest")
                    for membership in item.get("build_membership", [])
                    if membership.get("layout") or membership.get("manifest")
                ),
            })
    return sorted(modules, key=lambda item: (item["path"], item["module"]))


def active_packages(inventory, prefixes):
    packages = []
    for item in inventory.get("files", []):
        if item.get("status") != "active":
            continue
        if not any(item["path"].startswith(prefix) for prefix in prefixes):
            continue
        for declaration in item.get("declarations", []):
            if declaration.get("kind") == "package":
                packages.append({
                    "path": item["path"],
                    "package": declaration["name"],
                    "sha256": item["sha256"],
                    "verification_unit": item["verification_unit"],
                    "contexts": sorted(
                        membership.get("layout") or membership.get("manifest")
                        for membership in item.get("build_membership", [])
                        if membership.get("layout") or membership.get("manifest")
                    ),
                })
    return sorted(packages, key=lambda item: (item["path"], item["package"]))


def validate_status(owner, repo_root, evidence_sets):
    status = owner["implementation_status"]
    if status not in VALID_STATUSES:
        fail(f"{owner['id']} has invalid status")
    if status in {"planned", "blocked"}:
        return None
    evidence = owner.get("evidence")
    evidence_ref = owner.get("evidence_ref")
    if evidence_ref:
        if evidence is not None:
            fail(f"{owner['id']} has both evidence and evidence_ref")
        evidence = evidence_sets.get(evidence_ref)
        if evidence is None:
            fail(f"{owner['id']} references unknown evidence set {evidence_ref}")
    required = {
        "test_target",
        "runner",
        "suite_registry",
        "test_sources",
        "scenario_manifest",
        "coverage_manifest",
    }
    if not isinstance(evidence, dict) or set(evidence) != required:
        fail(f"{owner['id']} status {status} lacks executable evidence")
    if (
        not evidence["test_target"] or
        not evidence["runner"] or
        not evidence["suite_registry"] or
        not evidence["test_sources"]
    ):
        fail(f"{owner['id']} evidence is incomplete")
    if evidence["runner"] not in evidence["test_sources"]:
        fail(f"{owner['id']} runner is not hashed as a test source")
    if evidence["suite_registry"] not in evidence["test_sources"]:
        fail(f"{owner['id']} suite registry is not hashed as a test source")
    target = subprocess.run(
        [
            "make",
            "-s",
            "-n",
            "--no-print-directory",
            "-C",
            str(repo_root),
            evidence["test_target"],
        ],
        capture_output=True,
        text=True,
    )
    if target.returncode:
        fail(f"{owner['id']} Make target does not resolve: {evidence['test_target']}")
    normalized_target = target.stdout.replace("./", "")
    if evidence["runner"] not in normalized_target:
        fail(f"{owner['id']} Make target does not invoke its hashed runner")
    verify = subprocess.run(
        [
            "make",
            "-s",
            "-n",
            "--no-print-directory",
            "-C",
            str(repo_root),
            "verify",
        ],
        capture_output=True,
        text=True,
    )
    normalized_verify = verify.stdout.replace("./", "")
    if (
        verify.returncode or
        evidence["suite_registry"] not in normalized_verify
    ):
        fail(f"{owner['id']} is not reachable from make verify")
    for field in ("test_sources",):
        for source in evidence[field]:
            if not (repo_root / source).is_file():
                fail(f"{owner['id']} evidence path does not exist: {source}")
    for field in ("scenario_manifest", "coverage_manifest"):
        if not (repo_root / evidence[field]).is_file():
            fail(f"{owner['id']} evidence path does not exist: {evidence[field]}")
    digest = hashlib.sha256()
    evidence_paths = [
        *evidence["test_sources"],
        evidence["scenario_manifest"],
        evidence["coverage_manifest"],
    ]
    for relative_path in sorted(evidence_paths):
        path = repo_root / relative_path
        digest.update(relative_path.encode())
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def validate_non_module_suites(
    plan, packages, profiles, repo_root, evidence_sets
):
    suites = plan.get("non_module_suites", [])
    if len(suites) != plan["module_scope"].get("expected_non_module_suites"):
        fail("non-module suite count changed")
    if not packages and suites:
        fail("non-module suites exist without active package declarations")
    package_owners = []
    for suite in suites:
        for field in (
            "id",
            "test_id",
            "declaration_kind",
            "priority",
            "profile",
            "oracle_id",
            "implementation_status",
            "required_scenarios",
        ):
            if field not in suite:
                fail(f"non-module suite is missing {field}")
        if suite["declaration_kind"] != "package":
            fail(f"unsupported non-module declaration kind: {suite['id']}")
        if suite["profile"] not in profiles:
            fail(f"{suite['id']} references unknown profile")
        if suite["priority"] not in VALID_PRIORITIES:
            fail(f"{suite['id']} has invalid priority")
        if not suite["required_scenarios"] or not suite["oracle_id"]:
            fail(f"{suite['id']} lacks scenarios or oracle")
        suite["_evidence_sha256"] = validate_status(
            suite, repo_root, evidence_sets
        )
        package_owners.append(suite)
    if len(package_owners) != 1 and packages:
        fail("active packages must have exactly one contract-suite owner")
    return [
        {
            **package,
            "suite": package_owners[0]["id"],
            "test_id": package_owners[0]["test_id"],
            "priority": package_owners[0]["priority"],
            "strategy_profile": package_owners[0]["profile"],
            "oracle_id": package_owners[0]["oracle_id"],
            "implementation_status": package_owners[0]["implementation_status"],
            "evidence_sha256": package_owners[0]["_evidence_sha256"],
        }
        for package in packages
    ]


def build_matrix(inventory, plan, repo_root, inventory_sha256, plan_sha256):
    if plan.get("schema_version") != 1:
        fail("unsupported module coverage-plan schema")
    if inventory.get("schema_version") != plan.get("inventory_schema_version"):
        fail("coverage plan does not support this inventory schema")
    validate_policy(plan)
    profiles = validate_profiles(plan)
    evidence_sets = plan.get("evidence_sets", {})
    if not isinstance(evidence_sets, dict):
        fail("evidence_sets must be an object")

    scope = plan.get("module_scope", {})
    prefixes = scope.get("active_path_prefixes", [])
    if not prefixes:
        fail("module scope has no active_path_prefixes")
    if inventory.get("rtl_roots") != scope.get("expected_inventory_roots"):
        fail("coverage plan inventory roots do not match")
    if inventory.get("generated_by") != scope.get("expected_inventory_generator"):
        fail("coverage plan inventory generator does not match")
    modules = active_modules(inventory, prefixes)
    packages = active_packages(inventory, prefixes)
    if len(modules) != scope.get("expected_module_declarations"):
        fail(
            f"active module count {len(modules)} != "
            f"{scope.get('expected_module_declarations')}"
        )
    hashes = {module["sha256"] for module in modules}
    if len(hashes) != scope.get("expected_distinct_source_hashes"):
        fail(
            f"active source hash count {len(hashes)} != "
            f"{scope.get('expected_distinct_source_hashes')}"
        )
    if len(packages) != scope.get("expected_package_declarations"):
        fail(
            f"active package count {len(packages)} != "
            f"{scope.get('expected_package_declarations')}"
        )

    families = plan.get("families", [])
    family_ids = [family.get("id") for family in families]
    if len(family_ids) != len(set(family_ids)):
        fail("duplicate coverage family id")
    test_ids = [family.get("test_id") for family in families]
    if len(test_ids) != len(set(test_ids)):
        fail("duplicate coverage test id")
    if len(families) != scope.get("expected_family_plans"):
        fail(
            f"coverage family count {len(families)} != "
            f"{scope.get('expected_family_plans')}"
        )
    family_evidence = {}
    for family in families:
        for field in REQUIRED_FAMILY_FIELDS:
            if field not in family:
                fail(f"coverage family is missing {field}: {family}")
        if family["priority"] not in VALID_PRIORITIES:
            fail(f"family {family['id']} has invalid priority")
        family_evidence[family["id"]] = validate_status(
            family, repo_root, evidence_sets
        )
        if family["profile"] not in profiles:
            fail(f"family {family['id']} references unknown profile")
        if not family["required_scenarios"] or not family["oracle_id"]:
            fail(f"family {family['id']} has no scenarios or oracle")

    matrix = []
    family_counts = Counter()
    for module in modules:
        owners = [family for family in families if matches(family, module)]
        if len(owners) != 1:
            fail(
                f"{module['path']}::{module['module']} has "
                f"{len(owners)} coverage owners"
            )
        family = owners[0]
        family_counts[family["id"]] += 1
        matrix.append({
            **module,
            "family": family["id"],
            "test_id": family["test_id"],
            "priority": family["priority"],
            "strategy_profile": family["profile"],
            "oracle_id": family["oracle_id"],
            "implementation_status": family["implementation_status"],
            "evidence_sha256": family_evidence[family["id"]],
        })

    empty_families = sorted(set(family_ids) - set(family_counts))
    if empty_families:
        fail("coverage families match no modules: " + ", ".join(empty_families))

    context_executions = sum(len(module["contexts"]) for module in matrix)
    if context_executions != scope.get("expected_context_executions"):
        fail(
            f"context execution count {context_executions} != "
            f"{scope.get('expected_context_executions')}"
        )
    if any(not module["contexts"] for module in matrix):
        fail("every production module requires at least one build context")

    hash_families = {}
    for module in matrix:
        hash_families.setdefault(module["sha256"], set()).add(module["family"])
    cross_family_hashes = {
        source_hash: sorted(family_ids)
        for source_hash, family_ids in hash_families.items()
        if len(family_ids) > 1
    }
    exceptions = plan.get("cross_family_hash_exceptions", [])
    exception_map = {
        exception.get("sha256"): exception for exception in exceptions
    }
    if set(exception_map) != set(cross_family_hashes):
        fail("cross-family source-hash exceptions are incomplete or stale")
    for source_hash, family_ids in cross_family_hashes.items():
        exception = exception_map[source_hash]
        if sorted(exception.get("families", [])) != family_ids:
            fail(f"cross-family hash ownership changed: {source_hash}")
        if not exception.get("reason") or not exception.get("issue"):
            fail(f"cross-family hash exception lacks reason/issue: {source_hash}")

    package_matrix = validate_non_module_suites(
        plan, packages, profiles, repo_root, evidence_sets
    )
    return {
        "schema_version": 1,
        "plan_id": plan["plan_id"],
        "coverage_plan_sha256": plan_sha256,
        "rtl_inventory_sha256": inventory_sha256,
        "inventory_schema_version": inventory["schema_version"],
        "summary": {
            "module_declarations": len(matrix),
            "distinct_source_hashes": len(hashes),
            "families": len(families),
            "package_declarations": len(package_matrix),
            "non_module_suites": len(plan.get("non_module_suites", [])),
            "context_executions": context_executions,
            "status_counts": dict(sorted(Counter(
                entry["implementation_status"] for entry in matrix
            ).items())),
            "family_status_counts": dict(sorted(Counter(
                family["implementation_status"] for family in families
            ).items())),
            "family_module_counts": dict(sorted(family_counts.items())),
        },
        "modules": matrix,
        "non_module_declarations": package_matrix,
    }


def main():
    parser = argparse.ArgumentParser(
        description="Validate and expand an RTL module coverage plan"
    )
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--inventory", type=Path, required=True)
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()

    repo_root = args.repo_root.resolve()
    inventory_path = (repo_root / args.inventory).resolve()
    plan_path = (repo_root / args.plan).resolve()
    output_path = (repo_root / args.output).resolve()
    for path in (inventory_path, plan_path, output_path.parent):
        try:
            path.relative_to(repo_root)
        except ValueError:
            fail(f"path escapes repository root: {path}")

    inventory_bytes = inventory_path.read_bytes()
    plan_bytes = plan_path.read_bytes()
    inventory = load_json(inventory_path)
    plan = load_json(plan_path)
    matrix = build_matrix(
        inventory,
        plan,
        repo_root,
        hashlib.sha256(inventory_bytes).hexdigest(),
        hashlib.sha256(plan_bytes).hexdigest(),
    )
    serialized = json.dumps(matrix, indent=2) + "\n"
    if args.write:
        output_path.write_text(serialized)
        print(f"WROTE {output_path.relative_to(repo_root)}")
    elif not output_path.is_file():
        fail(f"missing module matrix: {output_path.relative_to(repo_root)}")
    elif output_path.read_text() != serialized:
        fail(
            "module test matrix is stale; review the inventory/plan and "
            "regenerate it"
        )

    summary = matrix["summary"]
    print(
        f"PASS module_coverage_plan {matrix['plan_id']} "
        f"modules={summary['module_declarations']} "
        f"hashes={summary['distinct_source_hashes']} "
        f"families={summary['families']} "
        f"packages={summary['package_declarations']} "
        f"contexts={summary['context_executions']}"
    )


if __name__ == "__main__":
    main()
