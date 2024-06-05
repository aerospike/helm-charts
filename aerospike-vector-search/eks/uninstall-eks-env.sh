#!/bin/bash -e
WORKSPACE="$(git rev-parse --show-toplevel)"
REGION=""
PROFILE=""

if [ -z "$REGION" ]; then
    echo "set Region"
    exit 1
fi

helm uninstall quote-search --namespace aerospike
helm uninstall avs-eks --namespace aerospike
kubectl delete -f "$WORKSPACE/aerospike-vector-search/eks/config/gateway.yaml"
kubectl delete -f "$WORKSPACE/aerospike-vector-search/eks/config/virtual-service-vector-search.yaml"
helm uninstall istio-ingress --namespace istio-ingress
kubectl delete namespace istio-ingress
helm uninstall istiod --namespace istio-system
helm uninstall istio-base --namespace istio-system
kubectl delete namespace istio-system
kubectl delete -f "$WORKSPACE/aerospike-vector-search/examples/eks/aerospike.yaml"
kubectl delete -f https://raw.githubusercontent.com/aerospike/aerospike-kubernetes-operator/master/config/samples/storage/gce_ssd_storage_class.yaml
kubectl --namespace aerospike delete secret auth-secret
kubectl --namespace aerospike delete secret aerospike-secret
kubectl delete clusterrolebinding aerospike-cluster
kubectl --namespace aerospike delete serviceaccount aerospike-operator-controller-manager
kubectl delete namespace aerospike
kubectl delete -f https://operatorhub.io/install/aerospike-kubernetes-operator.yaml
kubectl delete clusterserviceversion "$(kubectl get clusterserviceversion -o=jsonpath='{.items[0].metadata.name}')"
kubectl delete crd aerospikeclusters.asdb.aerospike.com

eksctl delete iamserviceaccount \
--profile="$PROFILE" \
--region="$REGION" \
--cluster avs-eks-cluster \
--name ebs-csi-controller-sa \
--namespace kube-system

eksctl delete addon \
--profile="$PROFILE" \
--region="$REGION" \
--name aws-ebs-csi-driver \
--cluster avs-eks-cluster

eksctl delete cluster \
--profile="$PROFILE" \
--region="$REGION" \
--name avs-eks-cluster
