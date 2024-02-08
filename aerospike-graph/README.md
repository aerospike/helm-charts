# Deploying Aerospike Graph Service with Kubernetes and Helm
If you're just getting started with trying out [Aerospike Graph Service](https://aerospike.com/docs/graph)
(AGS), you may wish to start with a local deployment for testing purposes. When you're ready to
deploy AGS in a production environment, you'll probably want to use
containerization and orchestration tools. This guide is intended to illustrate deploying AGS
with [Kubernetes](https://kubernetes.io/) and [Helm](https://helm.sh/).
## Prerequisites
- A running instance of [Aerospike Database Server](https://aerospike.com/docs/database)
  with an accessible IP address and port.
- [Kubernetes](https://kubernetes.io/) and [Helm](https://helm.sh/).
- The scripts in the `helm/graphservice` directory.
## Usage
The arguments you pass to the `helm` command depend on your Aerospike Server
network and namespace configuration. The prototype form of the command is as
follows:
```bash noCopy
$ helm [INSTALL|UPGRADE] [POD-NAME] helm/graphservice \
    --set 'env[0].name=[GRAPH-CONFIG-NAME]' \
    --set 'env[1].name=[GRAPH-CONFIG-NAME]' \
    ...
```
All the [configuration options](https://aerospike.com/docs/graph/configuring/options)
listed in the Graph documentation are available to pass in as environment variables.
You can also edit the file `helm/graphservice/values.yaml` to specify environment
variables.
## Example commands
The following example command:
- Creates a Kubernetes pod named `test-pod`.
- Specifies `10.32.32.77:3000` as the IP address and port of the Aerospike
  database server.
- Specifies `test` as the namespace to use on the Aerospike database.
```bash
$ helm install test-pod helm/graphservice \
  --set 'env[0].name=aerospike.client.host' \
  --set 'env[0].value=10.32.32.77:3000' \
  --set 'env[1].name=aerospike.client.namespace' \
  --set 'env[1].value=test'
```
If the command is successful, output similar to the following appears:
```ascii
NAME: aerospike-graph-pod
LAST DEPLOYED: Mon Sep 25 19:14:38 2023
NAMESPACE: default
STATUS: deployed
REVISION: 1
NOTES:
1. Get the application URL by running these commands:
  http://graph-service.aerospike.demo/gremlin
```
You can use all the standard Kubernetes commands to inspect and alter
your pods.
```ascii
$ kubectl get pods
NAME                                                READY   STATUS    RESTARTS   AGE
aerospike-graph-pod-graphservice-6d8c8b77fd-zjfpg   1/1     Running   0          31s
```
Once your AGS instance is up and running, you can connect to it over
the [Gremlin websocket port](https://tinkerpop.apache.org/docs/3.6.4/reference/#connecting-gremlin-server).
For more information about using the Gremlin console with AGS, see
[Basic Graph Usage](https://aerospike.com/docs/graph/getting-started/basic-usage).
You can get networking information about your active pods with the `get services` command:
```ascii
$ kubectl get services
NAME                               TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)          AGE
aerospike-graph-pod-graphservice   LoadBalancer   10.107.38.223   10.107.38.223   8182:32330/TCP   5m22s
```
You can alter your pod configuration with the `helm upgrade command`. Use the `replicaCount`
argument to adjust the number of running pods:
```ascii
$ helm upgrade test-pod helm/graphservice \
  --set 'env[0].name=aerospike.client.host' \
  --set 'env[0].value=10.32.32.77:3000' \
  --set 'env[1].name=aerospike.client.namespace' \
  --set 'env[1].value=test' \
  --set replicaCount=3
...
$ kubectl get pods -w
NAME                                     READY   STATUS    RESTARTS   AGE
test-pod-graphservice-697dcdfcb8-sb9xt   1/1     Running   0          6s
test-pod-graphservice-697dcdfcb8-sfcmr   1/1     Running   0          6s
test-pod-graphservice-697dcdfcb8-v2x5z   1/1     Running   0          6s
```
## Configuring the `values.yaml` file
You can set AGS configuration options in the `values.yaml` file. At the
bottom of the file, there are environment variables which are commented
out by default. You can uncomment the existing variables and add others
as needed. For a complete list of AGS configuration options, see the
[documentation](https://aerospike.com/docs/graph/configuring/options).
For more information about the `values.yaml` file, see the
[Helm documentation](https://helm.sh/docs/chart_template_guide/values_files/).
