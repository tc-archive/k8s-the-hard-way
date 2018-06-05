#!/bin/bash

# Provisioning a CA and Generating TLS Certificates ***************************
#

# Provision a PKI Infrastructure using CloudFlare's PKI toolkit, cfssl, then 
# use it to bootstrap a Certificate Authority, and generate TLS certificates 
# for the following components: 
#   * etcd
#   * kube-apiserver
#   * kube-controller-manager
#   * kube-scheduler
#   * kubelet
#   * kube-proxy

function check-prerequisites() {
  if [ -z "$(which cfssl)" ]; then
    echo "No 'cfssl' present on the path. Please install cfssl."
    exit 1
  fi
  if [ -z "$(which cfssljson)" ]; then
    echo "No 'cfssljson' present on the path. Please install cfssljson."
    exit 1
  fi
}

function create-certificate-authority() {
  # Create ca-config.
  cat > ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "8760h"
    },
    "profiles": {
      "kubernetes": {
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "expiry": "8760h"
      }
    }
  }
}
EOF
  # Create ca-csr.
  cat > ca-csr.json <<EOF
{
  "CN": "Kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "Kubernetes",
      "OU": "CA",
      "ST": "Oregon"
    }
  ]
}
EOF
  # Create certificates.
  cfssl gencert -initca ca-csr.json | cfssljson -bare ca
}


function delete-certificate-authority() {
  rm -f ca-key.pem ca.csr ca.pem
  rm -f ca-csr.json 
  rm -f ca-config.json 
}

# Main ************************************************************************
#

# If provided, execute the specified function.
if [ ! -z "$1" ]; then
  $1
else
  echo "No function defined."
fi
