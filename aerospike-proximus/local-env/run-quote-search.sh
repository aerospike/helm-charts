#!/bin/bash -e
WORKSPACE="$(git rev-parse --show-toplevel)"
if [ ! -d "$WORKSPACE/aerospike-proximus/proximus-examples" ]; then
  echo "Cloning proximus-examples"
  git clone https://github.com/aerospike/proximus-examples.git --no-checkout "$WORKSPACE/aerospike-proximus/proximus-examples"
  cd "$WORKSPACE/aerospike-proximus/proximus-examples"
  git sparse-checkout init --cone
  git sparse-checkout set "quote-semantic-search/container-volumes/quote-search/data/quotes.csv.tgz"
  git fetch origin main
  git checkout main
  git pull
  cd -
  fi

docker run -d \
--name "quote-search" \
-v "$WORKSPACE/aerospike-proximus/proximus-examples/quote-semantic-search/container-volumes/quote-search/data:/container-volumes/quote-search/data" \
--network "kind" -p "8080:8080" \
-e "PROXIMUS_HOST=$(kubectl -n aerospike get svc/proximus-aerospike-proximus-lb -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')" \
-e "PROXIMUS_PORT=80" \
-e "APP_NUM_QUOTES=5000" \
-e "GRPC_DNS_RESOLVER=native" \
-e "PROXIMUS_IS_LOADBALANCER=True" quote-search
