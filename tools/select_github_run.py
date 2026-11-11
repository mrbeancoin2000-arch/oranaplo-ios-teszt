#!/usr/bin/env python3
"""Select exactly one GitHub Actions run from gh run list JSON.

Usage: gh run list --json databaseId,headSha,event,displayTitle | python
       tools/select_github_run.py --token <unique-guid> --sha <commit-sha>
Exit 0: exactly one found (stdout contains ONLY the numeric ID).
Exit 2: no match yet, safe to retry. Exit 3: ambiguous. Exit 4: invalid data.
"""
import argparse
import json
import re
import sys


def resolve(raw, token, sha):
    if not re.fullmatch(r"[0-9a-f]{32}", token):
        raise ValueError("Invalid dispatch token")
    if not re.fullmatch(r"[0-9a-fA-F]{40}", sha):
        raise ValueError("Invalid Git commit SHA")
    data = json.loads(raw)
    if not isinstance(data, list):
        raise ValueError("Expected GitHub run list array")
    title = "OraNaplo CI " + token
    matches = []
    for item in data:
        if not isinstance(item, dict):
            raise ValueError("Non-object in run list")
        if (item.get("displayTitle") == title
                and item.get("event") == "workflow_dispatch"
                and item.get("headSha", "").lower() == sha.lower()):
            run_id = item.get("databaseId")
            if not isinstance(run_id, int) or isinstance(run_id, bool) or run_id < 1:
                raise ValueError("Invalid numeric workflow run ID")
            matches.append(run_id)
    if not matches:
        return None
    if len(matches) > 1:
        raise RuntimeError("Multiple GitHub runs match the unique request")
    return matches[0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--token", required=True)
    ap.add_argument("--sha", required=True)
    args = ap.parse_args()
    try:
        result = resolve(sys.stdin.read(), args.token, args.sha)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return 3
    except (ValueError, json.JSONDecodeError) as exc:
        print(str(exc), file=sys.stderr)
        return 4
    if result is None:
        return 2
    print(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
