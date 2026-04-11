# SubjectIdentityMismatchFailure

## Failing step
Step 4: Identity binding (SAN)

## What this proves
Even when crypto and trust are fine, the verifier (client-side) rejects if the requested identity does not match the certificate SAN.
SAN is the identity binding. CN is irrelevant.

## Symptom
**Client-side:** handshake fails; request does not reach HTTP 200. curl reports a hostname/SAN mismatch (e.g., “no alternative certificate subject name matches target host name”).  
**Verifier-side (nginx):** may show handshake aborted / TLS alert (optional).  
**Application-side (flask):** no request is received (because the connection is rejected before HTTP).

## Root Cause
Failing step: **Step 4 (Identity binding / SAN)**

Why this fails deterministically:
- The server certificate SAN contains `localhost`.
- The client requests `https://127.0.0.1:8443/`.
- Identity binding compares the requested hostname to SAN.
- `127.0.0.1` ≠ `localhost`, so verification rejects.

## Hidden Inputs
- **Requested identity (hostname/SNI):** the URL hostname is an input to verification.
- **SAN is non-negotiable:** CN is not the identity binding in modern TLS validation.
- **Evidence window:** logs must be collected from the same run (restarts/previous runs mislead).

## Evidence

Evidence bundle is created by running the failure run:
failure-archetypes/SubjectIdentityMismatchFailure/run.sh

This proves Step 4 failed:
- client/handshake.txt  
  Shows curl verification failure consistent with SAN mismatch.
- certs/server_san_eku.txt  
  Shows the server cert SAN contains `localhost` (and not `127.0.0.1`).
- server/access.log + server/error.log (optional)  
  Shows no proxied request reached the app (expected).

## Minimal Fix
Minimal safe fix:
- Issue a server leaf certificate whose SAN matches the identity clients actually use (hostname/IP), or change clients to use the hostname that matches the SAN.

Do not:
- Do not disable verification (`-k`, `--insecure`) to “make it pass”.
- Do not change trust anchors to “fix” an identity binding error.

## Replay requirements
- Server cert SAN must not match the requested hostname.
- Client must request a hostname that is absent from SAN (e.g. `127.0.0.1` when SAN only contains `localhost`).
- Client cert must still be presented correctly so Step 6B does not fail first.