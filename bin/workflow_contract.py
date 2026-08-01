#!/usr/bin/env python3
"""Shared workflow manifest contracts for runtime phase instances."""

import json
import os
import re


PHASE_ID_RE = re.compile(r"^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$")


def load_manifest(path):
    with open(path, "r", encoding="utf-8") as file_handle:
        return json.load(file_handle)


def active_phase_ids(manifest):
    phases = {phase["id"]: phase for phase in manifest.get("phases", [])}
    if manifest.get("kind") == "run":
        active = set(manifest.get("execution", {}).get("order", []))
    else:
        active = set(phases)

    # A review loop may invoke its fixup phase even when the fixup is not a
    # top-level execution item.
    for loop in manifest.get("loops", {}).values():
        review_phase = loop.get("review_phase")
        fixup_phase = loop.get("fixup_phase")
        if review_phase in active and fixup_phase in phases:
            active.add(fixup_phase)
    return active


def validate_phase_id(value):
    if not isinstance(value, str) or not PHASE_ID_RE.fullmatch(value):
        raise ValueError(f"phase id must be lowercase kebab-case: {value!r}")


def validate_instance_name_template(value):
    if not isinstance(value, str) or not value:
        raise ValueError("instance_name_template must be a non-empty string")
    if value.count("{round}") > 1:
        raise ValueError(f"instance_name_template may contain {{round}} at most once: {value}")
    remaining_placeholders = value.replace("{round}", "")
    if "{" in remaining_placeholders or "}" in remaining_placeholders:
        raise ValueError(f"instance_name_template only supports {{round}}: {value}")

    rendered = value.replace("{round}", "1")
    if not PHASE_ID_RE.fullmatch(rendered):
        raise ValueError(
            "instance_name_template fixed text must render to lowercase kebab-case: "
            f"{value}"
        )


def instance_name_matches(template, phase_name):
    pattern = re.escape(template).replace(re.escape("{round}"), r"[1-9][0-9]*")
    return re.fullmatch(pattern, phase_name) is not None


def allowed_phase_name(manifest, phase_name):
    if not isinstance(phase_name, str):
        return False
    phases = {phase["id"]: phase for phase in manifest.get("phases", [])}
    for phase_id in active_phase_ids(manifest):
        phase = phases.get(phase_id)
        if phase is None:
            continue
        if phase_name == phase_id:
            return True
        template = phase.get("instance_name_template", phase_id)
        if isinstance(template, str) and instance_name_matches(template, phase_name):
            return True
    return False


def validate_state_phase_names(state, manifest):
    errors = []
    for phase_name in state.get("phases", {}):
        if not allowed_phase_name(manifest, phase_name):
            errors.append(
                "workflow-state phase name is not allowed by manifest templates: "
                f"{phase_name}"
            )
    return errors


def manifest_path_from_state(state):
    metadata = state.get("metadata", {})
    path = metadata.get("flow_file") if isinstance(metadata, dict) else None
    return path if isinstance(path, str) and path else None
