# mtls-trust-decision-lab
A verifier-centric lab that models mTLS as an ordered trust decision graph, with reproducible failure archetypes and evidence-based debugging.

## What this repo proves

This repo demonstrates that mTLS success or failure is the result of
a deterministic verifier decision process, not randomness.

## What it ignores

- Production concerns
- Scaling
- Zero Trust architecture
- Automation

## How to run baseline success

0. Prerequisites:
- Docker Desktop + WSL2 integration enabled, docker compose available in WSL, OpenSSL available.


- Known issue: docker-credential-desktop.exe: exec format error
  - Cause: Docker is trying to use a Windows helper inside Linux 
  - Fix: remove credsStore/credHelpers from ~/.docker/config.json in WSL

1. Generate certs:
```bash
make certs
```

2. Prove mTLS works (baseline good path):
```bash
make success-run
```