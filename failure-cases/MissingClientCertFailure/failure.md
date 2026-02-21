# MissingClientCertFailure

## Failing step
Step 6B: Client cert presence

## What this proves
When the verifier requires a client certificate, omitting it causes a deterministic reject at Step 6B, before any application logic runs.

## Symptom
**Client-side:** request does not reach HTTP 200. The server rejects the handshake because no client certificate was presented.  
**Verifier-side (nginx):** nginx emits an error consistent with “client certificate required but not provided.”  
**Application-side (flask):** no request is received (because nginx rejects during handshake).

## Root Cause
Failing step: **Step 6B (Client cert presence)**

Why this fails deterministically:
- The verifier policy requires a client certificate (`ssl_verify_client on`).
- The client command does not present one (no `--cert/--key`).
- The verifier rejects during handshake, so the request is never proxied to the application.

## Hidden Inputs
- **Verifier policy mode:** `ssl_verify_client on` (required). If `optional`/`off`, this specific failure would not occur.
- **Where the policy lives:** nginx config is the decision owner for “client cert required.”
- **Evidence window:** logs must be collected from the same run (container restarts, log rotation, and previous runs will mislead).

## Evidence

Evidence bundle is created by:
./scripts/collect-evidence.sh MissingClientCertFailure

This proves Step 6B failed:
- curl_verbose.txt
  Shows the request was sent without `--cert/--key` (client did not present a certificate).
- nginx_logs.txt
  Contains the reject reason for missing client certificate.
  This is the verifier output proving Step 6B failed.
- nginx_T.txt
  Proves the policy input at time of failure: client cert is required (`ssl_verify_client on`).
- flask_logs.txt
  Shows the app did not receive the request (expected for a handshake reject).

## Minimal Fix
- Present a client certificate and key in the client command.

Do not:
- Do not weaken nginx by changing `ssl_verify_client` from on to `optional` or `off` to make it pass.
- Do not change trust anchors or certificate authorities.

## Replay requirements
- nginx must require a client certificate (`ssl_verify_client on`).
- the failure run must omit `--cert/--key` from the client command.
- evidence must be collected from the same run as the failure execution.