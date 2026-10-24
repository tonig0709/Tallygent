#!/usr/bin/env python3
import json
import sys

catalog_reads = 0
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
        result = {"account": {"email": "catalog-fixture@example.invalid", "planType": "test"}}
    elif method == "account/rateLimits/read":
        result = {"rateLimits": {"primary": {"usedPercent": 12, "windowDurationMins": 300},
                                 "secondary": {"usedPercent": 46, "windowDurationMins": 10080}}}
    elif method == "account/usage/read":
        result = {"dailyUsageBuckets": []}
    elif method == "model/list":
        cursor = request.get("params", {}).get("cursor")
        if cursor is None:
            catalog_reads += 1
        if catalog_reads > 1:
            print(json.dumps({"id": identifier, "error": {"code": -32601, "message": "fixture catalog failure"}}), flush=True)
            continue
        name = "fixture-advisor" if cursor is None else "fixture-efficient"
        result = {"data": [{"model": name, "displayName": name, "description": "Deterministic gate fixture",
                            "hidden": False, "defaultReasoningEffort": "medium",
                            "supportedReasoningEfforts": [{"reasoningEffort": "medium"}, {"reasoningEffort": "high"}],
                            "isDefault": cursor is None}], "nextCursor": "fixture-page-two" if cursor is None else None}
    else:
        raise RuntimeError("Probe attempted an unapproved protocol method")
    print(json.dumps({"id": identifier, "result": result}), flush=True)
