# UsageContraintFailure

## Failing step
Step 5: Role constraints (KU/EKU)

## What this proves
A certificate can be correctly issued and chain to a trusted root, yet still be rejected deterministically because its KU/EKU does not authorize the intended role (client auth).

## Symptom
**Client-side:** request does not reach HTTP 200. curl shows TLS failure / 400 from nginx depending on how nginx reports it.  
**Verifier-side (nginx):** nginx rejects the client certificate with an OpenSSL purpose error (commonly “unsuitable certificate purpose” / “unsupported certificate purpose”).  
**Application-side (flask):** no request is received (because nginx rejects during handshake).

## Root Cause
Failing step: **Step 5 (Role constraints / KU/EKU)**

Why this fails deterministically:
- The client presents a valid certificate chain (leaf signed by intermediate, chaining to the trusted root).
- The presented leaf certificate does **not** have `clientAuth` EKU (it has `serverAuth` instead).
- The verifier enforces the client-auth role constraint, so the certificate is rejected even though it is “trusted” cryptographically.

## Hidden Inputs
- **EKU/KU enforcement is verifier behavior:** a chain-valid cert can still be rejected if role constraints don’t match.
- **Verifier strictness:** behavior depends on verifier policy and OpenSSL verification mode.
- **Evidence window:** logs must be collected from the same run (previous runs mislead).

## Evidence
Evidence bundle is created by running:
failure-archetypes/UsageContraintFailure/run.sh

This proves Step 5 failed:
- client/handshake.txt  
  Shows handshake did not reach HTTP 200.
- server/error.log or server/nginx_logs_since_run.txt  
  Contains the reject reason consistent with certificate purpose / EKU failure.
- certs/verify_client_sslclient.txt (generic probe)  
  Will demonstrate “unsuitable certificate purpose” for the wrong-EKU cert if you add a targeted verify later.
- failure-archetypes/UsageContraintFailure/generated/client_wrong_eku.crt + wrong_eku_client.ext  
  Shows the EKU intentionally excludes `clientAuth`.

## Minimal Fix
Minimal safe fix:
- Issue a client leaf certificate that includes `Extended Key Usage = clientAuth` (and correct KU).

Do not:
- Do not disable verification or set `ssl_verify_client optional/off`.
- Do not “fix” by changing trust anchors when the problem is role constraints.

## Replay requirements
- nginx must enforce client verification.
- the failure run must present a client certificate that chains to the trusted root but lacks `clientAuth` EKU.
- evidence must be collected from the same run as the failure execution.