#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source "${DIR}/03-provision-infra.sh" ""
source "${DIR}/04-provision-pki.sh" ""
source "${DIR}/05-provision-kubeconfigs.sh" ""

# K8s Cluster *****************************************************************
#
function create-k8s() {
  create-infra
  create-certs
  create-kubeconfigs
}

function delete-k8s() {
  delete-kubeconfigs
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