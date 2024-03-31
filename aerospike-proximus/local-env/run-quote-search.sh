#!/bin/bash -e
WORKSPACE="$(git rev-parse --show-toplevel)"

mkdir -p "$WORKSPACE/aerospike-proximus/proximus-examples/local-env/data"

curl -L -o "$WORKSPACE/aerospike-proximus/proximus-examples/local-env/data/quotes.csv.tgz" \
https://github.com/aerospike/proximus-examples/raw/main/quote-semantic-search/container-volumes/quote-search/data/quotes.csv.tgz
docker run -d \
--name "quote-search" \
-v "$WORKSPACE/aerospike-proximus/local-env/data:/container-volumes/quote-search/data" \
--network "kind" -p "8080:8080" \
-e "PROXIMUS_HOST=$(kubectl -n aerospike get svc/as-quote-search-aerospike-proximus-lb \
-o=jsonpath='{.status.loadBalancer.ingress[0].ip}')" \
-e "PROXIMUS_PORT=80" \
-e "APP_NUM_QUOTES=5000" \
-e "GRPC_DNS_RESOLVER=native" \
-e "PROXIMUS_IS_LOADBALANCER=True" quote-search
