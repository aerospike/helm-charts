# Aerospike JMS Inbound Connector

This Helm chart allows you to configure and run our official [Aerospike JMS Inbound Connector](https://hub.docker.com/repository/docker/aerospike/aerospike-jms-inbound) 
docker image on a Kubernetes cluster.

This helm chart sets up a `Deployment` for JMS inbound connector deployment. 

**_NOTE:_** The helm chart appends `-aerospike-jms-inbound` suffix to all created Kubernetes resources to prevent name clashes with other applications.

## Prerequisites
- Kubernetes cluster
- Helm v3
- A JMS cluster with brokers reachable from the pods in the Kubernetes cluster
- An Aerospike cluster reachable from the connectors pods in the Kubernetes cluster.
  The Aerospike cluster can be deployed in the same Kubernetes cluster using [Aerospike
  Kubernetes Operator](https://docs.aerospike.com/cloud/kubernetes/operator)

## Adding the helm chart repository

Add the `aerospike` helm repository if not already done

```shell
helm repo add aerospike https://aerospike.github.io/helm-charts
```

### Supported configuration

### Configuration

| Parameter            | Description                                                                                                                                                                          | Default                        |
|----------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------|
| `replicaCount`       | Configures the number Aerospike JMS connector pods to run.                                                                                                                           | '1'                            |
| `image`              | Configures Aerospike JMS connector image repository, tag and pull policy.                                                                                                            | see [values.yaml](values.yaml) |
| `connectorConfig`    | Connector configuration deployed to `/etc/aerospike-jms-inbound/aerospike-jms-inbound.yml`.                                                                                          | see [values.yaml](values.yaml) |
| `connectorSecrets`   | List of secrets mounted to `/etc/aerospike-jms-inbound/secrets` for each connector pod.                                                                                              | `[]`                           |
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
  tag: "3.0.6"

connectorConfig:
  # Optional HTTP Server configuration to expose Manage API and Prometheus metrics
  service:
    manage:
      port: 8081

  # JMS sources to consume messages from.
  queues:
    MyJmsQueue:
      aerospike-operation:
        type: write
      parsing:
        format: json
      mapping:
        bins:
          type: multi-bins
          all-value-fields: true
        key-field:
          source: value-field
          field-name: key
        namespace:
          mode: static
          value: test

  # topics: {}

  # The connection properties to the JMS message broker.
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

  # The Aerospike cluster connection properties.
  aerospike:
    seeds:
      - aerocluster.aerospike: # Aerospike Headless Service name or seed node address.
          port: 3000

  # The logging properties.
  logging:
    enable-console-logging: true
```

Here `replicaCount` is the count of connectors pods that are deployed. 
The connector configuration is provided as yaml under the key `connectorConfig`.
See [Aerospike JMS Inbound configuration](https://docs.aerospike.com/connect/jms/to-asdb/configuring) for details.

Update the `jms` configuration to point to you JMS cluster endpoints and update `queues` and `topics` to point to the JMS queues and topics you want to consume messages from.
Also, update the `aerospike` configuration to point to your Aerospike cluster.

We recommend naming the file with the name of the connector cluster. For example if you want to name your connector cluster as
`as-jms-inbound`, create a file `as-jms-inbound-values.yaml`.
Once you have created this custom values file, deploy the connectors, using the following command.

## Configure connector to write to Aerospike cluster

Aerospike cluster Pod DNS names or service name can be used directly if the Aerospike cluster is also running in the same Kubernetes cluster.

To get the service name and port to be used for `aerospike` section in the connectorConfig, run the following command.

```shell
# kubectl get svc --namespace <target namespace> <AerospikeCluster custom-resource name> --no-headers -o custom-columns=":metadata.name,:spec.ports[].port" \
#    | sed -e "s/<AerospikeCluster custom-resource name>/<AerospikeCluster custom-resource name>.<target namespace>/g"
kubectl get svc --namespace aerospike aerocluster --no-headers -o custom-columns=":metadata.name,:spec.ports[].port" \
    | sed -e "s/aerocluster/aerocluster.aerospike/g"
```

You should see output similar to the following
```shell
aerocluster.aerospike 3000
```

OR 

To get the pod DNS names and ports to be used for `aerospike` section in the connectorConfig, run the following command.

```shell
# kubectl get pods --namespace <target namespace> --selector=aerospike.com/cr=<AerospikeCluster custom-resource name> --no-headers -o custom-columns=":metadata.name" \
#    | sed -e "s/$/.<target namespace> <Aerospike cluster service port or service TLS port as desired>/g"
kubectl get pods --namespace aerospike --selector=aerospike.com/cr=aerocluster --no-headers -o custom-columns=":metadata.name" \
    | sed -e "s/$/.aerospike 3000/g"
```

You should see output similar to the following
```shell
aerocluster-0-0.aerospike 3000
aerocluster-0-1.aerospike 3000
```

If you are using [Aerospike Kubernetes Operator](https://docs.aerospike.com/connect/jms/to-asdb/configuring),
see [clear text](examples/clear-text) and [tls](examples/tls) for reference.

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
# helm install --namespace <target namespace> <helm release name/cluster name> -f <path to custom values yaml> aerospike/aerospike-jms-inbound
helm install --namespace aerospike as-jms-inbound -f as-jms-inbound-values.yaml aerospike/aerospike-jms-inbound
```

Here `as-jms-inbound` is the release name for the connector cluster and also its cluster name.

On successful deployment you should see output similar to below:

```shell
AME: as-jms-inbound
LAST DEPLOYED: Mon Oct 17 20:44:34 2022
NAMESPACE: aerospike
STATUS: deployed
REVISION: 1
NOTES:
1. Get the list of connector pods  by running the command:

kubectl get pods --namespace aerospike --selector=app=as-jms-inbound-aerospike-jms-inbound --no-headers -o custom-columns=":metadata.name"
```

## List pods for the connector
To list the pods for the connector run the following command:
```shell
# kubectl get pods --namespace aerospike --selector=app=<helm release name>-aerospike-jms-inbound
kubectl get pods --namespace aerospike --selector=app=as-jms-inbound-aerospike-jms-inbound
```

You should see output similar to the following:
```shell
NAME                                                    READY   STATUS    RESTARTS   AGE
as-jms-inbound-aerospike-jms-inbound-5c448c9945-7hgkc   1/1     Running   0          37m
as-jms-inbound-aerospike-jms-inbound-5c448c9945-jxtsh   1/1     Running   0          38m
as-jms-inbound-aerospike-jms-inbound-5c448c9945-nh2gd   1/1     Running   0          38m
```

## Get logs for all connector instances

```shell
# kubectl -n aerospike logs -f deployment/<helm release name>-aerospike-jms-inbound
# Skip the -f flag to get a one time dump of the log
kubectl -n aerospike logs -f deployment/as-jms-inbound-aerospike-jms-inbound
```

## Get logs for one connector pod

```shell
# kubectl -n aerospike logs -f <pod-name>
# Skip the -f flag to get a one time dump of the log
kubectl -n aerospike logs -f as-jms-inbound-aerospike-jms-inbound-5c448c9945-7hgkc
```

## Updating connector configuration

Edit the `connectorConfig` section in the custom values file and save the changes.

Upgrade the connector deployment using the following command. 

```shell
#helm upgrade --namespace <target namespace> <helm release name> -f <path to custom values yaml file> aerospike/aerospike-jms-inbound
helm upgrade --namespace aerospike as-jms-inbound -f as-jms-inbound-values.yaml aerospike/aerospike-jms-inbound
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
#helm upgrade --namespace <target namespace> <helm release name> -f <path to custom values yaml file> aerospike/aerospike-jms-inbound
helm upgrade --namespace aerospike as-jms-inbound -f as-jms-inbound-values.yaml aerospike/aerospike-jms-inbound
```

Verify that the connectors have been scaled.
 - [List the pods](#list-pods-for-the-connector) and verify the count of connectors is as desired

**_NOTE:_** The changes might take some time to apply. If you do not see the desired count try again after some time. 
If connector pods are not being listed or report status as crashed see [troubleshooting](#troubleshooting).

## Troubleshooting

### Connector pods not listed

Check for any error events on the StatefulSet created for the connectors.
```shell
# kubectl -n aerospike describe deployment <helm release name>-aerospike-jms-inbound
kubectl -n aerospike describe deployment as-jms-inbound-aerospike-jms-inbound
```

### Connector pods stuck in `init` or `pending` state

Check for any error events on the pod created for the connectors.
```shell
# kubectl -n aerospike describe pod <pod-name>
kubectl -n aerospike describe pod as-jms-inbound-aerospike-jms-inbound-5c448c9945-7hgkc
```

The most likely reason is secret listed in `connectorSecrets` has not been created in the connector namespace.

### Connector pods in crashed state

The most likely reason is connector configuration provided in `connectorConfig` is invalid. 
Verify this by [viewing the connector logs](#get-logs-for-all-connector-instances), fix and [update](#updating-connector-configuration)
the connector configuration.
