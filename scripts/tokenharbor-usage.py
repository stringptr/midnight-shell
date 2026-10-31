#!/usr/bin/env python3
"""Report Token Harbor free-allowance usage for a single credential.

The gateway only exposes its allowance counters on a successful chat
completion, so this sends one tiny completion to a free model and reads the
response headers:

    x-th-free-used-pct   percentage of the rolling free allowance used
    x-th-free-resets     ISO timestamp of the next reset

When the allowance is exhausted the request returns 429 and the reset time is
parsed from the error message instead.

The API key is read from opencode's credential store (opened read-only) so it
never appears on a command line or in any log. Usage:

    tokenharbor-usage.py <integration_id> <base_url> <free_model>

Output is a single line:

    ok|<usedPercent>|<resetISO>
    exhausted|100|<resetISO>
    error|<code>|<message>
"""

import datetime as dt
import json
import os
import re
import sqlite3
import sys
import urllib.error
import urllib.request

RESET_RE = re.compile(r"starts on (\d{1,2} \w{3} \d{4}) at (\d{2}:\d{2}) UTC")


def read_key(integration_id: str) -> str:
    db = os.path.join(os.environ.get("HOME", ""), ".local/share/opencode/opencode.db")
    try:
        con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    except sqlite3.Error:
        return ""
    try:
        row = con.execute(
            "SELECT value FROM credential WHERE integration_id = ?", (integration_id,)
        ).fetchone()
    except sqlite3.Error:
        return ""
    finally:
        con.close()
    if not row:
        return ""
    try:
        return json.loads(row[0]).get("key", "")
    except (ValueError, TypeError):
        return ""


def normalize_iso(value: str) -> str:
    if not value:
        return ""
    try:
        parsed = dt.datetime.fromisoformat(value)
    except ValueError:
        return ""
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def reset_from_message(message: str) -> str:
    match = RESET_RE.search(message)
    if not match:
        return ""
    try:
        when = dt.datetime.strptime(f"{match.group(1)} {match.group(2)}", "%d %b %Y %H:%M")
    except ValueError:
        return ""
    return when.replace(tzinfo=dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def main() -> None:
    if len(sys.argv) < 4:
        print("error|args|")
        return

    integration_id, base, model = sys.argv[1], sys.argv[2].rstrip("/"), sys.argv[3]
    key = read_key(integration_id)
    if not key:
        print("error|nokey|")
        return

    payload = json.dumps(
        {
            "model": model,
            "messages": [{"role": "user", "content": "."}],
            "max_tokens": 1,
            "stream": False,
        }
    ).encode()
    request = urllib.request.Request(
        f"{base}/chat/completions",
        data=payload,
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=45) as resp:
            percent = resp.headers.get("x-th-free-used-pct", "")
            reset = normalize_iso(resp.headers.get("x-th-free-resets", ""))
            resp.read(1)
            print(f"ok|{percent}|{reset}")
    except urllib.error.HTTPError as err:
        body = err.read(4000).decode("utf-8", "replace")
        if err.code == 429:
            print(f"exhausted|100|{reset_from_message(body)}")
        else:
            print(f"error|{err.code}|")
    except Exception:
        print("error|unreachable|")


if __name__ == "__main__":
    main()
