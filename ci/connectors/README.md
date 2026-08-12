# Connector Integration Tests CI

This directory contains CI/CD files specifically for running integration tests on Aerospike connectors.

## Files

- **`Jenkinsfile`** - Jenkins Pipeline definition for running connector integration tests
- **`run-all-connector-tests.sh`** - Master script that orchestrates integration tests for all connectors

## Connectors Tested

The following connectors are tested:
- `aerospike-elasticsearch-outbound`
- `aerospike-esp-outbound`
- `aerospike-jms-inbound`
- `aerospike-jms-outbound`
- `aerospike-kafka-outbound`
- `aerospike-pulsar-outbound`
- `aerospike-xdr-proxy`

## Usage

### Running Locally

```bash
cd /path/to/helm-charts
./ci/connectors/run-all-connector-tests.sh
```


### Running in GitHub Actions

Workflow: **Connector Integration Tests** (`.github/workflows/connector-integration-tests.yaml`)

Uses the existing repository secret `FEATURES_CONF` containing the Aerospike `features.conf` contents.

**Automatic run after packaging**

When **Package Connector Helm Charts** completes successfully, it calls **Connector Integration Tests** on the feature branch that was just pushed.

**End-to-end release from main**

1. Open **Actions → Package Connector Helm Charts → Run workflow** on `main`
2. Set `branch_name` to the JIRA id (e.g. `CONNECTOR-1645`)
3. Select connectors and set `version_bump` (default `patch`)
4. The workflow reuses the feature branch if it already exists, otherwise creates it from `main`, applies Helm updates on that branch, opens/updates a PR to `main`, then runs integration tests on the feature branch

```bash
gh workflow run package-connector-charts.yaml \
  --ref main \
  -f branch_name=CONNECTOR-1645 \
  -f version_bump=patch
```

Optional `-f pr_title='Custom release title'` overrides the default suffix. When omitted, the PR title is:

`[CONNECTOR-1645] - [Streaming] Aerospike Streaming Connectors - Security vulnerabilities - Aug'26`

(month/year are set automatically from the current date in IST). Reviewers `mphanias`, `abhilashmandaliya`, and `VivekASHub` are requested on every release PR.

**Manual run**

1. Open **Actions → Connector Integration Tests → Run workflow**
2. Select the branch to test (e.g. your PR branch)
3. Select connectors using the checkboxes (all selected by default)

Manual runs require permission to trigger workflows on this repository (configure under **Settings → Actions → General**).

**Pull request runs**

Pull requests trigger this workflow when connector **test or CI** files change (`ci/connectors/**`, `aerospike-*/tests/**`, or `.github/workflows/connector-integration-tests.yaml`). Changes to chart packaging files alone (`Chart.yaml`, `README.md`, `docs/`) do not trigger it; those release PRs run tests via **Package Connector Helm Charts** instead.

Fork and Dependabot pull requests are skipped automatically because repository secrets (including `FEATURES_CONF`) are unavailable on those `pull_request` runs. Re-running failed PR jobs or triggering **Connector Integration Tests** manually does not update PR checks; merge the skip fix to `main`, update the Dependabot branch, then re-run PR checks (or merge with admin override after a manual green run).

Test logs are uploaded as workflow artifacts for 14 days.

### Packaging connector charts

Workflow: **Package Connector Helm Charts** (`.github/workflows/package-connector-charts.yaml`)

**Version inputs**

| Input | Purpose |
|---|---|
| `version_bump` | Default for all selected charts: `patch`, `minor`, `major`, `none`, or explicit `X.Y.Z` |
| `chart_version_overrides` | Optional JSON map overriding `version_bump` per chart directory |

Example overrides (each value can be a bump mode or explicit semver):

```json
{
  "aerospike-kafka-outbound": "6.1.0",
  "aerospike-jms-outbound": "minor",
  "aerospike-esp-outbound": "none"
}
```

Charts not listed in overrides use `version_bump`. With `version_bump=none`, only charts listed in overrides are updated.

**Branch inputs**

| Input | Purpose |
|---|---|
| `branch_name` | JIRA feature branch and PR head (e.g. `CONNECTOR-1645`) |
| `pr_title` | Optional title suffix after the JIRA prefix; default is `[Streaming] Aerospike Streaming Connectors - Security vulnerabilities - Mon'YY` (IST) |

If the feature branch already exists it is reused; otherwise it is created from `main` on the first push. New `docs/index.yaml` entries use `Asia/Kolkata` timestamps to match prior releases.

After packaging, the workflow verifies each connector Docker image exists on Docker Hub (using `values.yaml` `image.repository` and `appVersion`), verifies each `.tgz` with `helm show chart`, prints `sha256sum`, and confirms the digest matches `docs/index.yaml` (also included in the release PR body). Integration tests checkout the pushed release commit (SHA when available), not the caller branch.

```bash
gh workflow run package-connector-charts.yaml \
  --ref main \
  -f branch_name=CONNECTOR-1645 \
  -f version_bump=patch \
  -f 'chart_version_overrides={"aerospike-kafka-outbound":"6.1.0","aerospike-jms-outbound":"4.3.0"}'
```

### Running in Jenkins

1. Create a Pipeline job in Jenkins
2. Configure it to use `ci/connectors/Jenkinsfile` from your repository
3. Jenkins will automatically:
   - Checkout the code
   - Run all connector integration tests
   - Archive logs
   - Send notifications

## Script Behavior

The `run-all-connector-tests.sh` script:
1. Tests each connector sequentially
2. For each connector:
   - Installs Kind cluster (`install-kind.sh`)
   - Runs integration test (`run-integration-test.sh`)
   - Collects results (PASSED/FAILED)
   - Uninstalls Kind cluster (`uninstall-kind.sh`)
3. Continues testing all connectors regardless of individual pass/fail
4. Prints summary metrics at the end
5. Exits with success only if all connectors pass

## Log Files

All test logs are stored in `/tmp/`:
- `${connector}-install.log` - Kind cluster installation logs
- `${connector}-test.log` - Integration test execution logs
- `${connector}-uninstall.log` - Kind cluster cleanup logs

## Path Resolution

The script automatically resolves paths:
- Script location: `ci/connectors/run-all-connector-tests.sh`
- Repo root: Resolved as `ci/connectors/../..`
- Connectors: Located at `${REPO_ROOT}/${connector}`

This ensures the script works regardless of where it's executed from.
