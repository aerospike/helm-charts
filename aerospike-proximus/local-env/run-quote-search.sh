#!/bin/bash -e
WORKSPACE="$(git rev-parse --show-toplevel)"
if [ ! -d "$WORKSPACE/aerospike-proximus/proximus-examples" ]; then
  echo "Cloning proximus-examples"
  git clone https://github.com/aerospike/proximus-examples.git "$WORKSPACE/aerospike-proximus/proximus-examples"
  fi

if ! docker images --format "{{.Repository}}" | grep -q "^quote-search"; then
  echo "Building quote-semantic-search docker image"
  cd "$WORKSPACE/aerospike-proximus/proximus-examples/quote-semantic-search" && \
  docker build -f "Dockerfile-quote-search" -t "quote-search" . && cd -
  fi

#docker run -d \
#--name "quote-search" \
#-v "$WORKSPACE/aerospike-proximus/proximus-examples/quote-semantic-search/container-volumes/quote-search/data:/container-volumes/quote-search/data" \
#--network "kind" -p "8080:8080" \
#-e "PROXIMUS_HOST=$(kubectl get svc/aerospike-proximus-lb -n aerospike  -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')" \
#-e "PROXIMUS_PORT=5000" \
#-e "APP_NUM_QUOTES=5000" \
#-e "VERIFY_TLS=False" \
#-e "GRPC_DNS_RESOLVER=native" quote-search

#docker run -d \
#--name "quote-search" \
#-v "$WORKSPACE/aerospike-proximus/proximus-examples/quote-semantic-search/container-volumes/quote-search/data:/container-volumes/quote-search/data" \
#--network "kind" -p "8080:8080" \
#-e "PROXIMUS_HOST=$(kubectl -n aerospike get svc/aerospike-proximus-ingress -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')" \
#-e "PROXIMUS_PORT=5000" \
#-e "APP_NUM_QUOTES=5000" \
#-e "GRPC_DNS_RESOLVER=native" quote-search

docker run -d \
--name "quote-search" \
-v "$WORKSPACE/aerospike-proximus/proximus-examples/quote-semantic-search/container-volumes/quote-search/data:/container-volumes/quote-search/data" \
--net "host" -p "8080:8080" \
-e "PROXIMUS_HOST=host.docker.internal" \
-e "PROXIMUS_PORT=5000" \
-e "APP_NUM_QUOTES=5000" \
-e "GRPC_DNS_RESOLVER=native" quote-search