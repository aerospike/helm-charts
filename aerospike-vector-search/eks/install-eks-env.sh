#!/bin/bash -e
WORKSPACE="$(git rev-parse --show-toplevel)"
REGION=""

if [ -z "$REGION" ]; then
    echo "Set Region"
    exit 1
fi

if [ ! -f "$WORKSPACE/aerospike-proximus/eks/config/features.conf" ]; then
  echo "features.conf Not found"
  exit 1
fi

eksctl create cluster \
--region="$REGION" \
--name=proximus-eks-cluster \
--nodes=3 \
--node-type=t3.xlarge \
--with-oidc \
--set-kubeconfig-context

eksctl create iamserviceaccount \
--region="$REGION" \
--name ebs-csi-controller-sa \
--namespace kube-system \
--cluster proximus-eks-cluster \
--role-name AmazonEKS_EBS_CSI_DriverRole \
--role-only \
--attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
--approve

eksctl create addon \
--region="$REGION" \
--name aws-ebs-csi-driver \
--cluster proximus-eks-cluster \
--service-account-role-arn arn:aws:iam::"$(aws sts get-caller-identity \
--query "Account" \
--output text)":role/AmazonEKS_EBS_CSI_DriverRole \
--force

sleep 30
echo "Deploying AKO"
curl -sL https://github.com/operator-framework/operator-lifecycle-manager/releases/download/v0.25.0/install.sh \
| bash -s v0.25.0
kubectl create -f https://operatorhub.io/install/aerospike-kubernetes-operator.yaml
echo "Waiting for AKO"
while true; do
  if kubectl --namespace operators get deployment/aerospike-operator-controller-manager &> /dev/null; then
    kubectl --namespace operators wait \
    --for=condition=available --timeout=180s deployment/aerospike-operator-controller-manager
    break
  fi
done

echo "Grant permissions to the target namespace"
kubectl create namespace aerospike
kubectl --namespace aerospike create serviceaccount aerospike-operator-controller-manager
kubectl create clusterrolebinding aerospike-cluster \
--clusterrole=aerospike-cluster --serviceaccount=aerospike:aerospike-operator-controller-manager

echo "Set Secrets for Aerospike Cluster"
kubectl --namespace aerospike create secret generic aerospike-secret \
--from-file=features.conf="$WORKSPACE/aerospike-proximus/eks/config/features.conf"
kubectl --namespace aerospike create secret generic auth-secret --from-literal=password='admin123'

echo "Add Storage Class"
kubectl apply -f https://raw.githubusercontent.com/aerospike/aerospike-kubernetes-operator/master/config/samples/storage/eks_ssd_storage_class.yaml

sleep 5
echo "Deploy Aerospike Cluster"
kubectl apply -f "$WORKSPACE/aerospike-proximus/examples/eks/aerospike.yaml"

sleep 5
echo "Waiting for Aerospike Cluster"
while true; do
  if  kubectl --namespace aerospike get pods --selector=statefulset.kubernetes.io/pod-name &> /dev/null; then
    kubectl --namespace aerospike wait pods \
    --selector=statefulset.kubernetes.io/pod-name --for=condition=ready --timeout=180s
    break
  fi
done

sleep 30
echo "Deploy Proximus"
helm install as-proximus-eks "$WORKSPACE/aerospike-proximus" \
--values "$WORKSPACE/aerospike-proximus/examples/eks/as-proximus-eks-values.yaml" --namespace aerospike --wait
