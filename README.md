# clienthub
ClientHub - customer portal (Digital Services)

## Printed Chapters 11, 16 and 17

`src/ClientHub` is a runnable .NET 8 application with `/health` and
build-stamped `/version` endpoints. Build with:

```powershell
dotnet build src/ClientHub -c Release
```

The book's printed exercises and companion guides describe provisioning a
Central US Linux S1 plan, this app's staging slot, and environment-specific
immutable GitHub OIDC trust. Configure non-secret Azure repository variables
and a required reviewer on `production` before running the workflows.

- `release.yml` builds and deploys the candidate to staging, then waits for
  production review before clearing temporary traffic routing and swapping.
  Its concurrency group serializes releases.
- `scripts/monitor.ps1` configures sticky telemetry destination settings and
  creates one named availability test and alert, using authorized shared
  monitoring resources without altering the component or workspace.
- `scripts/observe.sh` checks the actual staged version/health before writing
  its deployment annotation.
- `gate.yml` evaluates the existing candidate with `scripts/gate.sh`.
  `unhealthy`, `empty`, and `insufficient` must block; `healthy` can unlock
  production review only after enough persisted, run-isolated telemetry.
- `/lab/probe` exists only with `LAB_PROBES=true`. Enable it in a sandbox
  staging slot only; do not expose deliberate-failure testing to customers.
- `scripts/cleanup.ps1` removes the owned App Service/monitoring resources,
  identity, scoped roles and Azure variables. Remove only your own deployment
  annotations after recording their evidence.

For the chapter example:

```powershell
gh workflow run release.yml -f version=2.0.0 -f gate=off
gh workflow run release.yml -f version=3.1.0 `
  -f monitor=true -f gate=off
gh workflow run gate.yml -f version=3.1.0 -f scenario=healthy
```

The 2026-10-09 print validation finished and tore down its Azure resources,
credentials and variables. Code, workflows and reviewer-protected environments
remain as the reader end state; configure your own identifiers before running.
