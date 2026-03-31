# Aerospike Proxy

This helm chart sets up a `Deployment` for Aerospike Proxy.


## Prerequisites
- Kubernetes cluster
- Helm v3
- An Aerospike cluster that can connect to Pods in the Kubernetes cluster.
  The Aerospike cluster can be deployed in the same Kubernetes cluster using [Aerospike Kubernetes Operator](https://docs.aerospike.com/cloud/kubernetes/operator)

## Adding the helm chart repository

Add the `aerospike` helm repository if not already done

```shell
helm repo add aerospike https://aerospike.github.io/helm-charts
```

## Supported configuration

### Configuration

| Parameter                 | Description                                                                                                                                                                          | Default                        |
|---------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------|
| `replicaCount`            | Configures the number Aerospike Backup Service instance pods to run.                                                                                                                 | '1'                            |
| `image`                   | Configures Aerospike Aerospike Backup Service image repository, tag and pull policy.                                                                                                 | see [values.yaml](values.yaml) |
| `imagePullSecrets`        | For Private docker registries, when authentication is needed.                                                                                                                        | see [values.yaml](values.yaml) |
| `proxyConfig`             | Proxy configuration deployed to `/etc/aerospike-proxy/aerospike-proxy.yml`.                                                                                                          | see [values.yaml](values.yaml) |
| `serviceAccount`          | Service Account details like name and annotations.                                                                                                                                   | see [values.yaml](values.yaml) |
| `podAnnotations`          | Additional pod [annotations](https://kubernetes.io/docs/concepts/overview/working-with-objects/annotations/). Should be specified as a map of annotation names to annotation values. | `{}`                           |
| `podLabels`               | Additional pod [labels](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/). Should be specified as a map of label names to label values.                     | `{}`                           |
| `podSecurityContext`      | Pod [security context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)                                                                                   | `{}`                           |
| `securityContext`         | Container [security context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/#set-the-security-context-for-a-container)                                    | `{}`                           |
| `resources`               | Resource [requests and limits](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) for the proxy service pods.                                           | `{}`                           |
| `autoscaling`             | Enable the horizontal pod auto-scaler.                                                                                                                                               | see [values.yaml](values.yaml) |
| `volumes`                 | List of additional volumes to attach to the proxy pod.                                                                                                                               | see [values.yaml](values.yaml) |
| `extraVolumeMounts`       | Extra volume mounts corresponding to the volumes added to `extraVolumes`.                                                                                                            | see [values.yaml](values.yaml) |
| `extraSecretVolumeMounts` | Extra secret volume mounts corresponding to the volumes added to `extraVolumes`.                                                                                                     | see [values.yaml](values.yaml) |
| `affinity`                | [Affinity](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#affinity-and-anti-affinity)  rules if any for the pods.                                          | `{}`                           |
| `nodeSelector`            | [Node selector](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#nodeselector)  for the pods.                                                                | `{}`                           |
| `tolerations`             | [Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)  for the pods.                                                                          | `{}`                           |



## Deploy the Aerospike-Proxy

We recommend creating a new `.yaml` for providing configuration values to the helm chart for deployment.
See the [examples](examples) folder for examples.


We recommend naming the file with the name of the Aerospike Proxy service. For example if you want to name your service as
`aerospike-proxy`, create a file `aerospike-proxy-values.yaml`.
Once you have created this custom values file, deploy the Aerospike Proxy, using the following commands.

### Create a new namespace
We recommend using `aerospike` namespace for the Aerospike Proxy. If the namespace does not exist run the following command:
```shell
kubectl create namespace aerospike
```

### Create secrets

You can create additional secrets, for confidential data like TLS certificates or Aerospike cluster password these are mounted to the proxy pods as files.
The Aerospike Proxy service can then be configured to use these secrets.

### Deploy Aerospike Proxy

```shell
# helm install --namespace <target namespace> <helm release name/cluster name> -f <path to custom values yaml> aerospike/aerospike-backup-service
helm install proxy "aerospike/aerospike-proxy" \
--namespace aerospike \
--values aerospike-proxy-values.yaml \
--create-namespace \
--wait
```

Here `proxy` is the release name for the Aerospike Proxy service.

On successful deployment you should see output similar to below:

```shell
NAME: proxy
LAST DEPLOYED: Sun Jul 21 11:36:42 2024
NAMESPACE: aerospike
STATUS: deployed
REVISION: 1
NOTES:
1. Get the application URL by running these commands:
  export POD_NAME=$(kubectl get pods --namespace aerospike -l "app.kubernetes.io/name=aerospike-proxy,app.kubernetes.io/instance=proxy" -o jsonpath="{.items[0].metadata.name}")
  export CONTAINER_PORT=$(kubectl get pod --namespace aerospike $POD_NAME -o jsonpath="{.spec.containers[0].ports[0].containerPort}")
  echo "Visit http://127.0.0.1:8080 to use your application"
  kubectl --namespace aerospike port-forward $POD_NAME 8080:$CONTAINER_PORT
```

## List pods for the Aerospike Proxy
To list the pods for the Aerospike Proxy service run the following command:
```shell
# kubectl get pods --namespace aerospike --selector=app=<helm release name>-aerospike-proxy
kubectl get pods --namespace aerospike --selector=app=proxy-aerospike-proxy
```

You should see output similar to the following:
```shell
NAME                                    READY   STATUS    RESTARTS   AGE
proxy-aerospike-proxy-f49cb67f4-llw4h   1/1     Running   0          9m3s
```

## Get logs for all Aerospike Proxy instances

```shell
# kubectl -n aerospike logs -f deployment/<helm release name>-aerospike-proxy
# Skip the -f flag to get a one time dump of the log
kubectl -n aerospike logs -f deployment/proxy-aerospike-proxy
```

## Get logs for one Aerospike Proxy pod

```shell
# kubectl -n aerospike logs -f <helm release name>-aerospike-proxy-<random-hash>
# Skip the -f flag to get a one time dump of the log
kubectl -n aerospike logs -f proxy-aerospike-proxy-f49cb67f4-llw4h
```

## Updating Aerospike Proxy configuration

Edit the `proxyConfig` section in the custom values file and save the changes.

Upgrade the Aerospike Proxy deployment using the following command.

```shell
#helm upgrade --namespace <target namespace> <helm release name> -f <path to custom values yaml file> aerospike/aerospike-proxy
helm upgrade --namespace aerospike proxy -f aerospike-proxy-values.yaml aerospike/aerospike-proxy
```

On successful execution of the command the Aerospike Proxy service pods will undergo a rolling restart and come up with the new configuration.

To verify the changes are applied
- [List the pods](#list-pods-for-the-aerospike-proxy)
- [Verify the configuration in Aerospike Proxy logs](#get-logs-for-all-aerospike-proxy-instances)

**_NOTE:_** The changes might take some time to apply. If you do not see the desired Aerospike Proxy config try again after some time.
If proxy pods are not being listed or report status as crashed see [troubleshooting](#troubleshooting).

## Scaling up/down the Aerospike Proxy

Edit the `replicaCount` to the desired Aerospike Proxy service count and upgrade the proxy deployment using the following command.

```shell
#helm upgrade --namespace <target namespace> <helm release name> -f <path to custom values yaml file> aerospike/aerospike-proxy
helm upgrade --namespace aerospike proxy -f aerospike-proxy-values.yaml aerospike/aerospike-proxy
```

Verify that the Aerospike Proxy have been scaled.
- [List the pods](#list-pods-for-the-aerospike-proxy) and verify the count of proxy instances is as desired

**_NOTE:_** The changes might take some time to apply. If you do not see the desired count try again after some time.
If proxy pods are not being listed or report status as crashed see [troubleshooting](#troubleshooting).

## Troubleshooting

### Aerospike Proxy pods not listed

Check for any error events on the Deployment created for the Aerospike Proxy.
```shell
# kubectl -n aerospike describe deployment <helm release name>-aerospike-proxy
kubectl -n aerospike describe deployment proxy-aerospike-proxy
```

### Aerospike Proxy pods stuck in `init` or `pending` state

Check for any error events on the pod created for the Aerospike Proxy service.
```shell
# kubectl -n aerospike describe pod <helm release name>-aerospike-proxy--<random-hash>
kubectl -n aerospike describe pod proxy-aerospike-proxy-f49cb67f4-llw4h
```

The most likely reason is secret listed in `proxyConfig` has not been created in the proxy namespace.

### Aerospike Proxy pods in crashed state

The most likely reason is proxy configuration provided in `proxyConfig` is invalid.
Verify this by [viewing the proxy logs](#get-logs-for-all-aerospike-proxy-instances), fix and [update](#updating-aerospike-proxy-configuration)
the Aerospike Proxy configuration.
