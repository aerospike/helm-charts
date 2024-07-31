# Aerospike Pulsar Outbound Connector

This Helm chart allows you to configure and run our official [Aerospike Pulsar Outbound Connector](https://hub.docker.com/repository/docker/aerospike/aerospike-pulsar-outbound) 
docker image on a Kubernetes cluster.

This helm chart sets up a `StatefulSet` for each connector deployment. We use a `StatefulSet` instead of a `Deployment`, to have stable DNS names for the  
deployed connector pods.

**_NOTE:_** The helm chart appends `-aerospike-pulsar-outbound` suffix to all created Kubernetes resources to prevent name clashes with other applications.

## Prerequisites
- Kubernetes cluster
- Helm v3
- A Pulsar cluster with brokers reachable from the pods in the Kubernetes cluster
- An Aerospike cluster that can connect to Pods in the Kubernetes cluster.
  The Aerospike cluster can be deployed in the same Kubernetes cluster using [Aerospike Kubernetes Operator](https://docs.aerospike.com/cloud/kubernetes/operator)

## Adding the helm chart repository

Add the `aerospike` helm repository if not already done

```shell
helm repo add aerospike https://aerospike.github.io/helm-charts
```

## Supported configuration

### Configuration

| Parameter            | Description                                                                                                                                                                          | Default                        |
|----------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------|
| `replicaCount`       | Configures the number Aerospike Pulsar connector pods to run.                                                                                                                        | '1'                            |
| `image`              | Configures Aerospike Pulsar connector image repository, tag and pull policy.                                                                                                         | see [values.yaml](values.yaml) |
| `connectorConfig`    | Connector configuration deployed to `/etc/aerospike-pulsar-outbound/aerospike-pulsar-outbound.yml`.                                                                                  | see [values.yaml](values.yaml) |
| `connectorSecrets`   | List of secrets mounted to `/etc/aerospike-pulsar-outbound/secrets` for each connector pod.                                                                                          | `[]`                           |
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
  tag: "3.3.2"

connectorConfig:
  service:
    # TLS setup for communication between Aerospike server (XDR) and the
    # connector.
    # Use the TLS certificates and keys specific to your setup.
    # See: https://docs.aerospike.com/connect/pulsar/from-asdb/configuring/service#configuring-tls
    port: 8080

    manage:
      port: 8081

  # Pulsar connector client  configuration.
  # See: https://docs.aerospike.com/connect/pulsar/from-asdb/configuring/client-props
  client-configuration:
    serviceUrl: pulsar://pulsar-broker.pulsar:6650

  # Format of the Pulsar destination message.
  format:
    mode: flat-json
    metadata-key: metadata

  # Aerospike record routing to a Pulsar destination.
  routing:
    mode: static
    destination: persistent://apache/pulsar/test-topic   # <--- Change this to your topic

  # The logging properties.
  logging:
    enable-console-logging: true
```

Here `replicaCount` is the count of connectors pods that are deployed. 
The connector configuration is provided as yaml under the key `connectorConfig`.
See [Aerospike Pulsar Outbound configuration](https://docs.aerospike.com/connect/pulsar/from-asdb/configuring) for details.

Update the `client-configuration`.`serviceUrl` configuration to point to your Pulsar cluster.

We recommend naming the file with the name of the connector cluster. For example if you want to name your connector cluster as
`as-pulsar-outbound`, create a file `as-pulsar-outbound-values.yaml`.
Once you have created this custom values file, deploy the connectors, using the following command.

### Create a new namespace
We recommend using `aerospike` namespace for the connector cluster. If the namespace does not exist run the following command:
```shell
kubectl create namespace aerospike
```

### Create secrets

You can create additional secrets, for confidential data like TLS certificates, that are mounted to the connector pods.
The connector can then be configured to use these secrets. See [examples/tls](examples/tls) for example.

### Deploy the connector cluster

```shell
# helm install --namespace <target namespace> <helm release name/cluster name> -f <path to custom values yaml> aerospike/aerospike-pulsar-outbound
helm install --namespace aerospike as-pulsar-outbound -f as-pulsar-outbound-values.yaml aerospike/aerospike-pulsar-outbound
```

Here `as-pulsar-outbound` is the release name for the connector cluster and also its cluster name.

On successful deployment you should see output similar to below:

```shell
NAME: as-pulsar-outbound
LAST DEPLOYED: Mon Oct 17 20:44:34 2022
NAMESPACE: aerospike
STATUS: deployed
REVISION: 1
NOTES:
1. Get the list of connector pods  by running the command:

kubectl get pods --namespace aerospike --selector=app=as-pulsar-outbound-aerospike-pulsar-outbound --no-headers -o custom-columns=":metadata.name"

2. Configure XDR to use each of these connector pods in the datacenter section

Use the following command to get the pod DNS names and port to use.

kubectl get pods --namespace aerospike --selector=app=as-pulsar-outbound-aerospike-pulsar-outbound --no-headers -o custom-columns=":metadata.name" \
    | sed -e "s/$/.as-pulsar-outbound-aerospike-pulsar-outbound 8080/g"

Visit https://docs.aerospike.com/connect/common/change-notification for details
```

## List pods for the connector
To list the pods for the connector run the following command:
```shell
# kubectl get pods --namespace aerospike --selector=app=<helm release name>-aerospike-pulsar-outbound
kubectl get pods --namespace aerospike --selector=app=as-pulsar-outbound-aerospike-pulsar-outbound
```

You should see output similar to the following:
```shell
NAME                                           READY   STATUS    RESTARTS   AGE
as-pulsar-outbound-aerospike-pulsar-outbound-0   1/1     Running   0          7m19s
as-pulsar-outbound-aerospike-pulsar-outbound-1   1/1     Running   0          7m40s
as-pulsar-outbound-aerospike-pulsar-outbound-2   1/1     Running   0          7m51s
```

## Configure XDR to ship to connector pods

Pod DNS names can be used directly if the Aerospike cluster is also running in the same Kubernetes cluster. 
To get the pod DNS names and ports to be added to XDR DC section, run the following command.

```shell
# kubectl get pods --namespace <target namespace> --selector=app=<helm release name>-aerospike-pulsar-outbound --no-headers -o custom-columns=":metadata.name" \
#    | sed -e "s/$/.<helm release name>-aerospike-pulsar-outbound <service port or service TLS port as desired>/g"
kubectl get pods --namespace aerospike --selector=app=as-pulsar-outbound-aerospike-pulsar-outbound --no-headers -o custom-columns=":metadata.name" \
    | sed -e "s/$/.as-pulsar-outbound-aerospike-pulsar-outbound 8080/g"
```

You should see output similar to the following
```shell
as-pulsar-outbound-aerospike-pulsar-outbound-0.as-pulsar-outbound-aerospike-pulsar-outbound 8080
as-pulsar-outbound-aerospike-pulsar-outbound-1.as-pulsar-outbound-aerospike-pulsar-outbound 8080
as-pulsar-outbound-aerospike-pulsar-outbound-2.as-pulsar-outbound-aerospike-pulsar-outbound 8080
```

If you are using [Aerospike Kubernetes Operator](https://docs.aerospike.com/connect/pulsar/from-asdb/configuring), 
see [clear text](examples/clear-text) and [tls](examples/tls) for reference.

## Get logs for all connector instances

```shell
# kubectl -n aerospike logs -f statefulset/<helm release name>-aerospike-pulsar-outbound
# Skip the -f flag to get a one time dump of the log
kubectl -n aerospike logs -f statefulset/as-pulsar-outbound-aerospike-pulsar-outbound
```

## Get logs for one connector pod

```shell
# kubectl -n aerospike logs -f <helm release name>-aerospike-pulsar-outbound-0
# Skip the -f flag to get a one time dump of the log
kubectl -n aerospike logs -f as-pulsar-outbound-aerospike-pulsar-outbound-0
```

## Updating connector configuration

Edit the `connectorConfig` section in the custom values file and save the changes.

Upgrade the connector deployment using the following command. 

```shell
#helm upgrade --namespace <target namespace> <helm release name> -f <path to custom values yaml file> aerospike/aerospike-pulsar-outbound
helm upgrade --namespace aerospike as-pulsar-outbound -f as-pulsar-outbound-values.yaml aerospike/aerospike-pulsar-outbound
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
#helm upgrade --namespace <target namespace> <helm release name> -f <path to custom values yaml file> aerospike/aerospike-pulsar-outbound
helm upgrade --namespace aerospike as-pulsar-outbound -f as-pulsar-outbound-values.yaml aerospike/aerospike-pulsar-outbound
```

Verify that the connectors have been scaled.
 - [List the pods](#list-pods-for-the-connector) and verify the count of connectors is as desired

**_NOTE:_** The changes might take some time to apply. If you do not see the desired count try again after some time. 
If connector pods are not being listed or report status as crashed see [troubleshooting](#troubleshooting).

### Update the XDR DC section
If you have scaled up add the new PODs to the XDR DC section else on scale down remove to additional pods DNS names. 

## Troubleshooting

### Connector pods not listed

Check for any error events on the StatefulSet created for the connectors.
```shell
# kubectl -n aerospike describe statefulset <helm release name>-aerospike-pulsar-outbound
kubectl -n aerospike describe statefulset as-pulsar-outbound-aerospike-pulsar-outbound
```

### Connector pods stuck in `init` or `pending` state

Check for any error events on the pod created for the connectors.
```shell
# kubectl -n aerospike describe pod <helm release name>-aerospike-pulsar-outbound-0
kubectl -n aerospike describe pod as-pulsar-outbound-aerospike-pulsar-outbound-0
```

The most likely reason is secret listed in `connectorSecrets` has not been created in the connector namespace.

### Connector pods in crashed state

The most likely reason is connector configuration provided in `connectorConfig` is invalid. 
Verify this by [viewing the connector logs](#get-logs-for-all-connector-instances), fix and [update](#updating-connector-configuration)
the connector configuration.
