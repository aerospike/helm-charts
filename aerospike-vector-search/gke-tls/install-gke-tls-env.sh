#!/bin/bash -e
WORKSPACE="$(git rev-parse --show-toplevel)"
PROJECT=""
ZONE=""

if [ -z "$PROJECT" ]; then
    echo "Set Project"
    exit 1
fi

if [ -z "$ZONE" ]; then
    echo "set Zone"
    exit 1
fi

if [ ! -f "$WORKSPACE/aerospike-vector-search/examples/gke-tls/secrets/features.conf" ]; then
  echo "features.conf Not found"
  exit 1
fi


mkdir -p "$WORKSPACE"/aerospike-vector-search/examples/gke-tls/{input,output,secrets,certs}

echo "Generate Root"
openssl genrsa \
-out "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/ca.aerospike.com.key" 2048

openssl req \
-x509 \
-new \
-nodes \
-config "$WORKSPACE/aerospike-vector-search/examples/gke-tls/openssl_ca.conf" \
-extensions v3_ca \
-key "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/ca.aerospike.com.key" \
-sha256 \
-days 3650 \
-out "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/ca.aerospike.com.pem" \
-subj "/C=UK/ST=London/L=London/O=abs/OU=Support/CN=ca.aerospike.com"

echo "Generate Requests & Private Key"
SVC_NAME="aerospike-cluster.aerospike.svc.cluster.local" COMMON_NAME="asd.aerospike.com" openssl req \
-new \
-nodes \
-config "$WORKSPACE/aerospike-vector-search/examples/gke-tls/openssl.conf" \
-extensions v3_req \
-out "$WORKSPACE/aerospike-vector-search/examples/gke-tls/input/asd.aerospike.com.req" \
-keyout "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/asd.aerospike.com.key" \
-subj "/C=UK/ST=London/L=London/O=abs/OU=Server/CN=asd.aerospike.com"

echo "1"
SVC_NAME="avs-gke-aerospike-vector-search.aerospike.svc.cluster.local" COMMON_NAME="avs.aerospike.com" openssl req \
-new \
-nodes \
-config "$WORKSPACE/aerospike-vector-search/examples/gke-tls/openssl.conf" \
-extensions v3_req \
-out "$WORKSPACE/aerospike-vector-search/examples/gke-tls/input/avs.aerospike.com.req" \
-keyout "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/avs.aerospike.com.key" \
-subj "/C=UK/ST=London/L=London/O=abs/OU=Client/CN=avs.aerospike.com" \

echo "2"
SVC_NAME="avs-gke-aerospike-vector-search.aerospike.svc.cluster.local" COMMON_NAME="svc.aerospike.com" openssl req \
-new \
-nodes \
-config "$WORKSPACE/aerospike-vector-search/examples/gke-tls/openssl_svc.conf" \
-extensions v3_req \
-out "$WORKSPACE/aerospike-vector-search/examples/gke-tls/input/svc.aerospike.com.req" \
-keyout "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/svc.aerospike.com.key" \
-subj "/C=UK/ST=London/L=London/O=abs/OU=Client/CN=svc.aerospike.com" \

echo "Generate Certificates"
SVC_NAME="aerospike-cluster.aerospike.svc.cluster.local" COMMON_NAME="asd.aerospike.com" openssl x509 \
-req \
-extfile "$WORKSPACE/aerospike-vector-search/examples/gke-tls/openssl.conf" \
-in "$WORKSPACE/aerospike-vector-search/examples/gke-tls/input/asd.aerospike.com.req" \
-CA "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/ca.aerospike.com.pem" \
-CAkey "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/ca.aerospike.com.key" \
-extensions v3_req \
-days 3649 \
-outform PEM \
-out "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/asd.aerospike.com.pem" \
-set_serial 110 \

SVC_NAME="avs-gke-aerospike-vector-search.aerospike.svc.cluster.local" COMMON_NAME="avs.aerospike.com" openssl x509 \
-req \
-extfile "$WORKSPACE/aerospike-vector-search/examples/gke-tls/openssl.conf" \
-in "$WORKSPACE/aerospike-vector-search/examples/gke-tls/input/avs.aerospike.com.req" \
-CA "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/ca.aerospike.com.pem" \
-CAkey "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/ca.aerospike.com.key" \
-extensions v3_req \
-days 3649 \
-outform PEM \
-out "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/avs.aerospike.com.pem" \
-set_serial 210 \

SVC_NAME="avs-gke-aerospike-vector-search.aerospike.svc.cluster.local" COMMON_NAME="svc.aerospike.com" openssl x509 \
-req \
-extfile "$WORKSPACE/aerospike-vector-search/examples/gke-tls/openssl_svc.conf" \
-in "$WORKSPACE/aerospike-vector-search/examples/gke-tls/input/svc.aerospike.com.req" \
-CA "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/ca.aerospike.com.pem" \
-CAkey "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/ca.aerospike.com.key" \
-extensions v3_req \
-days 3649 \
-outform PEM \
-out "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/svc.aerospike.com.pem" \
-set_serial 310 \

echo "Verify Certificate signed by root"
openssl verify \
-verbose \
-CAfile "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/ca.aerospike.com.pem" \
"$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/asd.aerospike.com.pem"

openssl verify \
-verbose\
 -CAfile "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/ca.aerospike.com.pem" \
 "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/asd.aerospike.com.pem"

 openssl verify \
 -verbose\
  -CAfile "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/ca.aerospike.com.pem" \
  "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/svc.aerospike.com.pem"

PASSWORD="citrusstore"
echo -n "$PASSWORD" | tee "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/storepass" \
"$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/keypass" > \
"$WORKSPACE/aerospike-vector-search/examples/gke-tls/secrets/client-password.txt"

ADMIN_PASSWORD="admin123"
echo -n "$ADMIN_PASSWORD" > "$WORKSPACE/aerospike-vector-search/examples/gke-tls/secrets/aerospike-password.txt"

keytool \
-import \
-file "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/ca.aerospike.com.pem" \
--storepass "$PASSWORD" \
-keystore "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/ca.aerospike.com.truststore.jks" \
-alias "ca.aerospike.com" \
-noprompt

openssl pkcs12 \
-export \
-out "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/avs.aerospike.com.p12" \
-in "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/avs.aerospike.com.pem" \
-inkey "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/avs.aerospike.com.key" \
-password file:"$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/storepass"

keytool \
-importkeystore \
-srckeystore "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/avs.aerospike.com.p12" \
-destkeystore "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/avs.aerospike.com.keystore.jks" \
-srcstoretype pkcs12 \
-srcstorepass "$(cat $WORKSPACE/aerospike-vector-search/examples/gke-tls/output/storepass)" \
-deststorepass "$(cat $WORKSPACE/aerospike-vector-search/examples/gke-tls/output/storepass)" \
-noprompt

openssl pkcs12 \
-export \
-out "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/svc.aerospike.com.p12" \
-in "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/svc.aerospike.com.pem" \
-inkey "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/svc.aerospike.com.key" \
-password file:"$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/storepass"

keytool \
-importkeystore \
-srckeystore "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/svc.aerospike.com.p12" \
-destkeystore "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/svc.aerospike.com.keystore.jks" \
-srcstoretype pkcs12 \
-srcstorepass "$(cat $WORKSPACE/aerospike-vector-search/examples/gke-tls/output/storepass)" \
-deststorepass "$(cat $WORKSPACE/aerospike-vector-search/examples/gke-tls/output/storepass)" \
-noprompt

mv "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/svc.aerospike.com.keystore.jks" \
"$WORKSPACE/aerospike-vector-search/examples/gke-tls/certs/svc.aerospike.com.keystore.jks"

mv "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/avs.aerospike.com.keystore.jks" \
"$WORKSPACE/aerospike-vector-search/examples/gke-tls/certs/avs.aerospike.com.keystore.jks"

mv "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/ca.aerospike.com.truststore.jks" \
"$WORKSPACE/aerospike-vector-search/examples/gke-tls/certs/ca.aerospike.com.truststore.jks"

mv "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/asd.aerospike.com.pem" \
"$WORKSPACE/aerospike-vector-search/examples/gke-tls/certs/asd.aerospike.com.pem"

mv "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/avs.aerospike.com.pem" \
"$WORKSPACE/aerospike-vector-search/examples/gke-tls/certs/avs.aerospike.com.pem"

mv "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/svc.aerospike.com.pem" \
"$WORKSPACE/aerospike-vector-search/examples/gke-tls/certs/svc.aerospike.com.pem"

mv "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/asd.aerospike.com.key" \
"$WORKSPACE/aerospike-vector-search/examples/gke-tls/certs/asd.aerospike.com.key"

mv "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/ca.aerospike.com.pem" \
"$WORKSPACE/aerospike-vector-search/examples/gke-tls/certs/ca.aerospike.com.pem"

mv "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/keypass" \
"$WORKSPACE/aerospike-vector-search/examples/gke-tls/certs/keypass"

mv "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output/storepass" \
"$WORKSPACE/aerospike-vector-search/examples/gke-tls/certs/storepass"

echo "Generate Auth Keys"
openssl genpkey \
-algorithm RSA \
-out "$WORKSPACE/aerospike-vector-search/examples/gke-tls/secrets/private_key.pem" \
-pkeyopt rsa_keygen_bits:2048 \
-pass "pass:$PASSWORD"

openssl rsa \
-pubout \
-in "$WORKSPACE/aerospike-vector-search/examples/gke-tls/secrets/private_key.pem" \
-out "$WORKSPACE/aerospike-vector-search/examples/gke-tls/secrets/public_key.pem" \
-passin "pass:$PASSWORD"

echo "Install GKE"
gcloud config set project "$PROJECT"
gcloud container clusters create avs-gke-cluster \
--zone "$ZONE" \
--project "$PROJECT" \
--num-nodes 3 \
--machine-type e2-highmem-4
gcloud container clusters get-credentials avs-gke-cluster --zone="$ZONE"

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
--from-file="$WORKSPACE/aerospike-vector-search/examples/gke-tls/secrets"
kubectl --namespace aerospike create secret generic aerospike-tls \
--from-file="$WORKSPACE/aerospike-vector-search/examples/gke-tls/certs"
kubectl --namespace aerospike create secret generic auth-secret --from-literal=password='admin123'

echo "Add Storage Class"
kubectl apply -f https://raw.githubusercontent.com/aerospike/aerospike-kubernetes-operator/master/config/samples/storage/gce_ssd_storage_class.yaml

sleep 5
echo "Deploy Aerospike Cluster"
kubectl apply -f "$WORKSPACE/aerospike-vector-search/examples/gke-tls/aerospike.yaml"

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
--values "$WORKSPACE/aerospike-vector-search/gke-tls/config/istio-ingressgateway-values.yaml" \
--namespace istio-ingress \
--create-namespace \
--wait

kubectl apply -f "$WORKSPACE/aerospike-vector-search/gke-tls/config/gateway.yaml"
kubectl apply -f "$WORKSPACE/aerospike-vector-search/gke-tls/config/virtual-service-vector-search.yaml"

echo "Deploy AVS"
helm install avs-gke "$WORKSPACE/aerospike-vector-search" \
--values "$WORKSPACE/aerospike-vector-search/examples/gke-tls/avs-gke-values.yaml" --namespace aerospike --wait

#echo "Deploying Quote-Search"
#docker run --name="quote-search" \
#--rm \
#--env AVS_HOST="$(kubectl get svc/istio-ingress --namespace istio-ingress -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')" \
#--env AVS_PORT="5433" \
#--env AVS_TLS_CA_FILE="/etc/quote-search/certs/ca.aerospike.com.pem" \
#--env AVS_IS_LOADBALANCER="True" \
#--volume "$WORKSPACE/aerospike-vector-search/examples/gke-tls/certs":"/etc/quote-search/certs" \
#davi17g/quote-search:1.0.0

#git clone \
#--depth 1 \
#--branch main \
#--no-checkout https://github.com/aerospike/aerospike-vector-search-examples.git
#cd aerospike-vector-search-examples
#git sparse-checkout set kubernetes/helm/quote-semantic-search
#git checkout main
#cd -
#
#helm install quote-search "$PWD/aerospike-vector-search-examples/kubernetes/helm/quote-semantic-search" \
#--values "$WORKSPACE/aerospike-vector-search/gke-tls/config/quote-search-gke-values.yaml" \
#--namespace aerospike \
#--wait \
#--timeout 7m0s
