# TrustAnchorResolutionFailure

## Failing step
Step 2: Trust anchor selection

## What this proves
Trust is a policy input. If the verifier’s trust anchor set is wrong, a valid certificate chain can still be rejected deterministically.

## Symptom
**Client-side:** handshake fails; request does not reach HTTP 200. curl reports “unknown CA” / “unable to get local issuer certificate” / “unable to verify the first certificate” (wording varies).  
**Verifier-side (nginx):** may show handshake aborted / TLS alert (optional).  
**Application-side (flask):** no request is received (because connection fails before HTTP).

## Root Cause
Failing step: **Step 2 (Trust anchor selection)**

Why this fails deterministically:
- The client’s verifier must select trust anchors from `--cacert`.
- This run deliberately uses the wrong CA bundle as the trust anchor input.
- With the wrong trust anchor set, the server’s chain cannot be validated, so verification rejects.

## Hidden Inputs
- **Which trust store is actually used:** the CAfile passed to curl is the trust policy input.
- **Trust store ownership:** who controls the trust store controls who is trusted.
- **Evidence window:** logs must be collected from the same run (restarts/previous runs mislead).

## Evidence

Evidence bundle is created by running the failure run:
failure-archetypes/TrustAnchorResolutionFailure/run.sh

This proves Step 2 failed:
- client/handshake.txt  
  Shows curl’s verification failure consistent with unknown CA / wrong trust anchor.
- server/nginx_T.txt  
  Proves server-side policy is unchanged (this is not a server trust-store problem).
- certs/id_root.txt + certs/id_intermediate.txt + certs/id_server.txt  
  Stable identifiers showing which issuers/subjects are in play.

## Minimal Fix
Minimal safe fix:
- Use the correct trust anchor bundle on the verifier that is performing the rejection (here: client-side CA bundle passed to curl).

Do not:
- Do not “fix” by disabling verification (`-k`, `--insecure`).
- Do not rotate leaf certificates when the anchor set is wrong.

## Replay requirements
- Client must use an incorrect trust anchor bundle (`--cacert` wrong).
- Server cert chain remains valid and unchanged.
- Client cert must still be presented correctly so Step 6B does not fail first.