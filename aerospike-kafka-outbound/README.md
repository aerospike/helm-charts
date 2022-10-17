# Aerospike Kafka Outbound Connector

This Helm chart allows you to configure and run our official [Aerospike Kafka Outbound Connector][https://hub.docker.com/repository/docker/aerospike/aerospike-kafka-outbound] 
docker image on a Kubernetes cluster.


## Prerequisites
- Kubernetes cluster
- Helm v3
- A Kafka cluster with brokers reachable from the pods in the Kubernetes cluster
- An Aerospike cluster that can connect to Pods in the Kubernetes cluster
  The Aerospike cluster can be deployed in the same Kubernetes cluster using [Aerospike
  Kubernetes Operator](https://docs.aerospike.com/cloud/kubernetes/operator)

