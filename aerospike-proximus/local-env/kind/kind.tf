provider "kind" {}

resource "kind_cluster" "proximus--k8s-cluster" {
  name           = "proximus-cluster"
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      extra_mounts {
        host_path = "${path.module}/volume"
        container_path = "/var/local-path-provisioner"
      }

      kubeadm_config_patches = [
        "kind: InitConfiguration\nnodeRegistration:\n  kubeletExtraArgs:\n    node-labels: \"ingress-ready=true\"\n"
      ]

      extra_port_mappings  {
        container_port = 80
        host_port      = 80
      }
      extra_port_mappings  {
        container_port = 443
        host_port      = 443
      }
#      extra_port_mappings  {
#        container_port = 5000
#        host_port      = 5000
#      }
#      extra_port_mappings  {
#        container_port = 5040
#        host_port      = 5040
#      }

    }

#    node  {
#      role = "worker"
#      extra_mounts {
#        host_path = "${path.module}/volume"
#        container_path = "/var/local-path-provisioner"
#      }
#      extra_port_mappings  {
#        container_port = 5000
#        host_port      = 5000
#      }
#      extra_port_mappings  {
#        container_port = 5040
#        host_port      = 5040
#      }
#    }
  }
}