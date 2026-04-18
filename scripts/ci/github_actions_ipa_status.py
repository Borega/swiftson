#!/usr/bin/env python3
"""
Check/await the GitHub Actions IPA workflow result for a specific commit SHA.

- Auth: uses `git credential fill` for github.com and consumes the `password` as token.
- Repo: inferred from `git remote get-url origin` unless --repo is provided.
- On failure: prints the first actionable error lines from run logs and exits non-zero.
"""

from __future__ import annotations

import argparse
import io
import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from dataclasses import dataclass
from typing import Iterable


DEFAULT_WORKFLOW = "Build Unsigned IPA"
API_VERSION = "2022-11-28"
USER_AGENT = "filius-ci-helper"


@dataclass
class RepoRef:
    owner: str
    repo: str


def run_cmd(args: list[str], input_text: str | None = None) -> str:
    proc = subprocess.run(
        args,
        input=input_text,
        text=True,
        capture_output=True,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"command failed ({' '.join(args)}): {proc.stderr.strip() or proc.stdout.strip()}")
    return proc.stdout.strip()


def get_token_from_git_credentials() -> str:
    out = run_cmd(["git", "credential", "fill"], "protocol=https\nhost=github.com\n\n")
    fields: dict[str, str] = {}
    for line in out.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            fields[key.strip()] = value.strip()
    token = fields.get("password", "")
    if not token:
        raise RuntimeError("github credential helper did not return a token/password")
    return token


def infer_repo_from_origin() -> RepoRef:
    origin = run_cmd(["git", "remote", "get-url", "origin"])
    match = re.search(r"github\.com[:/](?P<owner>[^/]+)/(?P<repo>[^/.]+)(?:\.git)?$", origin)
    if not match:
        raise RuntimeError(f"could not parse GitHub owner/repo from origin: {origin}")
    return RepoRef(owner=match.group("owner"), repo=match.group("repo"))


def github_get_bytes(token: str, url: str) -> bytes:
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": API_VERSION,
            "User-Agent": USER_AGENT,
        },
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read()


def github_get_json(token: str, url: str) -> dict:
    payload = github_get_bytes(token, url)
    return json.loads(payload)


def list_runs(token: str, repo: RepoRef, sha: str) -> list[dict]:
    params = urllib.parse.urlencode({"head_sha": sha, "per_page": 50})
    url = f"https://api.github.com/repos/{repo.owner}/{repo.repo}/actions/runs?{params}"
    data = github_get_json(token, url)
    return data.get("workflow_runs", [])


def select_workflow_run(runs: Iterable[dict], workflow_name: str) -> dict | None:
    filtered = [r for r in runs if r.get("name") == workflow_name]
    if not filtered:
        return None
    filtered.sort(key=lambda r: r.get("created_at", ""), reverse=True)
    return filtered[0]


def wait_for_completion(token: str, repo: RepoRef, run_id: int, timeout: int, interval: int) -> dict:
    deadline = time.time() + timeout
    url = f"https://api.github.com/repos/{repo.owner}/{repo.repo}/actions/runs/{run_id}"
    while True:
        run = github_get_json(token, url)
        status = run.get("status")
        conclusion = run.get("conclusion")
        print(f"status={status} conclusion={conclusion}")
        if status == "completed":
            return run
        if time.time() >= deadline:
            raise TimeoutError(f"timed out waiting for run {run_id} completion")
        time.sleep(interval)


def extract_error_lines_from_logs(zip_bytes: bytes, max_lines: int) -> list[str]:
    patterns = [
        re.compile(r"\berror:\b", re.IGNORECASE),
        re.compile(r"Command .* failed with a nonzero exit code", re.IGNORECASE),
        re.compile(r"\*\* BUILD FAILED \*\*", re.IGNORECASE),
    ]

    lines: list[str] = []
    with zipfile.ZipFile(io.BytesIO(zip_bytes)) as zf:
        for name in sorted(zf.namelist()):
            text = zf.read(name).decode("utf-8", errors="replace")
            for idx, line in enumerate(text.splitlines(), start=1):
                if any(p.search(line) for p in patterns):
                    lines.append(f"{name}:{idx}: {line}")
                    if len(lines) >= max_lines:
                        return lines
    return lines


def list_artifacts(token: str, repo: RepoRef, run_id: int) -> list[dict]:
    url = f"https://api.github.com/repos/{repo.owner}/{repo.repo}/actions/runs/{run_id}/artifacts"
    data = github_get_json(token, url)
    return data.get("artifacts", [])


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Check/wait GitHub IPA workflow status for a commit SHA.")
    parser.add_argument("--repo", help="owner/repo (default: infer from origin)")
    parser.add_argument("--sha", help="commit SHA (default: HEAD)")
    parser.add_argument("--workflow", default=DEFAULT_WORKFLOW, help=f"workflow name (default: {DEFAULT_WORKFLOW})")
    parser.add_argument("--wait", action="store_true", help="wait until run completes")
    parser.add_argument("--timeout", type=int, default=1800, help="max wait seconds when --wait is set")
    parser.add_argument("--interval", type=int, default=15, help="poll interval seconds when --wait is set")
    parser.add_argument("--max-error-lines", type=int, default=80, help="maximum extracted error lines on failure")
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    try:
        token = get_token_from_git_credentials()
        if args.repo:
            if "/" not in args.repo:
                raise RuntimeError("--repo must be in owner/repo format")
            owner, repo_name = args.repo.split("/", 1)
            repo = RepoRef(owner=owner, repo=repo_name)
        else:
            repo = infer_repo_from_origin()

        sha = args.sha or run_cmd(["git", "rev-parse", "HEAD"])

        runs = list_runs(token, repo, sha)
        run = select_workflow_run(runs, args.workflow)
        if not run:
            print(f"No workflow run named '{args.workflow}' found for sha {sha}")
            return 2

        run_id = int(run["id"])
        run_url = run.get("html_url", "")
        print(f"run_id={run_id} sha={sha} workflow='{args.workflow}'")
        if run_url:
            print(f"run_url={run_url}")

        if args.wait:
            run = wait_for_completion(token, repo, run_id, args.timeout, args.interval)

        status = run.get("status")
        conclusion = run.get("conclusion")
        print(f"final_status={status} final_conclusion={conclusion}")

        if status != "completed":
            return 3

        if conclusion == "success":
            artifacts = list_artifacts(token, repo, run_id)
            if artifacts:
                print("artifacts:")
                for artifact in artifacts:
                    print(
                        f"- {artifact.get('name')} size_bytes={artifact.get('size_in_bytes')} expired={artifact.get('expired')}"
                    )
            return 0

        # failure/cancelled/etc.
        logs_url = f"https://api.github.com/repos/{repo.owner}/{repo.repo}/actions/runs/{run_id}/logs"
        try:
            zip_bytes = github_get_bytes(token, logs_url)
            errors = extract_error_lines_from_logs(zip_bytes, max_lines=args.max_error_lines)
            if errors:
                print("workflow_error_lines:")
                for line in errors:
                    print(line)
            else:
                print("workflow_error_lines: (none matched; inspect full run logs)")
        except urllib.error.HTTPError as http_err:
            print(f"failed to download logs: HTTP {http_err.code}")
        return 1

    except Exception as exc:
        print(f"fatal: {exc}")
        return 10


if __name__ == "__main__":
    raise SystemExit(main())
