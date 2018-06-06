#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source "${DIR}/03-provision-infra.sh"
source "${DIR}/04-provision-pki.sh"

# K8s Cluster *****************************************************************
#
function create-k8s-cluster() {
  create-infra
  create-certs
}

function delete-k8s-cluster() {
  delete-certs
  delete-infra
}

# Main ************************************************************************
#

# If provided, execute the specified function.
if [ ! -z "$1" ]; then
  $1
else
  echo "No function defined."
fi