#!/bin/bash -e

WORKSPACE="$(git rev-parse --show-toplevel)"
if helm list -n aerospike --all  --output json | jq -r  '.[].name' | grep -q "proximus"; then
  helm delete proximus --namespace aerospike
  kubectl --namespace aerospike delete secret aerospike-proximus-secret
  fi

#kubectl delete -f "$WORKSPACE/aerospike-proximus/local-env/config/metallb-config.yaml"
#kubectl delete -f https://raw.githubusercontent.com/metallb/metallb/v0.13.7/config/manifests/metallb-native.yaml
##kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
##kubectl delete -f "$WORKSPACE/aerospike-proximus/local-env/config/aerospike-cluster.yaml"
#kubectl --namespace aerospike delete secret regcred
#kubectl --namespace aerospike delete secret auth-secret
#kubectl --namespace aerospike delete secret aerospike-secret
#kubectl delete clusterrolebinding aerospike-cluster
#kubectl --namespace aerospike delete serviceaccount aerospike-operator-controller-manager
#kubectl delete namespace aerospike
#kubectl delete -f https://operatorhub.io/install/aerospike-kubernetes-operator.yaml
#kubectl delete clusterserviceversion "$(kubectl get clusterserviceversion -o=jsonpath='{.items[0].metadata.name}')"
#kubectl delete crd aerospikeclusters.asdb.aerospike.com

terraform -chdir="$WORKSPACE/aerospike-proximus/local-env/kind" destroy -no-color -compact-warnings -auto-approve
rm -rf "$WORKSPACE/aerospike-proximus/local-env/kind/.terraform"
rm -rf "$WORKSPACE/aerospike-proximus/local-env/kind/volume"
rm -f "$WORKSPACE/aerospike-proximus/local-env/kind/proximus-cluster-config"
rm -f "$WORKSPACE/aerospike-proximus/local-env/kind/terraform.tfstate"
rm -f "$WORKSPACE/aerospike-proximus/local-env/kind/terraform.tfstate.backup"
rm -f "$WORKSPACE/aerospike-proximus/local-env/kind/.terraform.lock.hcl"
rm -f "$WORKSPACE/aerospike-proximus/local-env/secrets/features.conf"
rm -f "$WORKSPACE/aerospike-proximus/features.conf"
