# PrivateKeyProofFailure

## Failing step
Step 7: Proof of possession (PrivateKeyProof)

## What this proves
A certificate chain can be valid and trusted, but mTLS still fails deterministically if the peer cannot prove possession of the private key for the presented certificate.

## Symptom
**Client-side:** handshake fails; request does not reach HTTP 200.  
**Verifier-side (nginx):** verifier emits an OpenSSL signature verification error (commonly “bad signature” / “certificate verify failed” depending on log format).  
**Application-side (flask):** no request is received (because nginx rejects during handshake).

## Root Cause
Failing step: **Step 7 (Proof of possession)**

Why this fails deterministically:
- The client presents a valid leaf certificate and chain.
- The client uses a private key that does not match the certificate’s public key.
- The verifier checks PrivateKeyProof and rejects because the signature cannot be validated.

## Hidden Inputs
- **Cert vs key pairing:** a “valid cert” is meaningless without the matching private key at handshake time.
- **Failure is not about trust anchors:** changing CA bundles doesn’t fix key mismatch.
- **Evidence window:** logs must be collected from the same run.

## Evidence
Evidence bundle is created by running:
failure-archetypes/PrivateKeyProofFailure/run.sh

This proves Step 7 failed:
- client/handshake.txt  
  Shows handshake did not reach HTTP 200.
- server/error.log or server/nginx_logs_since_run.txt  
  Contains signature / PrivateKeyProof failure.
- failure-archetypes/PrivateKeyProofFailure/generated/wrong_client.key  
  Proves the key used is not the lab client key.

## Minimal Fix
- Use the correct private key for the presented client certificate.

Do not:
- Do not modify trust anchors.
- Do not weaken verification policy.

## Replay requirements
- nginx must enforce client verification.
- the run must present a valid client certificate chain with a mismatched private key.
- evidence must be collected from the same run.