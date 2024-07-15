# Aerospike Vector Search

This Helm chart allows you to configure and run our official [Aerospike Vector Search](https://hub.docker.com/repository/docker/aerospike/aerospike-vector-search)
docker image on a Kubernetes cluster.

This helm chart sets up a `StatefulSet` for each AVS instance. We use a `StatefulSet` instead of a `Deployment`, to have stable DNS names for the  
deployed AVS pods.

## Prerequisites
- Kubernetes cluster
- Helm v3
- An Aerospike cluster that can connect to Pods in the Kubernetes cluster.
  The Aerospike cluster can be deployed in the same Kubernetes cluster using [Aerospike Kubernetes Operator](https://docs.aerospike.com/cloud/kubernetes/operator)
- Ability to deploy a LoadBalancer on K8s in case AVS app runs outside the Kubernetes cluster

## Adding the helm chart repository

Add the `aerospike` helm repository if not already done

```shell
helm repo add aerospike https://aerospike.github.io/helm-charts
```

## Supported configuration

### Configuration

| Parameter                     | Description                                                                                                                                                                          | Default                        |
|-------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------|
| `replicaCount`                | Configures the number AVS instance pods to run.                                                                                                                                      | '1'                            |
| `image`                       | Configures AVS image repository, tag and pull policy.                                                                                                                                | see [values.yaml](values.yaml) |
| `imagePullSecrets`            | For Private docker registries, when authentication is needed.                                                                                                                        | see [values.yaml](values.yaml) |
| `aerospikeVectorSearchConfig` | AVS cluster configuration deployed to `/etc/aerospike-vector-search/aerospike-vector-search.yml`.                                                                                              | see [values.yaml](values.yaml) |
| `initContainers`              | List of initContainers added to each AVS pods for custom cluster behavior.                                                                                                           | `[]`                           |
| `serviceAccount`              | Service Account details like name and annotations.                                                                                                                                   | see [values.yaml](values.yaml) |
| `podAnnotations`              | Additional pod [annotations](https://kubernetes.io/docs/concepts/overview/working-with-objects/annotations/). Should be specified as a map of annotation names to annotation values. | `{}`                           |
| `podLabels`                   | Additional pod [labels](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/). Should be specified as a map of label names to label values.                     | `{}`                           |
| `podSecurityContext`          | Pod [security context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)                                                                                   | `{}`                           |
| `securityContext`             | Container [security context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/#set-the-security-context-for-a-container)                                    | `{}`                           |
| `service`                     | Load-Balancer configuration for more details please refer to a Load-Balancer docs.                                                                                                   | `{}`                           |
| `resources`                   | Resource [requests and limits](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) for the AVS pods.                                                     | `{}`                           |
| `autoscaling`                 | Enable the horizontal pod auto-scaler.                                                                                                                                               | see [values.yaml](values.yaml) |
| `extraVolumes`                | List of additional volumes to attach to the AVS pod.                                                                                                                                 | see [values.yaml](values.yaml) |
| `extraVolumeMounts`           | Extra volume mounts corresponding to the volumes added to `extraVolumes`.                                                                                                            | see [values.yaml](values.yaml) |
| `extraSecretVolumeMounts`     | Extra secret volume mounts corresponding to the volumes added to `extraVolumes`.                                                                                                     | see [values.yaml](values.yaml) |
| `affinity`                    | [Affinity](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#affinity-and-anti-affinity)  rules if any for the pods.                                          | `{}`                           |
| `nodeSelector`                | [Node selector](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#nodeselector)  for the pods.                                                                | `{}`                           |
| `tolerations`                 | [Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)  for the pods.                                                                          | `{}`                           |

## Deploy the AVS Cluster

We recommend creating a new `.yaml` for providing configuration values to the helm chart for deployment.
See the [examples](examples) folder for examples.

A sample values yaml file is shown below:

```yaml
replicaCount: 1

image:
  tag: "0.9.0"

aerospikeVectorSearchConfig:
  aerospike:
    metadata-namespace: "avs-meta"
    seeds:
      - aerospike-cluster-0-0.aerospike-cluster.aerospike.svc.cluster.local:
          port: 3000
```

Here `replicaCount` is the count of AVS pods that are deployed.
The AVS configuration is provided as yaml under the key `aerospikeVectorSearchConfig`.
[comment]: <> (Link to AVS docs should be added)
See [Aerospike Vector Search configuration]() for details.

We recommend naming the file with the name of the AVS cluster. For example if you want to name your AVS cluster as
`avs`, create a file `avs-values.yaml`.
Once you have created this custom values file, deploy the avs cluster, using the following command.

### Create a new namespace
We recommend using `aerospike` namespace for the AVS cluster. If the namespace does not exist run the following command:
```shell
kubectl create namespace aerospike
```

### Create secrets
Create the secret for aerospike using your Aerospike licence file
```shell
# kubectl --namespace <target namespace> create secret generic avs-secret--from-file=features.conf=<path to features conf file>
kubectl --namespace aerospike create secret generic aerospike-secret --from-file=features.conf=features.conf
```

### Deploy the AVS cluster

```shell
# helm install --namespace <target namespace> <helm release name/cluster name> -f <path to custom values yaml> aerospike/aerospike-vector-search
helm install --namespace aerospike avs -f avs-values.yaml aerospike/aerospike-vector-search
```

Here `avs` is the release name for the AVS cluster and also its cluster name.

On successful deployment you should see output similar to below:

```shell
NAME: avs
LAST DEPLOYED: Tue May 21 15:55:39 2024
NAMESPACE: aerospike
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
```

## List pods for the AVS cluster
To list the pods for the AVS cluster run the following command:
```shell
# kubectl get pods --namespace aerospike --selector=app=<helm release name>-aerospike-vector-search
kubectl get pods --namespace aerospike --selector=app=avs-aerospike-vector-search
```

You should see output similar to the following:
```shell
NAME                            READY   STATUS    RESTARTS   AGE
avs-aerospike-vector-search-0   1/1     Running   0          9m52s
```

If you are using [Aerospike Kubernetes Operator](https://docs.aerospike.com/connect/pulsar/from-asdb/configuring),
see [quote-search](examples/kind) for reference.

## Get logs for all AVS instances

```shell
# kubectl -n aerospike logs -f statefulset/<helm release name>-aerospike-vector-search
# Skip the -f flag to get a one time dump of the log
kubectl -n aerospike logs -f statefulsets/avs-aerospike-vector-search
```

## Get logs for one AVS pod

```shell
# kubectl -n aerospike logs -f <helm release name>-aerospike-vector-search-0
# Skip the -f flag to get a one time dump of the log
kubectl -n aerospike logs -f avs-aerospike-vector-search-0
```

## Updating AVS configuration

Edit the `aerospikeVectorSearchConfig` section in the custom values file and save the changes.

Upgrade the AVS deployment using the following command.

```shell
#helm upgrade --namespace <target namespace> <helm release name> -f <path to custom values yaml file> aerospike/aerospike-vector-search
helm upgrade --namespace aerospike avs -f avs-values.yaml aerospike/aerospike-vector-search
```

On successful execution of the command the AVS pods will undergo a rolling restart and come up with the new configuration.

To verify the changes are applied
- [List the pods](#list-pods-for-the-avs-cluster)
- [Verify the configuration in AVS logs](#get-logs-for-all-avs-instances)

**_NOTE:_** The changes might take some time to apply. If you do not see the desired AVS config try again after some time.

## Scaling up/down the AVS instances

Edit the `replicaCount` to the desired AVS instance count and upgrade the AVS deployment using the following command.

```shell
#helm upgrade --namespace <target namespace> <helm release name> -f <path to custom values yaml file> aerospike/aerospike-vector-search
helm upgrade --namespace aerospike avs-f avs-values.yaml aerospike/aerospike-vector-search
```

Verify that the AVS cluster have been scaled.
- [List the pods](#list-pods-for-the-avs-cluster) and verify the count of AVS instances is as desired

**_NOTE:_** The changes might take some time to apply. If you do not see the desired count try again after some time.
