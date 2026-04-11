# IncompleteChainFailure

## Failing step
Step 3: Path building

## What this proves
When the peer does not present required intermediates, the verifier cannot build a chain to a trusted root and deterministically rejects at Step 3.

## Symptom
**Client-side:** handshake fails; request does not reach HTTP 200. The verifier rejects because it cannot build a chain to a trusted anchor.  
**Verifier-side (nginx):** nginx emits an error consistent with “unable to get local issuer certificate” / “unable to verify the first certificate.”  
**Application-side (flask):** no request is received (because nginx rejects during handshake).

## Root Cause
Failing step: **Step 3 (Path building)**

Why this fails deterministically:
- The verifier trusts the root CA (`ssl_client_certificate` contains the root).
- The client presents only the leaf certificate.
- The intermediate required to link leaf to root is not presented.
- The verifier does not invent intermediates, so path building fails and the handshake is rejected.

## Hidden Inputs
- **What the peer actually presented:** path building depends on the presented chain, not what “should exist.”
- **Verifier depth:** `ssl_verify_depth` can change whether deeper chains are allowed, but it cannot replace a missing intermediate.
- **Evidence window:** logs must be collected from the same run (container restarts, log rotation, and previous runs will mislead).

## Evidence

Evidence bundle is created by:
./scripts/collect-evidence.sh IncompleteChainFailure

This proves Step 3 failed:
- client/curl_verbose.txt  
  Shows the client presented a leaf certificate but did not include the intermediate in the chain.
- server/nginx_logs.txt  
  Contains the reject reason consistent with chain/path failure.
  This is the verifier output proving Step 3 failed.
- server/nginx_T.txt  
  Proves the policy input at time of failure: nginx trusts the root and requires verification.
- certs/verify_client_as_sslclient.txt  
  Fails when evaluated without the intermediate available to the verifier.
- server/flask_logs.txt  
  Shows the app did not receive the request (expected for a handshake reject).

## Minimal Fix
Minimal safe fix:
- Present the required intermediate with the client certificate (send leaf + intermediate).

Do not:
- Do not “fix” this by weakening verification or increasing trust blindly.
- Do not add random intermediates/roots to the trust store to make it pass.

## Replay requirements
- nginx must trust the root CA and enforce client verification.
- the failure run must present the client leaf without the intermediate.
- evidence must be collected from the same run as the failure execution.