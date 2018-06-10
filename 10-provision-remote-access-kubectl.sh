#!/bin/bash

# Configuring kubectl for Remote Access ***************************************
#

function configure-kubectl() {

  local dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

  export KUBECONFIG="${dir}/admin.kubeconfig"

  local KUBERNETES_PUBLIC_ADDRESS=$(gcloud compute addresses describe kubernetes-the-hard-way \
    --region $(gcloud config get-value compute/region) \
    --format 'value(address)')

  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=https://${KUBERNETES_PUBLIC_ADDRESS}:6443

  kubectl config set-credentials admin \
    --client-certificate=admin.pem \
    --client-key=admin-key.pem

  kubectl config set-context kubernetes-the-hard-way \
    --cluster=kubernetes-the-hard-way \
    --user=admin

  kubectl config use-context kubernetes-the-hard-way
}

# Main ************************************************************************
#

# If provided, execute the specified function.
if [ ! -z "$1" ]; then
  $1
fi