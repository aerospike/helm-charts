# Aerospike JMS Outbound Connector

This Helm chart allows you to configure and run our official [Aerospike JMS Outbound Connector](https://hub.docker.com/repository/docker/aerospike/aerospike-jms-outbound) 
docker image on a Kubernetes cluster.

This helm chart sets up a `StatefulSet` for each connector deployment. We use a `StatefulSet` instead of a `Deployment`, to have stable DNS names for the  
deployed connector pods.

**_NOTE:_** The helm chart appends `-aerospike-jms-outbound` suffix to all created Kubernetes resources to prevent name clashes with other applications.

## Prerequisites

- **Kubernetes Cluster**: A running Kubernetes cluster (v1.19+)
  - Local options: [kind](https://kind.sigs.k8s.io/), [minikube](https://minikube.sigs.k8s.io/), [Docker Desktop](https://www.docker.com/products/docker-desktop)
  - Cloud options: GKE, EKS, AKS, or any Kubernetes cluster
- **Helm**: v3.x installed ([Install Helm](https://helm.sh/docs/intro/install/))
- **kubectl**: Configured to connect to your cluster
- **JMS Broker**: A JMS broker (RabbitMQ, ActiveMQ, IBM MQ, etc.) reachable from the pods in the Kubernetes cluster
- **Aerospike Cluster**: An Aerospike cluster that can connect to Pods in the Kubernetes cluster.
  The Aerospike cluster can be deployed in the same Kubernetes cluster using [Aerospike
  Kubernetes Operator](https://docs.aerospike.com/cloud/kubernetes/operator)

## Quick Start

### Option 1: Using the Deployment Script

```bash
# Deploy with default values
./tests/deploy-test.sh

# Deploy with custom values file
./tests/deploy-test.sh --values examples/clear-text/as-jms-outbound-values.yaml

# Deploy with TLS configuration
./tests/deploy-test.sh --values examples/tls/as-jms-outbound-tls-values.yaml

# Deploy to custom namespace
./tests/deploy-test.sh --namespace my-namespace --release-name my-release

# Uninstall
./tests/deploy-test.sh --uninstall
```

### Option 2: Setting Up a Local Test Cluster

If you don't have a Kubernetes cluster, you can set up a local kind cluster:

```bash
# Set up complete kind cluster with OLM and operator
cd kind
./install-kind.sh

# Navigate back to chart directory
cd ..

# Deploy the chart
./tests/deploy-test.sh --values examples/clear-text/as-jms-outbound-values.yaml
```

For more details on kind setup, see [kind/README.md](kind/README.md).

### Option 3: Using Helm Directly

```bash
# Create namespace
kubectl create namespace aerospike-test

# Deploy with default values
helm install test-jms-outbound . \
  --namespace aerospike-test \
  --wait --timeout 5m

# Deploy with custom values
helm install test-jms-outbound . \
  --namespace aerospike-test \
  --values examples/clear-text/as-jms-outbound-values.yaml \
  --wait --timeout 5m
```

## Install the helm chart

Add the `aerospike` helm repository if not already done

```shell
helm repo add aerospike https://aerospike.github.io/helm-charts
```

Install the Aerospike JMS Outbound connector helm chart

```shell
helm install aerospike-jms-outbound aerospike/aerospike-jms-outbound
```

## Supported configuration

## Configuration

| Parameter            | Description                                                                                                                                                                          | Default                        |
|----------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------|
| `replicaCount`       | Configures the number Aerospike JMS connector pods to run.                                                                                                                           | '1'                            |
| `image`              | Configures Aerospike JMS connector image repository, tag and pull policy.                                                                                                            | see [values.yaml](values.yaml) |
| `connectorConfig`    | Connector configuration deployed to `/etc/aerospike-jms-outbound/aerospike-jms-outbound.yml`.                                                                                        | see [values.yaml](values.yaml) |
| `connectorSecrets`   | List of secrets mounted to `/etc/aerospike-jms-outbound/secrets` for each connector pod.                                                                                             | `[]`                           |
| `initContainers`     | List of initContainers added to each connector pods for custom code plugin jars.                                                                                                     | `[]`                           |
| `serviceAccount`     | Service Account details like name and annotations.                                                                                                                                   | see [values.yaml](values.yaml) |
| `podAnnotations`     | Additional pod [annotations](https://kubernetes.io/docs/concepts/overview/working-with-objects/annotations/). Should be specified as a map of annotation names to annotation values. | `{}`                           |
| `podSecurityContext` | Pod [security context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)                                                                                   | `{}`                           |
| `securityContext`    | Container [security context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/#set-the-security-context-for-a-container)                                    | `{}`                           |
| `resources`          | Resource [requests and limits](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) for the connector pods.                                               | `{}`                           |
| `autoscaling`        | Enable the horizontal pod auto-scaler.                                                                                                                                               | see [values.yaml](values.yaml) |
| `affinity`           | [Affinity](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#affinity-and-anti-affinity)  rules if any for the pods.                                          | `{}`                           |
| `nodeSelector`       | [Node selector](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#nodeselector)  for the pods.                                                                | `{}`                           |
| `tolerations`        | [Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)  for the pods.                                                                          | `{}`                           |

## Deploy the connectors

We recommend creating a new `.yaml` for providing configuration values to the helm chart for deployment.
See the [examples](examples) folder for examples.

A sample values yaml file is shown below:

```yaml
replicaCount: 3

image:
  tag: "4.2.13"

connectorConfig:
  service:
    # TLS setup for communication between Aerospike server (XDR) and the
    # connector.
    # Use the TLS certificates and keys specific to your setup.
    # See: https://docs.aerospike.com/connect/jms/from-asdb/configuring/service#configuring-tls
    port: 8080

    manage:
      port: 8081

  # See: https://docs.aerospike.com/connect/jms/from-asdb/configuring/jms
  # The connection properties for the JMS message broker.
  jms:
    #  # RabbitMQ example.
    factory: com.rabbitmq.jms.admin.RMQConnectionFactory
    config:
      host: rabbitmq.rabbitmq-system
      port: 5672
      username: guest
      password: guest

  #  # ActiveMQ example.
  #  factory: org.apache.activemq.artemis.jndi.ActiveMQInitialContextFactory
  #  jndi-cf-name: ConnectionFactory
  #  config:
  #    java.naming.provider.url: tcp://127.0.0.1:61616
  #    java.naming.security.principal: admin
  #    java.naming.security.credentials: password

  #  # IBM MQ example.
  #  factory: com.ibm.mq.jms.MQConnectionFactory
  #  config:
  #    hostName: 127.0.0.1
  #    port: 1414
  #    queueManager: QM1
  #    transportType: 1
  #    channel: DEV.APP.SVRCONN

  # Format of the JMS destination message.
  format:
    mode: flat-json
    metadata-key: metadata

  # Aerospike record routing to a JMS destination.
  routing:
    mode: static
    type: queue
    destination: aerospike  # <---- Change this to the name of the JMS destination.

  # The logging properties.
  logging:
    enable-console-logging: true
```

Here `replicaCount` is the count of connectors pods that are deployed. 
The connector configuration is provided as yaml under the key `connectorConfig`.
See [Aerospike JMS Outbound configuration](https://docs.aerospike.com/connect/jms/from-asdb/configuring) for details.

Update the `jms` configuration to point to your JMS Provider.

We recommend naming the file with the name of the connector cluster. For example if you want to name your connector cluster as
`as-jms-outbound`, create a file `as-jms-outbound-values.yaml`.
Once you have created this custom values file, deploy the connectors, using the following command.

### Create a new namespace
We recommend using `aerospike` namespace for the connector cluster. If the namespace does not exist run the following command:
```shell
kubectl create namespace aerospike
```

### Create secrets

You can create additional secrets, for confidential data like TLS certificates, that are mounted to the connector pods.
The connector can then be configured to use these secrets. See [examples/tls](examples/tls) for example.

If deploying with TLS, create the required secrets:

```bash
# Create namespace (if not already created)
kubectl create namespace aerospike-test

# Create TLS secret
# Use the sample TLS certificates from examples/tls/tls-certs folder
kubectl -n aerospike-test create secret generic tls-certs --from-file=examples/tls/tls-certs
```

### Deploy the connector cluster

```shell
# helm install --namespace <target namespace> <helm release name/cluster name> -f <path to custom values yaml> aerospike/aerospike-jms-outbound
helm install --namespace aerospike as-jms-outbound -f as-jms-outbound-values.yaml aerospike/aerospike-jms-outbound
```

Here `as-jms-outbound` is the release name for the connector cluster and also its cluster name.

On successful deployment you should see output similar to below:

```shell
NAME: as-jms-outbound
LAST DEPLOYED: Mon Oct 17 20:44:34 2022
NAMESPACE: aerospike
STATUS: deployed
REVISION: 1
NOTES:
1. Get the list of connector pods  by running the command:

kubectl get pods --namespace aerospike --selector=app=as-jms-outbound-aerospike-jms-outbound --no-headers -o custom-columns=":metadata.name"

2. Configure XDR to use each of these connector pods in the datacenter section

Use the following command to get the pod DNS names and port to use.

kubectl get pods --namespace aerospike --selector=app=as-jms-outbound-aerospike-jms-outbound --no-headers -o custom-columns=":metadata.name" \
    | sed -e "s/$/.as-jms-outbound-aerospike-jms-outbound 8080/g"

Visit https://docs.aerospike.com/connect/common/change-notification for details
```

## List pods for the connector
To list the pods for the connector run the following command:
```shell
# kubectl get pods --namespace aerospike --selector=app=<helm release name>-aerospike-jms-outbound
kubectl get pods --namespace aerospike --selector=app=as-jms-outbound-aerospike-jms-outbound
```

You should see output similar to the following:
```shell
NAME                                           READY   STATUS    RESTARTS   AGE
as-jms-outbound-aerospike-jms-outbound-0   1/1     Running   0          7m19s
as-jms-outbound-aerospike-jms-outbound-1   1/1     Running   0          7m40s
as-jms-outbound-aerospike-jms-outbound-2   1/1     Running   0          7m51s
```

## Configure XDR to ship to connector pods

Pod DNS names can be used directly if the Aerospike cluster is also running in the same Kubernetes cluster. 
To get the pod DNS names and ports to be added to XDR DC section, run the following command.

```shell
# kubectl get pods --namespace <target namespace> --selector=app=<helm release name>-aerospike-jms-outbound --no-headers -o custom-columns=":metadata.name" \
#    | sed -e "s/$/.<helm release name>-aerospike-jms-outbound <service port or service TLS port as desired>/g"
kubectl get pods --namespace aerospike --selector=app=as-jms-outbound-aerospike-jms-outbound --no-headers -o custom-columns=":metadata.name" \
    | sed -e "s/$/.as-jms-outbound-aerospike-jms-outbound 8080/g"
```

You should see output similar to the following
```shell
as-jms-outbound-aerospike-jms-outbound-0.as-jms-outbound-aerospike-jms-outbound 8080
as-jms-outbound-aerospike-jms-outbound-1.as-jms-outbound-aerospike-jms-outbound 8080
as-jms-outbound-aerospike-jms-outbound-2.as-jms-outbound-aerospike-jms-outbound 8080
```

If you are using [Aerospike Kubernetes Operator](https://docs.aerospike.com/connect/jms/from-asdb/configuring), 
see [clear text](examples/clear-text) and [tls](examples/tls) for reference.

## Get logs for all connector instances

```shell
# kubectl -n aerospike logs -f statefulset/<helm release name>-aerospike-jms-outbound
# Skip the -f flag to get a one time dump of the log
kubectl -n aerospike logs -f statefulset/as-jms-outbound-aerospike-jms-outbound
```

## Get logs for a single connector pod

```shell
# kubectl -n aerospike logs -f <helm release name>-aerospike-jms-outbound-0
# Skip the -f flag to get a one time dump of the log
kubectl -n aerospike logs -f as-jms-outbound-aerospike-jms-outbound-0
```

## Verify Deployment

After deployment, verify all resources are created:

```bash
# Check pod status
kubectl get pods -n aerospike-test

# Check StatefulSet
kubectl get statefulset -n aerospike-test

# Check service
kubectl get service -n aerospike-test

# Check ConfigMap
kubectl get configmap -n aerospike-test

# View pod logs
kubectl logs -n aerospike-test -l app.kubernetes.io/name=aerospike-jms-outbound --tail=50

# Describe a pod for detailed information
kubectl describe pod -n aerospike-test -l app.kubernetes.io/name=aerospike-jms-outbound
```

## Test Connectivity

```bash
# Get pod DNS names for XDR configuration
kubectl get pods -n aerospike-test \
  --selector=app.kubernetes.io/name=aerospike-jms-outbound \
  --no-headers -o custom-columns=":metadata.name" \
  | sed -e "s/$/.test-jms-outbound-aerospike-jms-outbound 8080/g"

# Test service DNS resolution
kubectl run test-pod --image=busybox --rm -it --restart=Never \
  --namespace aerospike-test \
  -- nslookup test-jms-outbound-aerospike-jms-outbound

# Test port connectivity
kubectl run test-pod --image=busybox --rm -it --restart=Never \
  --namespace aerospike-test \
  -- nc -z test-jms-outbound-aerospike-jms-outbound 8080
```

## Run Helm Tests

```bash
# Run the built-in Helm tests
helm test test-jms-outbound --namespace aerospike-test

# Check test results
kubectl get pods -n aerospike-test -l helm.sh/hook=test
```

## Updating connector configuration

Edit the `connectorConfig` section in the custom values file and save the changes.

Upgrade the connector deployment using the following command. 

```shell
#helm upgrade --namespace <target namespace> <helm release name> -f <path to custom values yaml file> aerospike/aerospike-jms-outbound
helm upgrade --namespace aerospike as-jms-outbound -f as-jms-outbound-values.yaml aerospike/aerospike-jms-outbound
```

On successful execution of the command the connector pods will undergo a rolling restart and come up with the new configuration.

To verify the changes are applied
 - [List the pods](#list-pods-for-the-connector)
 - [Verify the configuration in connector logs](#get-logs-for-all-connector-instances)

**_NOTE:_** The changes might take some time to apply. If you do not see the desired connector config try again after some time. 
If connector pods are not being listed or report status as crashed see [troubleshooting](#troubleshooting).

## Scaling up/down the connectors

Edit the `replicaCount` to the desired connector count and upgrade the connector deployment using the following command.

```shell
#helm upgrade --namespace <target namespace> <helm release name> -f <path to custom values yaml file> aerospike/aerospike-jms-outbound
helm upgrade --namespace aerospike as-jms-outbound -f as-jms-outbound-values.yaml aerospike/aerospike-jms-outbound
```

Verify that the connectors have been scaled.
 - [List the pods](#list-pods-for-the-connector) and verify the count of connectors is as desired

**_NOTE:_** The changes might take some time to apply. If you do not see the desired count try again after some time. 
If connector pods are not being listed or report status as crashed see [troubleshooting](#troubleshooting).

### Update the XDR DC section
If you have scaled up add the new PODs to the XDR DC section else on scale down remove to additional pods DNS names.

## Uninstalling

```bash
# Using the deployment script
./tests/deploy-test.sh --uninstall

# Or using Helm directly
helm uninstall test-jms-outbound --namespace aerospike-test

# Delete namespace (optional)
kubectl delete namespace aerospike-test

# If using TLS, delete the secret (optional)
kubectl delete secret tls-certs --namespace aerospike-test
```

## Production Deployment

For production deployment:

1. Use a dedicated namespace
2. Configure resource limits and requests
3. Enable autoscaling if needed
4. Set up monitoring and alerting
5. Configure TLS with proper certificates
6. Use a private container registry
7. Set up backup and disaster recovery procedures

## Additional Resources

- [Aerospike JMS Outbound Connector Documentation](https://docs.aerospike.com/connect/jms/from-asdb/configuring)
- [Helm Documentation](https://helm.sh/docs/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)

## Troubleshooting

### Connector pods not listed

Check for any error events on the StatefulSet created for the connectors.
```shell
# kubectl -n aerospike describe statefulset <helm release name>-aerospike-jms-outbound
kubectl -n aerospike describe statefulset as-jms-outbound-aerospike-jms-outbound
```

### Connector pods stuck in `init` or `pending` state

Check for any error events on the pod created for the connectors.
```shell
# kubectl -n aerospike describe pod <helm release name>-aerospike-jms-outbound-0
kubectl -n aerospike describe pod as-jms-outbound-aerospike-jms-outbound-0
```

The most likely reason is secret listed in `connectorSecrets` has not been created in the connector namespace.

### Connector pods in crashed state

The most likely reason is connector configuration provided in `connectorConfig` is invalid. 
Verify this by [viewing the connector logs](#get-logs-for-all-connector-instances), fix and [update](#updating-connector-configuration)
the connector configuration.

### Common Issues

1. **Pods not starting**
   - Check pod logs: `kubectl logs -n aerospike-test <pod-name>`
   - Check events: `kubectl describe pod -n aerospike-test <pod-name>`
   - Verify image exists: `docker pull aerospike/aerospike-jms-outbound:latest`

2. **Configuration errors**
   - Verify ConfigMap: `kubectl get configmap -n aerospike-test -o yaml`
   - Check configuration syntax in values file
   - Verify configuration in pod:
     ```bash
     kubectl exec -n aerospike-test test-jms-outbound-aerospike-jms-outbound-0 \
       -- cat /etc/aerospike-jms-outbound/aerospike-jms-outbound.yml
     ```

3. **TLS issues**
   - Verify secrets exist: `kubectl get secrets -n aerospike-test`
   - Check secret mounting: `kubectl describe pod -n aerospike-test <pod-name>`
   - Verify TLS secret exists: `kubectl get secret -n aerospike-test tls-certs`

4. **Connectivity issues**
   - Verify service: `kubectl get svc -n aerospike-test`
   - Test DNS resolution: `kubectl run test-pod --image=busybox --rm -it --restart=Never -- nslookup <service-name>`

## Integration Testing

This chart includes a comprehensive integration test setup that verifies end-to-end data flow:
**Aerospike DB → JMS Outbound Connector → RabbitMQ Broker**

### Quick Start

Run the automated integration test:

```bash
cd tests/integration-test
./run-integration-test.sh
```

The test script will:
1. Deploy RabbitMQ broker (RabbitMQ 3.8.7)
2. Deploy JMS Outbound connector
3. Deploy Aerospike source cluster with XDR pointing to connector
4. Install Aerospike tools
5. Insert test data and verify it in Aerospike DB using AQL
6. Verify data replication to RabbitMQ queue
7. Decode and display message content from queue
8. Display connector metrics and final status

### What the Test Verifies

- ✅ Record insertion in Aerospike DB (verified with AQL SELECT)
- ✅ Data replication to RabbitMQ queue
- ✅ Message content decoding (base64 → JSON)
- ✅ Test key verification in message payload
- ✅ Connector metrics (requests-total, requests-success, jms-connections)

### Prerequisites for Integration Testing

1. **Kind cluster** - See `kind/README.md` for setup instructions
2. **Aerospike Kubernetes Operator** - Installed via the Kind setup script
3. **Aerospike features.conf** - License file placed in `kind/config/features.conf`

For detailed integration testing documentation, see [tests/integration-test/INTEGRATION-TEST.md](tests/integration-test/INTEGRATION-TEST.md).
