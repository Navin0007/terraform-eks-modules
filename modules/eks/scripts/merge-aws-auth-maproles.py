#!/usr/bin/env python3
"""Merge the node IAM role into aws-auth mapRoles with valid YAML."""
from __future__ import annotations

import json
import os
import subprocess
import sys

import yaml

NODE_ROLE_ARN = os.environ["NODE_ROLE_ARN"]
CLUSTER_NAME = os.environ["CLUSTER_NAME"]
AWS_REGION = os.environ["AWS_REGION"]
NAMESPACE = "kube-system"
NAME = "aws-auth"


def run(cmd: list[str]) -> str:
    return subprocess.check_output(cmd, text=True)


def role_name(arn: str) -> str:
    return arn.rsplit("/", 1)[-1]


def load_map_roles(raw: str | None) -> list[dict]:
    if not raw or not raw.strip():
        return []
    parsed = yaml.safe_load(raw)
    if parsed is None:
        return []
    if not isinstance(parsed, list):
        raise ValueError("mapRoles must be a YAML list")
    return parsed


def node_entry() -> dict:
    return {
        "rolearn": NODE_ROLE_ARN,
        "username": "system:node:{{EC2PrivateDNSName}}",
        "groups": ["system:bootstrappers", "system:nodes"],
    }


def merge_roles(existing: list[dict]) -> list[dict]:
    target = role_name(NODE_ROLE_ARN)
    kept: list[dict] = []
    for item in existing:
        if not isinstance(item, dict):
            continue
        arn = item.get("rolearn", "")
        # Drop duplicate node mappings (role ARN or matching role name suffix).
        if isinstance(arn, str) and (arn == NODE_ROLE_ARN or arn.endswith(f"/{target}")):
            continue
        kept.append(item)
    kept.append(node_entry())
    return kept


def main() -> int:
    subprocess.run(
        [
            "aws",
            "eks",
            "update-kubeconfig",
            "--name",
            CLUSTER_NAME,
            "--region",
            AWS_REGION,
        ],
        check=True,
        stdout=subprocess.DEVNULL,
    )

    try:
        raw = run(
            [
                "kubectl",
                "get",
                "configmap",
                NAME,
                "-n",
                NAMESPACE,
                "-o",
                "jsonpath={.data.mapRoles}",
            ]
        )
    except subprocess.CalledProcessError:
        raw = ""

    roles = merge_roles(load_map_roles(raw))
    map_roles_yaml = yaml.dump(roles, default_flow_style=False, sort_keys=False).rstrip() + "\n"

    # Round-trip validate before applying.
    yaml.safe_load(map_roles_yaml)

    patch = json.dumps({"data": {"mapRoles": map_roles_yaml}})

    cm_exists = (
        subprocess.run(
            ["kubectl", "get", "configmap", NAME, "-n", NAMESPACE],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ).returncode
        == 0
    )

    if cm_exists:
        subprocess.run(
            [
                "kubectl",
                "patch",
                "configmap",
                NAME,
                "-n",
                NAMESPACE,
                "--type",
                "merge",
                "-p",
                patch,
            ],
            check=True,
        )
    else:
        manifest = {
            "apiVersion": "v1",
            "kind": "ConfigMap",
            "metadata": {"name": NAME, "namespace": NAMESPACE},
            "data": {"mapRoles": map_roles_yaml},
        }
        subprocess.run(
            ["kubectl", "apply", "-f", "-"],
            input=yaml.dump(manifest),
            text=True,
            check=True,
        )

    print(map_roles_yaml)
    if NODE_ROLE_ARN not in map_roles_yaml:
        print(f"::error::Node role {NODE_ROLE_ARN} missing after merge", file=sys.stderr)
        return 1
    print(f"aws-auth mapRoles updated for {NODE_ROLE_ARN}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
