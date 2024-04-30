# Aerospike Proximus

This Helm chart allows you to configure and run our official [Aerospike Proximus](https://hub.docker.com/repository/docker/aerospike/aerospike-proximus)
docker image on a Kubernetes cluster.

This helm chart sets up a `StatefulSet` for each proximus instance. We use a `StatefulSet` instead of a `Deployment`, to have stable DNS names for the  
deployed proximus pods.

## Prerequisites
- Kubernetes cluster
- Helm v3
- An Aerospike cluster that can connect to Pods in the Kubernetes cluster.
  The Aerospike cluster can be deployed in the same Kubernetes cluster using [Aerospike Kubernetes Operator](https://docs.aerospike.com/cloud/kubernetes/operator)
- Ability to deploy a LoadBalancer on K8s in case proximus app runs outside the Kubernetes cluster

## Adding the helm chart repository

Add the `aerospike` helm repository if not already done

```shell
helm repo add aerospike https://aerospike.github.io/helm-charts
```

## Supported configuration

### Configuration

| Parameter                 | Description                                                                                                                                                                          | Default                        |
|---------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------|
| `replicaCount`            | Configures the number Aerospike Proximus instance pods to run.                                                                                                                       | '1'                            |
| `image`                   | Configures Aerospike Proximus image repository, tag and pull policy.                                                                                                                 | see [values.yaml](values.yaml) |
| `imagePullSecrets`        | For Private docker registries, when authentication is needed.                                                                                                                        | see [values.yaml](values.yaml) |
| `proximusConfig`          | Proximus cluster configuration deployed to `/etc/aerospike-proximus/aerospike-proximus.yml`.                                                                                         | see [values.yaml](values.yaml) |
| `initContainers`          | List of initContainers added to each proximus pods for custom cluster behavior.                                                                                                      | `[]`                           |
| `serviceAccount`          | Service Account details like name and annotations.                                                                                                                                   | see [values.yaml](values.yaml) |
| `podAnnotations`          | Additional pod [annotations](https://kubernetes.io/docs/concepts/overview/working-with-objects/annotations/). Should be specified as a map of annotation names to annotation values. | `{}`                           |
| `podLabels`               | Additional pod [labels](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/). Should be specified as a map of label names to label values.                     | `{}`                           |
| `podSecurityContext`      | Pod [security context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)                                                                                   | `{}`                           |
| `securityContext`         | Container [security context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/#set-the-security-context-for-a-container)                                    | `{}`                           |
| `service`                 | Load-Balancer configuration for more details please refer to a Load-Balancer docs.                                                                                                   | `{}`                           |
| `resources`               | Resource [requests and limits](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) for the proximus pods.                                                | `{}`                           |
| `autoscaling`             | Enable the horizontal pod auto-scaler.                                                                                                                                               | see [values.yaml](values.yaml) |
| `extraVolumes`            | List of additional volumes to attach to the Proximus pod.                                                                                                                            | see [values.yaml](values.yaml) |
| `extraVolumeMounts`       | Extra volume mounts corresponding to the volumes added to `extraVolumes`.                                                                                                            | see [values.yaml](values.yaml) |
| `extraSecretVolumeMounts` | Extra secret volume mounts corresponding to the volumes added to `extraVolumes`.                                                                                                     | see [values.yaml](values.yaml) |
| `affinity`                | [Affinity](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#affinity-and-anti-affinity)  rules if any for the pods.                                          | `{}`                           |
| `nodeSelector`            | [Node selector](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#nodeselector)  for the pods.                                                                | `{}`                           |
| `tolerations`             | [Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)  for the pods.                                                                          | `{}`                           |

## Deploy the Proximus Cluster

We recommend creating a new `.yaml` for providing configuration values to the helm chart for deployment.
See the [examples](examples) folder for examples.

A sample values yaml file is shown below:

```yaml
replicaCount: 1

image:
  tag: "0.3.1"

proximusConfig:
  aerospike:
    metadata-namespace: "proximus-meta"
    seeds:
      - aerospike-cluster-0-0.aerospike-cluster.aerospike.svc.cluster.local:
          port: 3000
```

Here `replicaCount` is the count of Proximus pods that are deployed.
The proximus configuration is provided as yaml under the key `proximusConfig`.
[comment]: <> (Link to proximus docs should be added)
See [Aerospike Proximus configuration]() for details.

We recommend naming the file with the name of the Proximus cluster. For example if you want to name your Proximus cluster as
`as-proximus`, create a file `as-proximus-values.yaml`.
Once you have created this custom values file, deploy the Proximus cluster, using the following command.

### Create a new namespace
We recommend using `aerospike` namespace for the Proximus cluster. If the namespace does not exist run the following command:
```shell
kubectl create namespace aerospike
```

### Create secrets
Create the secret for aerospike using your Aerospike licence file
```shell
# kubectl --namespace <target namespace> create secret generic aerospike-proximus-secret --from-file=features.conf=<path to features conf file>
kubectl --namespace aerospike create secret generic aerospike-secret --from-file=features.conf=features.conf
```

### Deploy the Proximus cluster

```shell
# helm install --namespace <target namespace> <helm release name/cluster name> -f <path to custom values yaml> aerospike/aerospike-proximus
helm install --namespace aerospike as-proximus -f as-proximus-values.yaml aerospike/as-proximus
```

Here `as-proximus` is the release name for the proximus cluster and also its cluster name.

On successful deployment you should see output similar to below:

```shell
NAME: as-proximus
LAST DEPLOYED: Sun Mar 31 13:47:28 2024
NAMESPACE: aerospike
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
```

## List pods for the Proximus cluster
To list the pods for the Proximus cluster run the following command:
```shell
# kubectl get pods --namespace aerospike --selector=app=<helm release name>-aerospike-proximus
kubectl get pods --namespace aerospike --selector=app=as-proximus-aerospike-proximus
```

You should see output similar to the following:
```shell
NAME                               READY   STATUS    RESTARTS   AGE
as-proximus-aerospike-proximus-0   1/1     Running   0          2m32s
```

If you are using [Aerospike Kubernetes Operator](https://docs.aerospike.com/connect/pulsar/from-asdb/configuring),
see [quote-search](examples/quote-search) for reference.

## Get logs for all Proximus instances

```shell
# kubectl -n aerospike logs -f statefulset/<helm release name>-aerospike-proximus
# Skip the -f flag to get a one time dump of the log
kubectl -n aerospike logs -f statefulset/as-proximus-aerospike-proximus
```

## Get logs for one Proximus pod

```shell
# kubectl -n aerospike logs -f <helm release name>-aerospike-proximus-0
# Skip the -f flag to get a one time dump of the log
kubectl -n aerospike logs -f as-proximus-aerospike-proximus-0
```

## Updating Proximus configuration

Edit the `proximusConfig` section in the custom values file and save the changes.

Upgrade the Proximus deployment using the following command.

```shell
#helm upgrade --namespace <target namespace> <helm release name> -f <path to custom values yaml file> aerospike/aerospike-proximus
helm upgrade --namespace aerospike as-proximus -f as-proximus-values.yaml aerospike/aerospike-proximus
```

On successful execution of the command the Proximus pods will undergo a rolling restart and come up with the new configuration.

To verify the changes are applied
- [List the pods](#list-pods-for-the-proximus-cluster)
- [Verify the configuration in proximus logs](#get-logs-for-all-proximus-instances)

**_NOTE:_** The changes might take some time to apply. If you do not see the desired Proximus config try again after some time.

## Scaling up/down the Proximus instances

Edit the `replicaCount` to the desired Proximus instance count and upgrade the Proximus deployment using the following command.

```shell
#helm upgrade --namespace <target namespace> <helm release name> -f <path to custom values yaml file> aerospike/aerospike-proximus
helm upgrade --namespace aerospike as-proximus -f as-proximus-values.yaml aerospike/aerospike-proximus
```

Verify that the Proximus cluster have been scaled.
- [List the pods](#list-pods-for-the-proximus-cluster) and verify the count of Proximus instances is as desired

**_NOTE:_** The changes might take some time to apply. If you do not see the desired count try again after some time.
