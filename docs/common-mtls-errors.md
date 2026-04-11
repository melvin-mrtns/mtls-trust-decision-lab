# Common mTLS Errors

Find your error string or symptom in the index below.
Each entry tells you what the failure actually is, why the common fix fails,
what the correct fix is, and how to verify it.

For automated analysis: `python3 scripts/analyze_run.py <OUT_DIR>`

---

## Index by Error String

| Error string | Archetype | Step | Section |
|---|---|---|---|
| `no required SSL certificate was sent` | `MissingClientCertificateCase` | 1 | [=>](#no-required-ssl-certificate-was-sent) |
| `client sent no required SSL certificate` | `MissingClientCertificateCase` | 1 | [=>](#no-required-ssl-certificate-was-sent) |
| `no peer certificate available` | `MissingServerCertificateCase` | 1 | [=>](#no-peer-certificate-available) |
| `self signed certificate` | `UntrustedSelfSignedLeafCase` | 2 | [=>](#self-signed-certificate) |
| `SSL certificate problem: self signed certificate` | `UntrustedSelfSignedLeafCase` | 2 | [=>](#self-signed-certificate) |
| `certificate verify failed` | `WrongTrustAnchorCase` or `MissingIntermediateCase` | 2 or 3 | [=>](#certificate-verify-failed) |
| `SSL certificate problem: unable to get local issuer certificate` | `WrongTrustAnchorCase` or `MissingIntermediateCase` | 2 or 3 | [=>](#certificate-verify-failed) |
| `SSL certificate problem: certificate verify failed` | `WrongTrustAnchorCase` or `MissingIntermediateCase` | 2 or 3 | [=>](#certificate-verify-failed) |
| `unable to get local issuer certificate` | `WrongTrustAnchorCase` or `MissingIntermediateCase` | 2 or 3 | [=>](#certificate-verify-failed) |
| `unable to verify the first certificate` | `MissingIntermediateCase` | 3 | [=>](#unable-to-verify-the-first-certificate) |
| `pubkey_sha256 mismatch` | `CertificateVerifySignatureMismatchCase` | 4 | [=>](#pubkey_sha256-mismatch) |
| `certificate has expired` | `ExpiredCertificateCase` | 5 | [=>](#certificate-has-expired) |
| `not yet valid` | `NotYetValidCertificateCase` | 5 | [=>](#not-yet-valid) |
| `unsuitable certificate purpose` | `ExtendedKeyUsageConstraintCase` | 6 | [=>](#unsuitable-certificate-purpose) |
| `unsupported certificate purpose` | `ExtendedKeyUsageConstraintCase` | 6 | [=>](#unsuitable-certificate-purpose) |
| `CA:TRUE` in client cert fields | `BasicConstraintsViolationCase` | 6 | [=>](#catrue-on-client-credential) |
| `no alternative certificate subject name matches` | `DnsSanMismatchCase` | 7 | [=>](#no-alternative-certificate-subject-name-matches) |
| `subject name does not match` | `DnsSanMismatchCase` | 7 | [=>](#no-alternative-certificate-subject-name-matches) |

---

## Index by Symptom

| What you observe | Most likely archetype | Section |
|---|---|---|
| Client connection refused, server log shows cert error | `MissingClientCertificateCase` | [=>](#no-required-ssl-certificate-was-sent) |
| curl fails, no cert-related error visible | `MissingServerCertificateCase` | [=>](#no-peer-certificate-available) |
| Works in browser, fails in curl | `MissingIntermediateCase` | [=>](#unable-to-verify-the-first-certificate) |
| Works in dev, fails in prod | `DnsSanMismatchCase` or `WrongTrustAnchorCase` | [=>](#no-alternative-certificate-subject-name-matches) |
| Works with old cert, fails after rotation | `CertificateVerifySignatureMismatchCase` | [=>](#pubkey_sha256-mismatch) |
| Fails for all services at once | `ExpiredCertificateCase` (intermediate) | [=>](#certificate-has-expired) |
| Fails exactly at a specific time | `ExpiredCertificateCase` (leaf) | [=>](#certificate-has-expired) |
| mTLS "enabled" but any client is accepted | Soft-fail, `ssl_verify_client optional` | [=>](#mtls-enabled-but-all-clients-are-accepted) |
| Handshake succeeds but CA cert used as client | `BasicConstraintsViolationCase` (soft-fail) | [=>](#catrue-on-client-credential) |
| Fails in Go / Java, works in curl | `ExtendedKeyUsageConstraintCase` | [=>](#unsuitable-certificate-purpose) |
| Connection succeeds, `--insecure` in command | Soft-fail, Step 7 bypass | [=>](#insecure-flag-in-production) |

---

## Entries

---

### `no required SSL certificate was sent`

**Also appears as**: `client sent no required SSL certificate`

**TDG step**: Step 1, Peer Certificate Presentation\
**Archetype**: `MissingPeerCredentialsFailure`\
**Case**: `MissingClientCertificateCase`\
**Direction**: server_verifies_client\
**Detected by**: server (`server/error.log`)

#### What this is

The server required a client certificate (`ssl_verify_client require` in nginx)
but the client did not present one. The handshake terminated at Step 1,
the earliest possible failure point. No identity evaluation occurred.

#### Why it happens in practice

The client was not configured to send a certificate.
In curl: `--cert` and `--key` flags are absent or point to wrong files.
In application code: the TLS client configuration does not specify a cert/key pair.
In service mesh migration: mTLS was enabled on the server before all clients
were updated to present credentials.

#### What people try that fails

**Rotating the server cert**: the server cert is irrelevant. The client
presented nothing. Changing the server cert has no effect.

**Checking the server trust store**: the trust store is not evaluated at
Step 1. The failure occurred before the chain was inspected.

**Disabling mTLS temporarily**: this resolves the symptom by removing the
control. The underlying problem (the client is not configured to present
identity) remains. When mTLS is re-enabled, the failure returns.

#### Correct fix

Configure the client to present a valid certificate and private key:

```bash
# curl:
curl --cert client.crt --key client.key https://server

# Verify the cert and key match before using them:
KEY_HASH=$(openssl pkey -pubout -in client.key 2>/dev/null | \
    openssl dgst -sha256 | awk '{print $2}')
CERT_HASH=$(openssl x509 -pubkey -noout -in client.crt 2>/dev/null | \
    openssl dgst -sha256 | awk '{print $2}')
[ "$KEY_HASH" = "$CERT_HASH" ] && echo "MATCH" || echo "MISMATCH: fix before proceeding"
```

#### Soft-fail variant

If `ssl_verify_client optional` is set, this error does not appear.
The client presents no cert, the server accepts the request, and the
client is treated as anonymous.\
See: [mTLS enabled but all clients are accepted](#mtls-enabled-but-all-clients-are-accepted)

---

### `no peer certificate available`

**TDG step**: Step 1, Peer Certificate Presentation\
**Archetype**: `MissingPeerCredentialsFailure`\
**Case**: `MissingServerCertificateCase`\
**Direction**: client_verifies_server\
**Detected by**: client (`client/handshake.txt`)

#### What this is

The server did not present any certificate during the TLS handshake.
The client received no certificate material to evaluate.
This is a server configuration failure, not a cert validity failure.

#### Why it happens in practice

The nginx `ssl_certificate` or `ssl_certificate_key` directive is missing,
points to a non-existent file, or contains a path error. nginx may have
failed to start, or is running a configuration that does not have TLS
enabled for the virtual host being contacted. In development environments:
the service was started without the TLS configuration block active.

#### What people try that fails

**Checking the client cert**: the client cert is not involved. The server
presented nothing. Client-side cert issues are irrelevant until the server
presents a cert for the client to evaluate.

**Adding `--cacert`**: the CA bundle is not consulted when there is no
server cert to anchor. The failure is upstream of trust anchor resolution.

#### Correct fix

Fix the server TLS configuration so it presents a certificate:

```bash
# Verify nginx config is syntactically correct:
nginx -t

# Check that the cert file exists and is readable:
openssl x509 -noout -subject -in /path/to/server.crt

# Check that the key matches the cert:
openssl x509 -pubkey -noout -in /path/to/server.crt | openssl dgst -sha256
openssl pkey -pubout -in /path/to/server.key | openssl dgst -sha256
# These must match

# Reload after fixing:
nginx -s reload

# Confirm the server is now presenting a cert:
openssl s_client -connect server:443 -showcerts </dev/null 2>/dev/null | \
    grep -E "subject|issuer"
```

---

### `self signed certificate`

**Also appears as**: `SSL certificate problem: self signed certificate`

**TDG step**: Step 2, Trust Anchor Resolution\
**Archetype**: `TrustAnchorResolutionFailure`\
**Case**: `UntrustedSelfSignedLeafCase`\
**Direction**: client_verifies_server\
**Detected by**: client (`client/handshake.txt`)

#### What this is

The server presented a certificate signed by itself. The issuer and subject
are the same entity. The client's trust store does not contain this certificate
as an explicitly trusted anchor. The chain terminates at the leaf with no
path to any trusted CA.

#### Why it happens in practice

A self-signed cert was generated for development or testing and was not
replaced before the system was accessed from a client that enforces trust
verification. Common in: local development environments, internal tooling,
expired CA hierarchy replaced by a quick self-signed cert under pressure.

#### What people try that fails

**Adding `--insecure`**: this bypasses the failure but removes all server
identity verification. Every subsequent connection is made to an unverified
peer. This is a soft-fail bypass, not a fix.\
See: [--insecure flag in production](#insecure-flag-in-production)

**Adding the self-signed cert to the system trust store**: this resolves
the immediate failure but treats a self-signed cert as a trusted CA across
the entire system. Any cert signed by this key would then be trusted.
Appropriate only if the self-signed cert is intentionally a private CA root.

#### Correct fix

Option A (correct for production): replace the self-signed cert with one
issued by a CA the client already trusts.

Option B (correct for private CA): add the self-signed cert to the client's
trust store explicitly and treat it as a CA root:

```bash
# Verify the cert is self-signed:
openssl x509 -noout -subject -issuer -in server.crt
# Self-signed: subject == issuer

# Option B: explicitly trust as a CA:
curl --cacert self-signed-cert.crt https://server
```

---

### `certificate verify failed`

**Also appears as**:
- `SSL certificate problem: unable to get local issuer certificate`
- `SSL certificate problem: certificate verify failed`
- `unable to get local issuer certificate`

**TDG step**: Step 2 OR Step 3 (disambiguation required)\
**Archetype**: `WrongTrustAnchorCase` (Step 2) or `MissingIntermediateCase` (Step 3)\
**Direction**: client_verifies_server or server_verifies_client\
**Detected by**: client (`client/handshake.txt`) or server (`server/error.log`)

#### What this is

This error string is ambiguous. It appears at two different steps for two
different root causes. The cert count in the presented chain is the only
deterministic way to split them.

**If the presented chain contains 1 certificate (leaf only)**:
The server or client presented only the leaf cert without intermediates.
The verifier cannot build a path from the leaf to any trust anchor because
the intermediates required to bridge them are absent from the chain.
This is a Step 3 failure (path building).\
Go to: [unable to verify the first certificate](#unable-to-verify-the-first-certificate)

**If the presented chain contains more than 1 certificate**:
The chain was presented with intermediates but the verifier still cannot
anchor it. The chain does not terminate at any cert in the trust store.
This is a Step 2 failure (trust anchor resolution).
Continue reading this entry.

#### Disambiguate first

```bash
# Count certs in the server chain:
grep -c "BEGIN CERTIFICATE" <OUT_DIR>/inputs/server/fullchain.crt

# Count certs in the client chain:
grep -c "BEGIN CERTIFICATE" <OUT_DIR>/inputs/client/cert.crt

# count == 1 => Step 3 (missing intermediate)
# count > 1  => Step 2 (wrong trust anchor)
```

#### Why it happens in practice (Step 2)

The client or server is using the wrong CA bundle. The cert was issued by
a private CA but the verifier is using the system trust store or a different
CA bundle. Common causes:
- `--cacert` points to the wrong file
- The CA bundle was updated but the running service was not reloaded
- Multiple CAs exist in the environment and the wrong one was passed
- The CA was rotated and the old bundle is still in use

#### What people try that fails

**Re-issuing the cert**: the cert chain and the issuing CA are not the
problem. The problem is the verifier does not have the correct CA in its
trust store. Re-issuing from the same CA produces the same failure.

**Adding `--insecure`**: bypasses verification entirely. This removes the
failure without resolving it and introduces a verification bypass on every
subsequent connection.

#### Correct fix

```bash
# Identify what CA issued the cert:
openssl x509 -noout -issuer -in server.crt

# Confirm the CA bundle contains that issuer:
openssl verify -CAfile ca-bundle.crt server.crt
# Expected: server.crt: OK

# Use the correct bundle:
curl --cacert correct-ca.crt https://server

# For server_verifies_client, confirm nginx is using the correct CA:
grep "ssl_client_certificate" <OUT_DIR>/server/nginx_T.txt
openssl x509 -noout -subject -in /path/to/client-ca.crt
# Subject must match the issuer of the client cert being presented
```

---

### `unable to verify the first certificate`

**TDG step**: Step 3, Path Building\
**Archetype**: `IncompleteChainFailure`\
**Case**: `MissingIntermediateCase`\
**Direction**: client_verifies_server or server_verifies_client\
**Detected by**: client (`client/handshake.txt`) or server (`server/error.log`)

#### What this is

The verifier received only the leaf certificate with no intermediates.
It cannot construct a path from the leaf to any trust anchor because
the intermediates that bridge them were not included in the presented chain.
The trust anchor exists in the trust store. The path to it is broken.

This is the single most common mTLS failure in practice. It is also the
failure most commonly misdiagnosed as a trust store problem.

#### Why it happens in practice

The server's `ssl_certificate` directive points to a leaf-only PEM file
instead of a fullchain PEM file. The intermediate cert exists on disk
but was never included in the TLS configuration. In automated cert
pipelines: the pipeline issues leaf-only files by default and the
fullchain assembly step was skipped or misconfigured.

**The browser exception**: browsers cache intermediates from prior
successful handshakes and will often fetch missing intermediates via
the AIA extension in the cert. A browser may succeed where curl fails
because the browser compensated for the missing intermediate silently.
This creates a false signal that the chain is correct. Always test with
curl or `openssl s_client`, not a browser.

#### What people try that fails

**Updating the CA bundle**: the CA bundle contains the trust anchor.
The problem is the path from the leaf to the anchor is broken. The anchor
is already there. The intermediate is missing from the presented chain.

**Re-issuing the leaf cert**: the leaf cert is not the problem. The
intermediate exists and is valid. The problem is it is not being presented
during the handshake. Re-issuing the leaf from the same intermediate
produces the same failure.

**Trusting the leaf cert directly**: adding the leaf to the trust store
converts a path-building problem into a trust anchor resolution. This
works technically but treats a leaf cert as a CA root, which is
structurally incorrect and creates a cert-specific trust exception that
must be manually managed.

#### Correct fix

```bash
# Confirm it is a leaf-only file:
grep -c "BEGIN CERTIFICATE" /path/to/server.crt
# Expected: 1

# Identify the intermediate:
openssl x509 -noout -issuer -in /path/to/server.crt
# Issuer field tells you which CA signed this cert

# Build the fullchain:
cat /path/to/server.crt /path/to/intermediate.crt > /path/to/fullchain.crt

# Verify the chain is correct and complete:
openssl verify -CAfile /path/to/root-ca.crt \
    -untrusted /path/to/intermediate.crt \
    /path/to/server.crt
# Expected: server.crt: OK

# Update nginx to use the fullchain:
# ssl_certificate /path/to/fullchain.crt;

# Reload and confirm the full chain is now served:
nginx -s reload
openssl s_client -connect server:443 -showcerts </dev/null 2>/dev/null | \
    grep -c "BEGIN CERTIFICATE"
# Expected: 2 or more (leaf + at least one intermediate)
```

---

### `pubkey_sha256 mismatch`

**TDG step**: Step 4, Proof of Possession\
**Archetype**: `PrivateKeyProofFailure`\
**Case**: `CertificateVerifySignatureMismatchCase`\
**Direction**: server_verifies_client\
**Detected by**: analyzer (deterministic hash comparison)

#### What this is

The private key file and the certificate file do not correspond to the
same key pair. The public key embedded in the cert does not match the
public key derived from the private key file. The CertificateVerify
message produced during the handshake will fail verification because
the signature is produced by a key that does not match the cert's public key.

This is the only failure in this lab detectable before a handshake occurs.
It is detected by comparing SHA-256 hashes of the public keys extracted
from both files.

#### Why it happens in practice

A cert rotation event updated one file but not the other. The new cert
was deployed but the old private key was left in place. Or: a new private
key was generated but the cert was not re-issued against it. In automated
pipelines: the cert and key are written in separate steps and a partial
failure left them out of sync.

#### What people try that fails

**Rotating the cert again**: if the new cert is issued against the wrong
key, rotating it again issues another cert against the same wrong key.
The mismatch persists. The correct action is to identify which file is
wrong and replace it specifically.

**Rotating the key**: same problem in reverse. Rotating the key without
re-issuing the cert leaves the cert pointing to a key that no longer exists.

**Checking cert validity dates**: the cert may be perfectly valid. The
problem is key correspondence. A valid cert with the wrong key fails every
handshake completely.

#### Correct fix

```bash
# Confirm the mismatch:
KEY_HASH=$(openssl pkey -pubout -in client.key 2>/dev/null | \
    openssl dgst -sha256 | awk '{print $2}')
CERT_HASH=$(openssl x509 -pubkey -noout -in client.crt 2>/dev/null | \
    openssl dgst -sha256 | awk '{print $2}')

echo "Key hash:  $KEY_HASH"
echo "Cert hash: $CERT_HASH"
[ "$KEY_HASH" = "$CERT_HASH" ] && echo "MATCH" || echo "MISMATCH"

# Identify which file is wrong:

# Option A: the key is correct, cert is wrong:
#   Re-issue the cert against the existing key:
#   openssl req -new -key client.key -out client.csr
#   [sign csr with CA to produce new client.crt]

# Option B: the cert is correct, key is wrong:
#   Restore the original key used to generate the cert's CSR.
#   If the original key is lost, re-issue the cert against a new key (Option A).

# After correction, confirm match before reloading:
# [run hash comparison again; must show MATCH]

# Reload service:
nginx -s reload
```

**What not to do**: do not rotate either file without first confirming via
hash comparison which file is wrong. Rotating the wrong file deepens the
mismatch and extends the outage.

---

### `certificate has expired`

**TDG step**: Step 5, Time Validity\
**Archetype**: `ValidityWindowFailure`\
**Case**: `ExpiredCertificateCase`\
**Direction**: client_verifies_server or server_verifies_client\
**Detected by**: client (`client/handshake.txt`) or server (`server/error.log`)

#### What this is

The verifier's current time is past the NotAfter field of a certificate
in the chain. The validity window has closed. The cert is no longer
acceptable to any verifier that enforces time validity.

This failure is time-correlated: it begins at the exact moment of expiry
and affects 100% of new connections immediately. Long-lived connections
established before expiry continue to function until they reconnect.

#### Why it happens in practice

**Leaf cert expiry**: the most common case. The cert was not rotated before
its NotAfter date. Causes: no automated rotation, rotation automation
failed silently, monitoring alert was ignored or suppressed, renewal lead
time was insufficient for the deployment pipeline.

**Intermediate cert expiry**: less common but far more severe. Every leaf
cert issued under the intermediate fails simultaneously. Intermediate
NotAfter values are measured in years and are almost never in the rotation
runbook. When an intermediate expires it is usually a complete surprise.

#### The partial failure pattern

When a leaf cert expires, long-lived connections established before expiry
continue to function while new connections fail immediately. The failure
pattern appears load-dependent and intermittent; some clients succeed and
some fail. Engineers misdiagnose this as a routing or load balancing
problem. It is not. It is fully deterministic: connections that predate
the expiry succeed; connections that postdate it fail.

```bash
# Confirm expiry and determine severity:
openssl x509 -noout -dates -in cert.crt
# notAfter shows exact expiry time

# Check whether the failure is leaf or intermediate:
openssl crl2pkcs7 -nocrl -certfile fullchain.crt | \
    openssl pkcs7 -print_certs -noout 2>/dev/null
# Inspect each cert's dates individually

# Estimate blast radius:
# Leaf expiry:         affects this service only
# Intermediate expiry: affects every service using a cert from this intermediate
```

#### What people try that fails

**Restarting the service**: the cert is expired. Restarting serves the
same expired cert. The failure immediately recurs.

**Checking the trust store**: the trust store is not the problem. The
problem is time. A valid CA bundle does not prevent an expired leaf from
failing this step.

**Extending the NotAfter field of the existing cert**: X.509 validity
fields are immutable after issuance. Any modification to the cert after
signing invalidates the signature. The only fix is re-issuance.

#### Correct fix

```bash
# Re-issue the expired cert:

# 1. Generate new CSR (reuse existing key if it is still valid):
openssl req -new -key existing.key -out new.csr \
    -subj "/CN=service-name"

# 2. Sign with CA (replace with your CA tooling):
openssl x509 -req -in new.csr \
    -CA intermediate.crt -CAkey intermediate.key \
    -CAcreateserial \
    -out new.crt \
    -days 365 \
    -sha256

# 3. Build fullchain:
cat new.crt intermediate.crt > new-fullchain.crt

# 4. Deploy and reload:
nginx -s reload

# 5. Confirm new cert is being served with correct dates:
openssl s_client -connect server:443 </dev/null 2>/dev/null | \
    openssl x509 -noout -dates
```

**After recovery: address the cause.**\
Cert expiry is a process failure, not a cert failure. After the immediate
outage is resolved, identify why the rotation did not occur:
- Was there an alert? Did it fire? Was it acknowledged?
- Was there automated rotation? Did it fail silently?
- What is the renewal lead time relative to pipeline latency?

If renewal lead time is shorter than pipeline latency plus deployment
window, expiry during rotation is structurally guaranteed to recur.

---

### `not yet valid`

**Also appears as**: `certificate is not yet valid`

**TDG step**: Step 5, Time Validity\
**Archetype**: `ValidityWindowFailure`\
**Case**: `NotYetValidCertificateCase`\
**Direction**: client_verifies_server or server_verifies_client\
**Detected by**: client (`client/handshake.txt`) or server (`server/error.log`)

#### What this is

The verifier's current time is before the NotBefore field of a certificate
in the chain. The validity window has not yet opened. The cert exists and
is structurally valid but is not yet acceptable at verification time.

#### Why it happens in practice

**Clock skew between the CA and the verifier**: the most common cause.
The CA's system clock is ahead of the verifier's clock. The cert was issued
with a NotBefore set to the CA's current time, which is in the future
relative to the verifier. The cert is valid in the CA's time frame and
invalid in the verifier's time frame simultaneously.

This failure is systematic: every cert issued by that CA until the clocks
converge will fail on any verifier whose clock is behind the CA's clock.

**Deployment before cert becomes valid**: a cert was issued with a future
NotBefore (intentional or accidental) and deployed immediately. The service
fails until the verifier's clock passes the NotBefore time.

```bash
# Confirm the NotBefore and compare to current time:
openssl x509 -noout -dates -in cert.crt
# notBefore shows when the cert becomes valid

# Check server clock:
date -u

# If server clock < notBefore: clock skew or future-dated cert
```

#### What people try that fails

**Re-issuing the cert**: if the CA clock is ahead of the verifier clock,
re-issuing produces a new cert with the same problem. The new cert's
NotBefore is also in the future relative to the verifier.
Fix the clock, not the cert.

**Waiting for the cert to become valid**: resolves the symptom temporarily
but does not address the root cause. The next cert issued by the same CA
has the same problem.

#### Correct fix

```bash
# Identify the clock skew:

# On the CA host:
date -u

# On the verifier host:
date -u

# Synchronize via NTP:
timedatectl status | grep "synchronized"
# or:
chronyc tracking | grep "System time"

# After clock synchronization:
# If the existing cert's NotBefore is now in the past, it becomes valid
# without re-issuance. Verify:
openssl x509 -noout -dates -in cert.crt
date -u
# notBefore must be <= current UTC time
```

**What not to change**: do not re-issue without fixing the clock, otherwise
the new cert will have the same problem. Cert fields are immutable after
signing; the NotBefore cannot be shifted on an existing cert.

---

### `unsuitable certificate purpose`

**Also appears as**: `unsupported certificate purpose`

**TDG step**: Step 6, Usage Constraints\
**Archetype**: `UsageConstraintFailure`\
**Case**: `ExtendedKeyUsageConstraintCase`\
**Direction**: server_verifies_client\
**Detected by**: server (`server/error.log`)

#### What this is

The client cert's Extended Key Usage (EKU) extension does not include
`clientAuth` required for TLS client authentication. The cert may be
valid, fully trusted, and unexpired, but it was not issued for the purpose
of client authentication and the verifier enforces this.

#### Why it happens in practice

The client cert was issued for a different purpose (`serverAuth`,
`emailProtection`, `codeSigning`) and was reused for mTLS client
authentication without re-issuance. In some CA configurations the default
template does not include `clientAuth` and engineers do not notice until
the cert is rejected under a strict verifier.

**The verifier strictness problem**: older OpenSSL versions and some lenient
verifiers do not enforce EKU strictly. A cert without `clientAuth` that
works against an older OpenSSL version fails against a newer OpenSSL build,
Go 1.15+, or any Java verifier. The cert has not changed. The enforcement
has. This failure appears during library upgrades, runtime updates, or
migrations to a different TLS stack.

```bash
# Inspect the cert's EKU:
openssl x509 -noout -text -in client.crt | grep -A3 "Extended Key Usage"

# clientAuth must appear:
# Extended Key Usage:
#     TLS Web Client Authentication
# If absent or shows only serverAuth/other: cert needs re-issuance
```

#### What people try that fails

**Checking cert expiry**: the cert is not expired. The problem is purpose
mismatch. Expiry and purpose are independent fields.

**Checking the trust store**: the trust anchor is not the problem. The
cert is trusted. Its declared purpose is wrong for this context.

**Downgrading the TLS library**: this restores lenient enforcement and
converts a hard failure back to a soft-fail. The cert is still wrong.
The next upgrade or migration produces the same failure.

#### Correct fix

```bash
# Re-issue the client cert with clientAuth EKU:
cat >> /tmp/client-ext.cnf << EOF
extendedKeyUsage = clientAuth
keyUsage = digitalSignature
EOF

openssl x509 -req -in client.csr \
    -CA intermediate.crt -CAkey intermediate.key \
    -CAcreateserial \
    -out new-client.crt \
    -days 365 -sha256 \
    -extfile /tmp/client-ext.cnf

# Verify the new cert has correct EKU:
openssl x509 -noout -text -in new-client.crt | \
    grep -A3 "Extended Key Usage"
# Must show: TLS Web Client Authentication
```

---

### `CA:TRUE` on client credential

**TDG step**: Step 6, Usage Constraints\
**Archetype**: `UsageConstraintFailure`\
**Case**: `BasicConstraintsViolationCase`\
**Direction**: server_verifies_client\
**Detected by**: analyzer (deterministic field inspection of `certs/fields/client_cert.txt`)

#### What this is

The client certificate has `Basic Constraints: CA:TRUE`, declaring itself
to be a CA certificate. End-entity credentials must have `CA:FALSE` or no
BasicConstraints extension. A CA cert used as a client credential is a
structural violation: the cert was not issued for this purpose and any
verifier that enforces BasicConstraints will reject it.

#### Why it happens in practice

The CA's intermediate or root cert was mistakenly used as a client
credential. In some internal PKI setups, engineers test with the CA cert
before issuing a proper leaf cert and the CA cert makes it into a
configuration file. In automated pipelines: the cert type was not
validated at issuance time.

#### The soft-fail danger

This is the canonical soft-fail in this lab. Some verifiers, particularly
older OpenSSL builds, do not strictly enforce BasicConstraints. A CA:TRUE
client cert passes Steps 1 through 5 and is accepted. The handshake
succeeds. The connection works. The logs are clean.

The failure is latent. It activates on:
- OpenSSL version upgrade that adds strict BasicConstraints enforcement
- Migration to a Go or Java verifier that enforces by default
- Deployment to a different environment with different library versions

There is no operational signal before the transition. The system works
and then fails completely.

```bash
# Detect the condition:
openssl x509 -noout -text -in client.crt | grep -A2 "Basic Constraints"

# CA:TRUE confirms the violation:
# Basic Constraints: critical
#     CA:TRUE

# CA:FALSE or absent is correct for an end-entity credential
```

#### Correct fix

```bash
# Re-issue as an end-entity cert with CA:FALSE:
cat >> /tmp/leaf-ext.cnf << EOF
basicConstraints = CA:FALSE
extendedKeyUsage = clientAuth
keyUsage = digitalSignature
EOF

openssl x509 -req -in client.csr \
    -CA intermediate.crt -CAkey intermediate.key \
    -CAcreateserial \
    -out new-client.crt \
    -days 365 -sha256 \
    -extfile /tmp/leaf-ext.cnf

# Verify:
openssl x509 -noout -text -in new-client.crt | grep -A2 "Basic Constraints"
# Must show: CA:FALSE
```

**This finding is high severity regardless of current verifier behavior.**
The condition will produce a hard failure on the next library upgrade.
The question is not whether it will fail, it is when.

---

### `no alternative certificate subject name matches`

**Also appears as**:
- `subject name does not match`
- `SSL certificate problem: no alternative certificate subject name matches`

**TDG step**: Step 7, Identity Binding\
**Archetype**: `SubjectIdentityMismatchFailure`\
**Case**: `DnsSanMismatchCase`\
**Direction**: client_verifies_server\
**Detected by**: client (`client/handshake.txt`)

#### What this is

The hostname the client used to connect does not match any entry in the
server certificate's Subject Alternative Name (SAN) extension. The cert
passed Steps 1 through 6: it is trusted, the chain is complete, the key
matches, it is not expired, and the purpose is correct. At the final step,
confirming the server is who the client expected, the identity does not match.

This is the most deterministic and most operationally common Step 7
failure. It is also the most preventable: the mismatch is fully visible
in the cert fields before any connection is attempted.

#### Why it happens in practice

**Environment promotion without re-issuance**: the most common trigger.
A cert issued for `api.dev.example.com` was used in production where the
hostname is `api.example.com`. The cert was correct in dev. It was never
re-issued for production.

**Wrong hostname in the connection**: the cert is correct but the client
is connecting to a different hostname than the cert covers.

**Wildcard scope mismatch**: the cert has `*.example.com` but the client
is connecting to `sub.api.example.com`, two labels below the wildcard.
Wildcards cover exactly one label.

```bash
# Identify the mismatch:

# What hostname did the client use?
grep "host=" <OUT_DIR>/metadata/verifier_inputs.parsed.txt

# What hostnames does the cert cover?
openssl x509 -noout -text \
    -in <OUT_DIR>/inputs/server/fullchain.crt | \
    grep -A1 "Subject Alternative Name"

# Compare manually: the connection hostname must appear in the SAN list
```

#### What people try that fails

**Adding `--insecure`**: disables hostname verification entirely. The
connection succeeds but the server identity is unverified. Any cert from
any trusted issuer can impersonate the server. This is a bypass, not a fix.\
See: [--insecure flag in production](#insecure-flag-in-production)

**Updating the trust store**: the trust anchor is not the problem. The
cert is trusted. Its declared identity does not match the connection target.

**Re-checking the cert chain**: the chain is valid. The problem is the
identity claim in the leaf cert, not the chain structure.

#### Correct fix

```bash
# Re-issue the cert with the correct hostname in the SAN:
cat >> /tmp/server-ext.cnf << EOF
subjectAltName = DNS:api.example.com, DNS:api.staging.example.com
basicConstraints = CA:FALSE
extendedKeyUsage = serverAuth
keyUsage = digitalSignature, keyEncipherment
EOF

openssl x509 -req -in server.csr \
    -CA intermediate.crt -CAkey intermediate.key \
    -CAcreateserial \
    -out new-server.crt \
    -days 365 -sha256 \
    -extfile /tmp/server-ext.cnf

# Verify SAN entries:
openssl x509 -noout -text -in new-server.crt | \
    grep -A2 "Subject Alternative Name"

# Build fullchain and reload:
cat new-server.crt intermediate.crt > new-fullchain.crt
nginx -s reload

# Confirm with a live connection:
curl --cacert ca.crt https://api.example.com
```

**For environment promotion**: issue environment-specific certs or issue
a cert that explicitly covers all environments. Do not share a single
cert across environments unless it explicitly covers all required hostnames.

---

## Soft-fail Conditions

Soft-fails are conditions where a failure was detected but the connection
was accepted. They do not appear as errors. They appear as success.
They are the most dangerous outcomes because they are invisible in standard
monitoring and survive all health checks.

---

### mTLS enabled but all clients are accepted

**Condition**: `ssl_verify_client optional` in nginx configuration\
**Status**: `ACCEPT` with `warning=true`\
**Archetype**: depends on which failure the accepted connection contains

#### What this is

nginx is configured to request a client certificate but not require one.
Connections without a client cert are accepted. Connections with an
invalid client cert (wrong trust anchor, missing intermediate, expired
cert, wrong EKU) may also be accepted.

The access log shows TLS. mTLS is "enabled." No client identity is being
enforced.

#### Why it happens in practice

`ssl_verify_client optional` is set during a migration period to allow
existing clients to continue working while new clients adopt client certs.
The migration completes but the directive is never changed to `require`.
The system runs in permanent soft-fail mode. No alert fires. No health
check fails. No one notices.

#### How to detect it

```bash
grep "ssl_verify_client" <OUT_DIR>/server/nginx_T.txt

# optional = client identity not enforced
# require  = client identity enforced
```

#### Correct fix

```bash
# After confirming all legitimate clients present valid certs:
# Change:
#   ssl_verify_client optional;
# To:
#   ssl_verify_client require;

nginx -t && nginx -s reload

# Verify a connection without a client cert is now rejected:
curl https://server
# Must produce: no required SSL certificate was sent
```

**Do not change to `require` without confirming all legitimate clients
are configured to present valid certs.** Audit client cert presence in
access logs before making the change.

---

### `--insecure` flag in production

**Condition**: `--insecure` or `-k` in any production request,
or `InsecureSkipVerify: true` in application TLS configuration
**Status**: `ACCEPT` with `warning=true`
**Steps bypassed**: Step 2 (trust anchor) and Step 7 (identity binding)

#### What this is

Server certificate verification is disabled. The TLS channel is encrypted
but the server identity is unverified. Any certificate that is structurally
valid passes, regardless of issuer, hostname, or trust anchor.

This is not a weaker form of verification. It is the absence of
verification. The encrypted channel provides confidentiality. It does not
provide authenticity. A man-in-the-middle with any certificate can
impersonate the target server.

#### Why it happens in practice

A Step 2 or Step 7 failure was encountered and `--insecure` was added
to make the connection work. The root cause was never fixed. The flag
was never removed. In application code: a developer added
`InsecureSkipVerify: true` during debugging, committed it, and it was
deployed.

#### How to detect it

```bash
# In the evidence bundle:
grep -E "\-\-insecure|\-k" <OUT_DIR>/metadata/verifier_cmd.sh

# In application code:
grep -r "InsecureSkipVerify" /path/to/app/   # Go
grep -r "verify=False" /path/to/app/         # Python
grep -r "ALLOW_ALL_HOSTNAME_VERIFIER" /path/to/app/  # Java
```

#### Correct fix

Remove the bypass and fix the underlying Step 2 or Step 7 failure that
caused it to be added. The bypass exists because the connection was
failing for a real reason. That reason is still present. Find it and fix it.

In regulated environments: any production connection made with certificate
verification disabled is a control failure. The finding is not "you used
--insecure." It is "your mTLS implementation does not provide identity
assurance for this connection."

---

## Verifier Behavior Reference

Some failures are verifier-specific: the same cert produces different
outcomes depending on which TLS implementation evaluates it.

| Behavior | OpenSSL < 1.1.0 | OpenSSL >= 1.1.0 | Go x509 | Java JSSE |
|---|---|---|---|---|
| `serverAuth` EKU enforcement | Lenient | Strict | Strict | Strict |
| `clientAuth` EKU enforcement | Lenient | Strict | Strict | Strict |
| `BasicConstraints CA:TRUE` on leaf | Often accepted | Strict | Strict | Strict |
| CN fallback when SAN absent | Yes | No | No | Version-dependent |
| AIA intermediate fetching | No | No | No | Yes (some versions) |
| Clock skew tolerance | None by default | None by default | None | Configurable |

**What this table means operationally**: a cert that passes in curl
(OpenSSL) may fail in a Go or Java service. A cert that works today may
fail after an OpenSSL upgrade. Constraint field audits must account for
the strictest verifier in the deployment, not the most lenient one.

---

## Known Gaps

These failure conditions are not yet covered by this document or the
analyzer. They are documented here so they are not confused with a
clean pass.

**Partial chain (some but not all intermediates presented)**
Produces `certificate verify failed` with cert count > 1. Currently
classified as `WrongTrustAnchorCase`. Requires manual issuer/subject
linkage inspection to diagnose correctly:
```bash
openssl crl2pkcs7 -nocrl -certfile fullchain.crt | \
    openssl pkcs7 -print_certs -noout
# Compare subject of each cert against issuer of the one below it
```

**EKU constraint propagation from intermediate**
An intermediate cert with a restricted EKU invalidates the leaf cert's
declared purpose regardless of what the leaf cert's own EKU says. Not
currently detectable automatically. Inspect manually:
```bash
openssl crl2pkcs7 -nocrl -certfile fullchain.crt | \
    openssl pkcs7 -print_certs -text 2>/dev/null | \
    grep -A3 "Extended Key Usage"
# Every intermediate in the chain must not restrict the leaf's required purpose
```

**IP address connection without iPAddress SAN**
Produces the same signal as `DnsSanMismatchCase` but requires a different
fix. Check whether the connection target is an IP address before
concluding the cert needs re-issuance. The fix may be to use the hostname
instead of the IP:
```bash
# Check if the connection target is an IP:
grep "host=" <OUT_DIR>/metadata/verifier_inputs.parsed.txt

# Check whether the cert has an iPAddress SAN:
openssl x509 -noout -text -in server.crt | grep "IP Address"
# No output means no iPAddress SAN: either add one or connect by hostname
```

**AIA fetching masking a missing intermediate**
A browser or AIA-capable verifier may silently fetch a missing
intermediate. The connection succeeds; the chain as presented is
incomplete. Always test with `openssl s_client` or curl, not a browser.

**Clock skew tolerance active in verifier**
An expired or not-yet-valid cert may be accepted within a configured
tolerance window. No signal is emitted. To detect it manually, compare
the cert's validity dates against the current time:
```bash
# Read the cert's validity window:
openssl x509 -noout -dates -in cert.crt

# Read the current time on the verifier:
date -u

# If current time is past notAfter or before notBefore,
# the cert is outside its validity window regardless of whether
# the connection succeeded.
```