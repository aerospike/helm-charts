#!/bin/bash -e
WORKSPACE="$(git rev-parse --show-toplevel)"
REGION=""
PROFILE=""

if [ -z "$REGION" ]; then
    echo "Set Region"
    exit 1
fi

if [ ! -f "$WORKSPACE/aerospike-vector-search/eks/config/features.conf" ]; then
  echo "features.conf Not found"
  exit 1
fi

echo "Install EKS"

eksctl create cluster \
--profile="$PROFILE" \
--region="$REGION" \
--name=avs-eks-cluster \
--nodes=3 \
--node-type=t3.xlarge \
--with-oidc \
--set-kubeconfig-context

eksctl create iamserviceaccount \
--profile="$PROFILE" \
--region="$REGION" \
--name ebs-csi-controller-sa \
--namespace kube-system \
--cluster avs-eks-cluster \
--role-name AmazonEKS_EBS_CSI_DriverRole \
--role-only \
--attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
--approve

eksctl create addon \
--profile="$PROFILE" \
--region="$REGION" \
--name aws-ebs-csi-driver \
--cluster avs-eks-cluster \
--service-account-role-arn arn:aws:iam::"$(aws sts get-caller-identity \
--query "Account" \
--output text)":role/AmazonEKS_EBS_CSI_DriverRole \
--force

sleep 60
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
--from-file=features.conf="$WORKSPACE/aerospike-vector-search/eks/config/features.conf"
kubectl --namespace aerospike create secret generic auth-secret --from-literal=password='admin123'

echo "Add Storage Class"
kubectl apply -f https://raw.githubusercontent.com/aerospike/aerospike-kubernetes-operator/master/config/samples/storage/eks_ssd_storage_class.yaml

sleep 5
echo "Deploy Aerospike Cluster"
kubectl apply -f "$WORKSPACE/aerospike-vector-search/examples/eks/aerospike.yaml"

sleep 5
echo "Waiting for Aerospike Cluster"
while true; do
  if  kubectl --namespace aerospike get pods --selector=statefulset.kubernetes.io/pod-name &> /dev/null; then
    kubectl --namespace aerospike wait pods \
    --selector=statefulset.kubernetes.io/pod-name --for=condition=ready --timeout=180s
    break
  fi
done

echo "Deploying Istio"
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update

helm install istio-base istio/base --namespace istio-system --set defaultRevision=default --create-namespace --wait
helm install istiod istio/istiod --namespace istio-system --create-namespace --wait
helm install istio-ingress istio/gateway \
--values "$WORKSPACE/aerospike-vector-search/eks/config/istio-ingressgateway-values.yaml" \
--namespace istio-ingress \
--create-namespace \
--wait

kubectl apply -f "$WORKSPACE/aerospike-vector-search/eks/config/gateway.yaml"
kubectl apply -f "$WORKSPACE/aerospike-vector-search/eks/config/virtual-service-vector-search.yaml"

echo "Deploy AVS"
helm install avs-eks "$WORKSPACE/aerospike-vector-search" \
--values "$WORKSPACE/aerospike-vector-search/examples/eks/avs-eks-values.yaml" --namespace aerospike --wait

echo "Deploying Quote-Search"

git clone \
--depth 1 \
--branch main \
--no-checkout https://github.com/aerospike/aerospike-vector-search-examples.git
cd aerospike-vector-search-examples
git sparse-checkout set kubernetes/helm/quote-semantic-search
git checkout main
cd -

helm install quote-search "$PWD/aerospike-vector-search-examples/kubernetes/helm/quote-semantic-search" \
--values "$WORKSPACE/aerospike-vector-search/eks/config/quote-search-eks-values.yaml" \
--namespace aerospike \
--wait \
--timeout 7m0s
