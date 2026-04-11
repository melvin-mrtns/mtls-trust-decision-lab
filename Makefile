.PHONY: regen certs success-run clean root intermediate server client fail-run restart all

# Ensure bind-mounted log files are writable by the current host user
DOCKER_UID := $(shell id -u)
DOCKER_GID := $(shell id -g)
export DOCKER_UID
export DOCKER_GID

regen: clean root intermediate server client

certs: root intermediate server client

all: certs restart
	$(MAKE) _fail-run ARCHETYPE=MissingPeerCredentialsFailure CASE=MissingClientCertificateCase
	$(MAKE) _fail-run ARCHETYPE=PrivateKeyProofFailure CASE=CertificateVerifySignatureMismatchCase
	$(MAKE) _fail-run ARCHETYPE=IncompleteChainFailure CASE=MissingIntermediateCase
	$(MAKE) _fail-run ARCHETYPE=TrustAnchorResolutionFailure CASE=WrongTrustAnchorCase
	$(MAKE) _fail-run ARCHETYPE=TrustAnchorResolutionFailure CASE=UntrustedSelfSignedLeafCase
	$(MAKE) _fail-run ARCHETYPE=ValidityWindowFailure CASE=ExpiredCertificateCase
	$(MAKE) _fail-run ARCHETYPE=ValidityWindowFailure CASE=NotYetValidCertificateCase
	$(MAKE) _fail-run ARCHETYPE=UsageConstraintFailure CASE=ExtendedKeyUsageConstraintCase
	$(MAKE) _fail-run ARCHETYPE=UsageConstraintFailure CASE=BasicConstraintsViolationCase
	$(MAKE) _fail-run ARCHETYPE=SubjectIdentityMismatchFailure CASE=DnsSanMismatchCase

restart:
	chmod +x scripts/docker-run.sh
	chmod +x scripts/collect-evidence.sh
	chmod +x scripts/analyze_run.py
	./scripts/docker-run.sh

# Internal target: Run a single failure without regenerating the certs
_fail-run: fix-runlogs-perms
	chmod +x failures/$(ARCHETYPE)/$(CASE)/run.sh
	./failures/$(ARCHETYPE)/$(CASE)/run.sh

# Public target: regenerate certs and restart before running the failure
fail-run: certs restart fix-runlogs-perms
	$(MAKE) _fail-run ARCHETYPE=$(ARCHETYPE) CASE=$(CASE)

success-run: certs restart fix-runlogs-perms
	chmod +x success/run.sh
	./success/run.sh

fix-runlogs-perms:
	- docker compose -f docker-compose.yml exec -T nginx sh -lc 'chown -R $(DOCKER_UID):$(DOCKER_GID) /var/log/nginx 2>/dev/null || true'

clean:
	rm -r evidence/
	rm -f certs/root/*.crt certs/root/*.key certs/root/*.srl certs/root/*.csr
	rm -f certs/ca/*.crt
	rm -f certs/intermediate/*.crt certs/intermediate/*.key certs/intermediate/*.csr certs/intermediate/*.srl
	rm -f certs/server/*.crt certs/server/*.key certs/server/*.csr certs/server/*.srl
	rm -f certs/client/*.crt certs/client/*.key certs/client/*.csr certs/client/*.srl
	rm -f failures/PrivateKeyProofFailure/CertificateVerifySignatureMismatchCase/wrong_client.key
	rm -f failures/ValidityWindowFailure/ExpiredCertificateCase/*.crt failures/ValidityWindowFailure/ExpiredCertificateCase/*.key failures/ValidityWindowFailure/ExpiredCertificateCase/*.srl failures/ValidityWindowFailure/ExpiredCertificateCase/*.csr
	rm -f failures/ValidityWindowFailure/NotYetValidCertificateCase/*.crt failures/ValidityWindowFailure/NotYetValidCertificateCase/*.key failures/ValidityWindowFailure/NotYetValidCertificateCase/*.srl failures/ValidityWindowFailure/NotYetValidCertificateCase/*.csr
	rm -f failures/UsageConstraintFailure/ExtendedKeyUsageConstraintCase/*.crt failures/UsageConstraintFailure/ExtendedKeyUsageConstraintCase/*.key failures/UsageConstraintFailure/ExtendedKeyUsageConstraintCase/*.srl failures/UsageConstraintFailure/ExtendedKeyUsageConstraintCase/*.csr
	rm -f failures/UsageConstraintFailure/BasicConstraintsViolationCase/*.crt failures/UsageConstraintFailure/BasicConstraintsViolationCase/*.key failures/UsageConstraintFailure/BasicConstraintsViolationCase/*.srl failures/UsageConstraintFailure/BasicConstraintsViolationCase/*.csr
	rm -f failures/TrustAnchorResolutionFailure/UntrustedSelfSignedLeafCase/*.crt failures/TrustAnchorResolutionFailure/UntrustedSelfSignedLeafCase/*.key failures/TrustAnchorResolutionFailure/UntrustedSelfSignedLeafCase/*.srl failures/TrustAnchorResolutionFailure/UntrustedSelfSignedLeafCase/*.csr
	rm -f failures/TrustAnchorResolutionFailure/WrongTrustAnchorCase/*.crt failures/TrustAnchorResolutionFailure/WrongTrustAnchorCase/*.key failures/TrustAnchorResolutionFailure/WrongTrustAnchorCase/*.srl failures/TrustAnchorResolutionFailure/WrongTrustAnchorCase/*.csr


root:
	openssl genrsa -out certs/root/root.key 4096
	openssl req -new -sha256 \
      -key certs/root/root.key \
      -subj "/C=US/O=Lab Root CA/CN=Lab Root CA" \
      -out certs/root/root.csr
	openssl x509 -req -sha256 \
		-in certs/root/root.csr \
		-signkey certs/root/root.key \
		-days 3650 \
		-out certs/root/root.crt \
		-extfile certs/root/root.ext \
		-extensions v3_root_ca
	cp certs/root/root.crt certs/ca/

intermediate: root
	openssl genrsa -out certs/intermediate/intermediate.key 4096
	openssl req -new -sha256 \
	  -key certs/intermediate/intermediate.key \
	  -subj "/C=US/O=Lab Intermediate CA/CN=Lab Intermediate CA" \
	  -out certs/intermediate/intermediate.csr
	openssl x509 -req -sha256 \
	  -in certs/intermediate/intermediate.csr \
	  -CA certs/root/root.crt \
	  -CAkey certs/root/root.key \
	  -CAcreateserial \
	  -days 1825 \
	  -out certs/intermediate/intermediate.crt \
	  -extfile certs/intermediate/intermediate.ext \
	  -extensions v3_intermediate_ca

server: intermediate
	openssl genrsa -out certs/server/server.key 2048
	openssl req -new -sha256 \
	  -key certs/server/server.key \
	  -subj "/C=US/O=Lab Server/CN=localhost" \
	  -out certs/server/server.csr
	openssl x509 -req -sha256 \
	  -in certs/server/server.csr \
	  -CA certs/intermediate/intermediate.crt \
	  -CAkey certs/intermediate/intermediate.key \
	  -CAcreateserial \
	  -days 120 \
	  -out certs/server/server.crt \
	  -extfile certs/server/server.ext \
	  -extensions v3_server
	cat certs/server/server.crt certs/intermediate/intermediate.crt > certs/server/server.fullchain.crt

client: intermediate
	openssl genrsa -out certs/client/client.key 2048
	openssl req -new -sha256 \
	  -key certs/client/client.key \
	  -subj "/C=US/O=Lab Client/CN=lab-client" \
	  -out certs/client/client.csr
	openssl x509 -req -sha256 \
	  -in certs/client/client.csr \
	  -CA certs/intermediate/intermediate.crt \
	  -CAkey certs/intermediate/intermediate.key \
	  -CAcreateserial \
	  -days 120 \
	  -out certs/client/client.crt \
	  -extfile certs/client/client.ext \
	  -extensions v3_client
	cat certs/client/client.crt certs/intermediate/intermediate.crt > certs/client/client.fullchain.crt
