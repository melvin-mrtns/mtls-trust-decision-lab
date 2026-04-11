# ValidityWindowFailure

## Failing step
Step 1: Time validity

## What this proves
Trust anchors do not override time validity.
A certificate can chain to a trusted root and still be rejected deterministically because it is expired.

## Symptom
**Client-side:** handshake fails; request does not reach HTTP 200. curl shows TLS failure / 400 from nginx depending on reporting.  
**Verifier-side (nginx):** nginx rejects with an expiry-related OpenSSL error (commonly “certificate has expired” / “not yet valid”).  
**Application-side (flask):** no request is received (because nginx rejects during handshake).

## Root Cause
Failing step: **Step 1 (Time validity)**

Why this fails deterministically:
- The client presents a certificate chain that is anchored to the trusted root (so trust anchor selection and path building can succeed).
- The presented leaf certificate’s NotAfter is in the past.
- The verifier checks validity time before (or as part of) acceptance, so it rejects immediately.

## Hidden Inputs
- **Current time:** time is a decision input. A cert can “work yesterday” and “fail today”.
- **Trusted issuer does not override expiry:** chain validity is separate from time validity.
- **Evidence window:** logs must be collected from the same run (previous runs mislead).

## Evidence
Evidence bundle is created by running:
failure-archetypes/ValidityWindowFailure/run.sh

This proves Step 1 failed:
- client/handshake.txt  
  Shows handshake did not reach HTTP 200.
- server/error.log or server/nginx_logs_since_run.txt  
  Contains the expiry reject reason.
- certs/client_dates.txt (generic probe) + generated cert dates  
  Confirms NotAfter is in the past for the presented client leaf.
- failure-archetypes/ValidityWindowFailure/generated/client_expired.crt  
  Shows explicit validity window (NotBefore/NotAfter).

## Minimal Fix
Minimal safe fix:
- Rotate the expired leaf certificate (re-issue client cert). Keep CA/trust anchors unchanged.

Do not:
- Do not “fix” by loosening verifier policy.
- Do not rotate root/intermediate to solve an expired leaf problem.

## Replay requirements
- nginx must enforce client verification.
- the failure run must present a client certificate that chains to the trusted root but is expired at the time of the run.
- evidence must be collected from the same run as the failure execution.