#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source "${DIR}/03-provision-infra.sh" ""
source "${DIR}/04-provision-pki.sh" ""
source "${DIR}/05-provision-kubeconfigs.sh" ""
source "${DIR}/06-provision-encryption.sh" ""
source "${DIR}/07-provision-etcd.sh" ""

# K8s Cluster *****************************************************************
#
function create-k8s() {
  create-infra
  create-pki
  create-kubeconfigs
  create-encryption
  create-etcd
}
function delete-k8s() {
  delete-etcd
  delete-encryption
  delete-kubeconfigs
  delete-oki
  delete-infra
}

# Main ************************************************************************
#

# If provided, execute the specified function.
if [ ! -z "$1" ]; then
  $1
fi