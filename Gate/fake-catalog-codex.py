#!/usr/bin/env python3
import json
import os
import sys
import time

catalog_reads = 0
account_reads = 0
quota_reads = 0
usage_reads = 0
phase = os.environ.get("TALLYGENT_CATALOG_PROBE_PHASE", "catalog")
held_account = held_quota = held_usage = None
reset_5h = int(time.time()) + 3600
reset_week = int(time.time()) + 604800


def reply(identifier, result):
    print(json.dumps({"id": identifier, "result": result}), flush=True)


def quota(five=12, weekly=46):
    return {"rateLimits": {"primary": {"usedPercent": five, "windowDurationMins": 300, "resetsAt": reset_5h},
                           "secondary": {"usedPercent": weekly, "windowDurationMins": 10080, "resetsAt": reset_week}}}


def account(email="catalog-fixture@example.invalid"):
    return {"account": {"email": email, "planType": "test"}}


for line in sys.stdin:
    request = json.loads(line)
    method = request["method"]
    identifier = request.get("id")
    result = {}
    if method == "initialize":
        pass
    elif method == "initialized":
        continue
    elif method == "account/read":
        account_reads += 1
        if phase == "account" and account_reads == 2:
            held_account = identifier
            continue
        if phase == "account" and account_reads >= 3:
            reply(identifier, account("new-catalog-fixture@example.invalid"))
            if held_account is not None:
                reply(held_account, account())  # Older account/read arrives after the new identity.
                held_account = None
            if held_quota is not None:
                reply(held_quota, quota(99, 99))  # Delayed response must not enter history.
                held_quota = None
            if held_usage is not None:
                reply(held_usage, {"dailyUsageBuckets": [{"startDate": "fixture-late-old", "tokens": 999}]})
                held_usage = None
            continue
        result = account()
    elif method == "account/rateLimits/read":
        quota_reads += 1
        if phase == "account" and quota_reads == 2:
            held_quota = identifier
            continue
        if phase == "catalog" and quota_reads > 2:
            continue  # A slow runner's 15s poll must not make fixture counts flaky.
        result = quota(33, 66) if phase == "account" and quota_reads >= 3 else quota()
        reply(identifier, result)  # Exact replay, followed by the normal response below.
    elif method == "account/usage/read":
        usage_reads += 1
        if phase == "catalog" and usage_reads == 1:
            held_usage = identifier
            continue  # Released by the probe's next catalog request, not a scheduler race.
        if phase == "account" and usage_reads == 2:
            held_usage = identifier
            continue
        if phase == "catalog" and usage_reads >= 2:
            continue  # Force the production 10s partial-refresh timeout.
        if usage_reads == 1 or phase == "account":
            time.sleep(0.8)
        result = {"dailyUsageBuckets": []}
    elif method == "model/list":
        if phase == "account":
            if catalog_reads == 0:
                for _ in range(2):
                    print(json.dumps({"method": "account/updated", "params": {}}), flush=True)
            catalog_reads += 1
            print(json.dumps({"id": identifier, "error": {"code": -32601, "message": "fixture account catalog failure"}}), flush=True)
            continue
        cursor = request.get("params", {}).get("cursor")
        if cursor is None:
            catalog_reads += 1
        if catalog_reads > 1:
            if held_usage is not None:
                time.sleep(0.8)
                reply(held_usage, {"dailyUsageBuckets": []})
                held_usage = None
            print(json.dumps({"id": identifier, "error": {"code": -32601, "message": "fixture catalog failure"}}), flush=True)
            continue
        name = "fixture-advisor" if cursor is None else "fixture-efficient"
        result = {"data": [{"model": name, "displayName": name, "description": "Deterministic gate fixture",
                            "hidden": False, "defaultReasoningEffort": "medium",
                            "supportedReasoningEfforts": [{"reasoningEffort": "medium"}, {"reasoningEffort": "high"}],
                            "isDefault": cursor is None}], "nextCursor": "fixture-page-two" if cursor is None else None}
    else:
        raise RuntimeError("Probe attempted an unapproved protocol method")
    reply(identifier, result)
