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

# Provisioning CA *************************************************************
#

# Provision a Certificate Authority that can be used to generate additional 
# TLS certificates:
#   * CA configuration files
#   * certificate
#   * private key
#
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

# Provision Admin Client Certificates *****************************************
#

# Generate client and server certificates for each Kubernetes component and a 
# client certificate for the Kubernetes admin user.

function create-admin-certs() {
  # Generate config file
  cat > admin-csr.json <<EOF
{
  "CN": "admin",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "system:masters",
      "OU": "Kubernetes The Hard Way",
      "ST": "Oregon"
    }
  ]
}
EOF
  # Generate the admin certificates and private key using CA.
  cfssl gencert \
    -ca=ca.pem \
    -ca-key=ca-key.pem \
    -config=ca-config.json \
    -profile=kubernetes \
    admin-csr.json | cfssljson -bare admin
}

function delete-admin-certs() {
  rm -f admin-key.pem admin.csr admin.pem  
  rm -f admin-csr.json 
}

# Provision Kublet Client Certificates ****************************************
#

# Kubernetes uses a special-purpose authorization mode called Node Authorizer, 
# that specifically authorizes API requests made by Kubelets. In order to be 
# authorized by the Node Authorizer, Kubelets must use a credential that 
# identifies them as being in the system:nodes group, with a username of 
# system:node:<nodeName>. 
#
# Create a certificate for each Kubernetes worker node hat meets the Node 
# Authorizer requirements.
#
# * https://kubernetes.io/docs/reference/access-authn-authz/node/
# * https://kubernetes.io/docs/concepts/overview/components/#kubelet

function create-kublet-certs() {
  for instance in worker-0 worker-1 worker-2; do
    cat > ${instance}-csr.json <<EOF
{
  "CN": "system:node:${instance}",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "system:nodes",
      "OU": "Kubernetes The Hard Way",
      "ST": "Oregon"
    }
  ]
}
EOF

    EXTERNAL_IP=$(gcloud compute instances describe ${instance} \
      --format 'value(networkInterfaces[0].accessConfigs[0].natIP)')

    INTERNAL_IP=$(gcloud compute instances describe ${instance} \
      --format 'value(networkInterfaces[0].networkIP)')

    cfssl gencert \
      -ca=ca.pem \
      -ca-key=ca-key.pem \
      -config=ca-config.json \
      -hostname=${instance},${EXTERNAL_IP},${INTERNAL_IP} \
      -profile=kubernetes \
      ${instance}-csr.json | cfssljson -bare ${instance}
  done
}

function delete-kublet-certs() {
  rm -f worker-*.csr worker-*.pem worker-*-key.pem 
  rm -f worker-*-csr.json 
}

# Main ************************************************************************
#

# If provided, execute the specified function.
if [ ! -z "$1" ]; then
  $1
else
  echo "No function defined."
fi
