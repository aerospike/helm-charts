#!/bin/bash -e
WORKSPACE="$(git rev-parse --show-toplevel)"
REGION=""

if [ -z "$REGION" ]; then
    echo "set Region"
    exit 1
fi

SG_ID="$(aws ec2 describe-security-groups \
--region "$REGION" \
--filters "Name=group-name,Values=proximus-quote-search-sg" \
--query "SecurityGroups[*].GroupId" \
--output text)"

INSTANCE_ID="$(aws ec2 describe-instances \
--region "$REGION" \
--filters "Name=instance-state-name,Values=running" "Name=tag:Name,Values=proximus-quote-search" \
--query "Reservations[*].Instances[*].InstanceId" \
--output text)"

aws ec2 terminate-instances \
--region "$REGION" \
--instance-ids "$INSTANCE_ID"

aws ec2 wait instance-terminated \
--region "$REGION" \
--instance-ids "$INSTANCE_ID"

aws ec2 delete-key-pair \
--region "$REGION" \
--key-name proximus-quote-search-key

rm -f "$WORKSPACE/aerospike-proximus/eks/proximus-quote-search.pem"
aws ec2 delete-security-group \
--region "$REGION" \
--group-id "$SG_ID"

kubectl delete -f "$WORKSPACE/aerospike-proximus/examples/eks/aerospike.yaml"
kubectl delete -f https://raw.githubusercontent.com/aerospike/aerospike-kubernetes-operator/master/config/samples/storage/eks_ssd_storage_class.yaml
helm uninstall as-proximus-eks -n aerospike
kubectl --namespace aerospike delete secret auth-secret
kubectl --namespace aerospike delete secret aerospike-secret
kubectl delete clusterrolebinding aerospike-cluster
kubectl --namespace aerospike delete serviceaccount aerospike-operator-controller-manager
kubectl delete namespace aerospike
kubectl delete -f https://operatorhub.io/install/aerospike-kubernetes-operator.yaml
kubectl delete clusterserviceversion "$(kubectl get clusterserviceversion -o=jsonpath='{.items[0].metadata.name}')"
kubectl delete crd aerospikeclusters.asdb.aerospike.com

eksctl delete iamserviceaccount \
--region="$REGION" \
--cluster proximus-eks-cluster \
--name ebs-csi-controller-sa \
--namespace kube-system

eksctl delete addon \
--region="$REGION" \
--name aws-ebs-csi-driver \
--cluster proximus-eks-cluster

eksctl delete cluster \
--region="$REGION" \
--name proximus-eks-cluster
