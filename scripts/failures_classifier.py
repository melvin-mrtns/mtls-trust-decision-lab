FAILURES_CLASSIFIER = {
    "MissingPeerCredentialsFailure": {
        "step_id": 1,
        "step_name": "Peer Certificate Presentation",
        "decision": "Was the peer certificate presented when required?",
        "cases": [
            {
                "MissingClientCertificateCase": {
                    "detected_by": ["server"],
                    "failing_input": "Presented Certificate Chain (absent)",
                    "symptom": "Server required a client certificate but none was presented.",
                    "evidence_file": "server/error.log",
                    "signals": [
                        r"client sent no required SSL certificate",
                        r"no required SSL certificate was sent",
                    ],
                    "exclusions": [],
                    "minimal_fix": "Present a client certificate/key (curl: --cert/--key).",
                }
            },
        ],
    },

    "TrustAnchorResolutionFailure": {
        "step_id": 2,
        "step_name": "Trust Anchor Resolution (Trust Store Acceptance)",
        "decision": "Does the constructed chain terminate at an acceptable trust anchor in the trust store?",
        "cases": [
            {
                "WrongTrustAnchorCase": {
                    "detected_by": ["client", "server"],
                    "failing_input": "Trust store / trust anchors",
                    "symptom": "Trust store did not contain the correct trust anchor for the presented chain.",
                    "evidence_file": "client/handshake.txt OR server/error.log",
                    "signals": [
                        r"unable to get local issuer certificate",
                        r"unable to get issuer certificate",
                        r"certificate verify failed",
                        r"SSL certificate problem: unable to get (?:local )?issuer certificate",
                        r"SSL certificate problem: certificate verify failed",
                    ],
                    "exclusions": [
                        r"no peer certificate available",
                        r"self[- ]signed certificate",
                        r"no alternative certificate subject name matches",
                        r"subject name.*does not match",
                        r"certificate has expired",
                        r"not yet valid",
                        r"no required SSL certificate was sent",
                        r"client sent no required SSL certificate",
                        r"unsuitable certificate purpose",
                        r"unsupported certificate purpose",
                    ],
                    "minimal_fix": "Use the correct CA bundle for the chain (curl: --cacert must point to the actual root/CA used).",
                }
            },
            {
                "UntrustedSelfSignedLeafCase": {
                    "detected_by": ["client"],
                    "failing_input": "Trust store / trust anchors",
                    "symptom": "Client could not anchor the server chain because the server leaf is self-signed and not trusted.",
                    "evidence_file": "client/handshake.txt",
                    "signals": [
                        r"self[- ]signed certificate",
                        r"SSL certificate problem:\s*self[- ]signed certificate",
                    ],
                    "exclusions": [],
                    "minimal_fix": "Use a server cert signed by the expected CA chain, or deliberately trust the correct CA if that is intended policy.",
                }
            },
        ],
    },

    "IncompleteChainFailure": {
        "step_id": 3,
        "step_name": "Path Building (Chain Construction)",
        "decision": "Can the verifier construct a complete chain from the presented certificates?",
        "cases": [
            {
                "MissingIntermediateCase": {
                    "detected_by": ["client", "server"],
                    "failing_input": "Presented Certificate Chain (intermediate absent)",
                    "symptom": "Verifier could not construct a complete chain from the presented certs (missing intermediate).",
                    "evidence_file": "client/handshake.txt OR server/error.log",
                    "signals": [
                        r"unable to get local issuer certificate",
                        r"unable to get issuer certificate",
                        r"unable to verify the first certificate",
                        r"certificate verify failed",
                    ],
                    "exclusions": [
                        r"no peer certificate available",
                        r"self[- ]signed certificate",
                        r"no alternative certificate subject name matches",
                        r"certificate has expired",
                        r"not yet valid",
                    ],
                    "minimal_fix": "Present leaf + required intermediates (use a fullchain) so the verifier can build to a trust anchor.",
                }
            }
        ],
    },

    "PrivateKeyProofFailure": {
        "step_id": 4,
        "step_name": "Proof of Possession (Handshake Signature / CertificateVerify)",
        "decision": "Did the peer prove possession of the private key (CertificateVerify signature verifies)?",
        "cases": [
            {
                "CertificateVerifySignatureMismatchCase": {
                    "detected_by": ["server"],
                    "failing_input": "CertificateVerify Message (signature mismatch)",
                    "symptom": "Client certificate was presented but the private key used does not match (CertificateVerify fails).",
                    "evidence_file": "inputs/client/key.pubkey_sha256.txt + inputs/client/cert.pubkey_sha256.txt",
                    "signals": [],
                    "exclusions": [],
                    "minimal_fix": "Use the private key that matches the presented certificate, or re-issue the cert for the intended key.",
                }
            }
        ],
    },

    "ValidityWindowFailure": {
        "step_id": 5,
        "step_name": "Time Validity",
        "decision": "Is verification time within NotBefore/NotAfter for the relevant certificate?",
        "cases": [
            {
                "ExpiredCertificateCase": {
                    "detected_by": ["client", "server"],
                    "failing_input": "Current time / NotAfter",
                    "symptom": "Certificate NotAfter is in the past at verification time.",
                    "evidence_file": "client/handshake.txt OR server/error.log OR certs/fields/client_cert.txt + server/nginx_time_utc.txt",
                    "signals": [
                        r"certificate has expired",
                        r"expired.*certificate",
                    ],
                    "exclusions": [],
                    "minimal_fix": "Rotate/re-issue the leaf certificate.",
                }
            },
            {
                "NotYetValidCertificateCase": {
                    "detected_by": ["client", "server"],
                    "failing_input": "Current time / NotBefore",
                    "symptom": "Certificate NotBefore is in the future at verification time.",
                    "evidence_file": "client/handshake.txt OR server/error.log OR certs/fields/client_cert.txt + server/nginx_time_utc.txt",
                    "signals": [
                        r"not yet valid",
                        r"certificate is not yet valid",
                    ],
                    "exclusions": [],
                    "minimal_fix": "Re-issue the leaf certificate with correct NotBefore, or correct system clock if wrong.",
                }
            },
        ],
    },

    "UsageConstraintFailure": {
        "step_id": 6,
        "step_name": "Usage Constraints (Role / Purpose Constraints)",
        "decision": "Do KU/EKU/BasicConstraints permit the intended role/purpose?",
        "cases": [
            {
                "ExtendedKeyUsageConstraintCase": {
                    "detected_by": ["server"],
                    "failing_input": "Presented Certificate Chain (EKU field) / Verification policy configuration",
                    "symptom": "Certificate EKU purpose is not valid for the intended role (example: clientAuth required).",
                    "evidence_file": "server/error.log",
                    "signals": [
                        r"unsuitable certificate purpose",
                        r"unsupported certificate purpose",
                    ],
                    "exclusions": [],
                    "minimal_fix": "Re-issue the leaf certificate with correct EKU (clientAuth for client cert).",
                }
            },
            {
                "BasicConstraintsViolationCase": {
                    "detected_by": ["server"],
                    "failing_input": "Presented Certificate Chain (BasicConstraints field)",
                    "symptom": "Client leaf certificate violates BasicConstraints expectations (e.g., CA:TRUE for a leaf credential).",
                    "evidence_file": "certs/fields/client_cert.txt",
                    "signals": [],
                    "exclusions": [],
                    "minimal_fix": "Re-issue the leaf certificate with BasicConstraints CA:FALSE.",
                }
            },
        ],
    },
    "SubjectIdentityMismatchFailure": {
        "step_id": 7,
        "step_name": "Identity Binding (SAN / Name Verification)",
        "decision": "Does the expected identity match the certificate SAN/name verification rules?",
        "cases": [
            {
                "DnsSanMismatchCase": {
                    "detected_by": ["client"],
                    "failing_input": "Target identity / Presented Certificate Chain (SAN)",
                    "symptom": "Client rejected server certificate due to hostname/SAN mismatch.",
                    "evidence_file": "client/handshake.txt",
                    "signals": [
                        r"no alternative certificate subject name matches",
                        r"subject name does not match",
                    ],
                    "exclusions": [],
                    "minimal_fix": "Issue server cert with SAN including the hostname used by the client (or use the correct hostname/SNI).",
                }
            }
        ],
    },
}