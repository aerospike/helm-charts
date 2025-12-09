# Connector Integration Tests CI

This directory contains CI/CD files specifically for running integration tests on Aerospike connectors.

## Files

- **`Jenkinsfile`** - Jenkins Pipeline definition for running connector integration tests
- **`run-all-connector-tests.sh`** - Master script that orchestrates integration tests for all connectors

## Connectors Tested

The following connectors are tested:
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
