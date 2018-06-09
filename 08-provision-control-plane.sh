#!/bin/bash

# Bootstrapping the Kubernetes Control Plane **********************************
#

# Bootstrap the Kubernetes control plane across three compute instances and 
# configure it for high availability. 
#
# Also create an external load balancer that exposes the Kubernetes API Servers 
# to remote clients.
#
# The following components will be installed on each node: 
#   * Kubernetes API Server
#   * Scheduler
#   * Controller Manager

function _install-kube-api-server() {
  local instance=$1
  # Generate installation script.
  cat > install-kube-api-server.sh <<EOF
#!/bin/bash

# Configure the Kubernetes API Server *****************************************
#

# Create config directory.
#
sudo mkdir -p /etc/kubernetes/config

# Download api-server and kubectl binaries.
#
wget -q --show-progress --https-only --timestamping \
  "https://storage.googleapis.com/kubernetes-release/release/v1.10.2/bin/linux/amd64/kube-apiserver" \
  "https://storage.googleapis.com/kubernetes-release/release/v1.10.2/bin/linux/amd64/kubectl"

# Configure permissions and install binaries.
#
chmod +x kube-apiserver kubectl
sudo mv kube-apiserver kubectl /usr/local/bin/

# Install pki certificates and encryption configuration.
#
sudo mkdir -p /var/lib/kubernetes/
sudo cp ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem \
  service-account-key.pem service-account.pem \
  encryption-config.yaml /var/lib/kubernetes/

# The instance internal IP address will be used to advertise the API Server to 
# members of the cluster. Retrieve the internal IP address for the current compute 
# instance.
#
INTERNAL_IP=\$(curl -s -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip)

# Create the kube-apiserver.service systemd unit file
#
cat <<EOF2 | sudo -E tee /etc/systemd/system/kube-apiserver.service
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver \\
  --advertise-address=\${INTERNAL_IP} \\
  --allow-privileged=true \\
  --apiserver-count=3 \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/log/audit.log \\
  --authorization-mode=Node,RBAC \\
  --bind-address=0.0.0.0 \\
  --client-ca-file=/var/lib/kubernetes/ca.pem \\
  --enable-admission-plugins=Initializers,NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \\
  --enable-swagger-ui=true \\
  --etcd-cafile=/var/lib/kubernetes/ca.pem \\
  --etcd-certfile=/var/lib/kubernetes/kubernetes.pem \\
  --etcd-keyfile=/var/lib/kubernetes/kubernetes-key.pem \\
  --etcd-servers=https://10.240.0.10:2379,https://10.240.0.11:2379,https://10.240.0.12:2379 \\
  --event-ttl=1h \\
  --experimental-encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \\
  --kubelet-certificate-authority=/var/lib/kubernetes/ca.pem \\
  --kubelet-client-certificate=/var/lib/kubernetes/kubernetes.pem \\
  --kubelet-client-key=/var/lib/kubernetes/kubernetes-key.pem \\
  --kubelet-https=true \\
  --runtime-config=api/all \\
  --service-account-key-file=/var/lib/kubernetes/service-account.pem \\
  --service-cluster-ip-range=10.32.0.0/24 \\
  --service-node-port-range=30000-32767 \\
  --tls-cert-file=/var/lib/kubernetes/kubernetes.pem \\
  --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF2
EOF
  # Set permissions.
  chmod u+x install-kube-api-server.sh 
  # Upload install script.
  gcloud compute scp install-kube-api-server.sh "${instance}":./
  # Execute installation script.
  gcloud compute ssh "${instance}" --command ./install-kube-api-server.sh
  # Start-up services.
  gcloud compute ssh "${instance}" --command "sudo systemctl daemon-reload"
  gcloud compute ssh "${instance}" --command "sudo systemctl enable kube-apiserver"
  gcloud compute ssh "${instance}" --command "sudo systemctl start kube-apiserver"
}

function _uninstall-kube-api-server() {
  local instance=$1
  # Shut-down
  gcloud compute ssh "${instance}" --command "sudo systemctl stop kube-apiserver"
  gcloud compute ssh "${instance}" --command "sudo systemctl disable kube-apiserver"
  gcloud compute ssh "${instance}" --command "sudo systemctl daemon-reload"
  # Clean up etcd resources.
  gcloud compute ssh "${instance}" --command "sudo rm -f /etc/systemd/system/kube-apiserver.service" 
  gcloud compute ssh "${instance}" --command "sudo rm -f /usr/local/bin/{kube-apiserver,kubectl}"
  # gcloud compute ssh "${instance}" --command "sudo rm -f /var/lib/kubernetes/{ca.pem,ca-key.pem,kubernetes-key.pem,kubernetes.pem,service-account-key.pem,service-account.pem,encryption-config.yaml}"
  gcloud compute ssh "${instance}" --command "sudo rm -f install-kube-api-server.sh"
  # Clean-up local
  rm -f install-kube-api-server.sh
}

function _install-kube-controller-manager() {
  local instance=$1
  # Generate installation script.
  cat > install-kube-controller-manager.sh <<EOF
#!/bin/bash

# Configure the Kubernetes Controller Manager *********************************
#

# Create config directory.
#
sudo mkdir -p /etc/kubernetes/config

# Download kube-controller-manager binary.
#
wget -q --show-progress --https-only --timestamping \
  "https://storage.googleapis.com/kubernetes-release/release/v1.10.2/bin/linux/amd64/kube-controller-manager"

# Configure permissions and install binaries.
#
chmod +x kube-controller-manager
sudo mv kube-controller-manager /usr/local/bin/

# Move the kube-controller-manager kubeconfig into place:
#
sudo cp kube-controller-manager.kubeconfig /var/lib/kubernetes/

# Create the kube-controller-manager.service systemd unit file
#
cat <<EOF2 | sudo -E tee /etc/systemd/system/kube-controller-manager.service
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \\
  --address=0.0.0.0 \\
  --cluster-cidr=10.200.0.0/16 \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=/var/lib/kubernetes/ca.pem \\
  --cluster-signing-key-file=/var/lib/kubernetes/ca-key.pem \\
  --kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig \\
  --leader-elect=true \\
  --root-ca-file=/var/lib/kubernetes/ca.pem \\
  --service-account-private-key-file=/var/lib/kubernetes/service-account-key.pem \\
  --service-cluster-ip-range=10.32.0.0/24 \\
  --use-service-account-credentials=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF2
EOF
  # Set permissions.
  chmod u+x install-kube-controller-manager.sh 
  # Upload install script.
  gcloud compute scp install-kube-controller-manager.sh "${instance}":./
  # Execute installation script.
  gcloud compute ssh "${instance}" --command ./install-kube-controller-manager.sh
  # Start-up services.
  gcloud compute ssh "${instance}" --command "sudo systemctl daemon-reload"
  gcloud compute ssh "${instance}" --command "sudo systemctl enable kube-controller-manager"
  gcloud compute ssh "${instance}" --command "sudo systemctl start kube-controller-manager" 
}

function _uninstall-kube-controller-manager() {
  local instance=$1
  # Shut-down etcd.
  gcloud compute ssh "${instance}" --command "sudo systemctl stop kube-controller-manager"
  gcloud compute ssh "${instance}" --command "sudo systemctl disable kube-controller-manager"
  gcloud compute ssh "${instance}" --command "sudo systemctl daemon-reload"
  # Clean up etcd resources.
  gcloud compute ssh "${instance}" --command "sudo rm -f /etc/systemd/system/kube-controller-manager.service" 
  gcloud compute ssh "${instance}" --command "sudo rm -f /usr/local/bin/kube-controller-manager"
  # gcloud compute ssh "${instance}" --command "sudo rm -f /var/lib/kubernetes/{ca.pem,ca-key.pem,kubernetes-key.pem,kubernetes.pem,service-account-key.pem,service-account.pem,encryption-config.yaml}"
  gcloud compute ssh "${instance}" --command "sudo rm -f install-kube-controller-manager.sh"
  # Clean-up local
  rm -f install-kube-controller-manager.sh
}

function _install-kube-scheduler() {
  local instance=$1
  # Generate installation script.
  cat > install-kube-scheduler.sh <<EOF
#!/bin/bash

# Configure the Kubernetes Scheduler *********************************
#

# Create config directory.
#
sudo mkdir -p /etc/kubernetes/config

# Download scheduler binary.
#
wget -q --show-progress --https-only --timestamping \
  "https://storage.googleapis.com/kubernetes-release/release/v1.10.2/bin/linux/amd64/kube-scheduler"

# Configure permissions and install binaries.
#
chmod +x kube-scheduler
sudo mv kube-scheduler /usr/local/bin/

# Move the kube-scheduler.kubeconfig into place:
#
sudo cp kube-scheduler.kubeconfig /var/lib/kubernetes/

# Create the kube-scheduler.yaml configuration file.
#
cat <<EOF2 | sudo -E tee /etc/kubernetes/config/kube-scheduler.yaml
apiVersion: componentconfig/v1alpha1
kind: KubeSchedulerConfiguration
clientConnection:
  kubeconfig: "/var/lib/kubernetes/kube-scheduler.kubeconfig"
leaderElection:
  leaderElect: true
EOF2

# Create the kube-scheduler.service systemd unit file
#
cat <<EOF2 | sudo -E tee /etc/systemd/system/kube-scheduler.service
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-scheduler \\
  --config=/etc/kubernetes/config/kube-scheduler.yaml \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF2
EOF
  # Set permissions.
  chmod u+x install-kube-scheduler.sh 
  # Upload install script.
  gcloud compute scp install-kube-scheduler.sh "${instance}":./
  # Execute installation script.
  gcloud compute ssh "${instance}" --command ./install-kube-scheduler.sh
  # Start-up services.
  gcloud compute ssh "${instance}" --command "sudo systemctl daemon-reload"
  gcloud compute ssh "${instance}" --command "sudo systemctl enable kube-scheduler"
  gcloud compute ssh "${instance}" --command "sudo systemctl start kube-scheduler"
}

function _uninstall-kube-scheduler() {
  local instance=$1
  # Shut-down etcd.
  gcloud compute ssh "${instance}" --command "sudo systemctl stop kube-scheduler"
  gcloud compute ssh "${instance}" --command "sudo systemctl disable kube-scheduler"
  gcloud compute ssh "${instance}" --command "sudo systemctl daemon-reload"
  # Clean up etcd resources.
  gcloud compute ssh "${instance}" --command "sudo rm -f /etc/systemd/system/kube-scheduler.service"
  gcloud compute ssh "${instance}" --command "sudo rm -f /etc/kubernetes/config/kube-scheduler.yaml" 
  gcloud compute ssh "${instance}" --command "sudo rm -f /usr/local/bin/kube-scheduler"
  gcloud compute ssh "${instance}" --command "sudo rm -f install-kube-scheduler.sh"
  # Clean-up local
  rm -f install-kube-scheduler.sh
}

# Enable HTTP Health Checks
# A Google Network Load Balancer will be used to distribute traffic across 
# the three API servers and allow each API server to terminate TLS connections 
# and validate client certificates. 
#
# The network load balancer only supports HTTP health checks which means the 
# HTTPS endpoint exposed by the API server cannot be used. As a workaround the 
# nginx webserver can be used to proxy HTTP health checks. In this section 
# nginx will be installed and configured to accept HTTP health checks on port 
# 80 and proxy the connections to the API server on https://127.0.0.1:6443/healthz.
#
#   * https://cloud.google.com/compute/docs/load-balancing/network/
#
function _install-nginx-http-health-check() {
  local instance=$1
  # Generate installation script.
  cat > install-kube-scheduler.sh <<EOF
#!/bin/bash

# Install and configure nginx health check ************************************
#

sudo apt-get install -y nginx

cat > kubernetes.default.svc.cluster.local <<EOF2
server {
  listen      80;
  server_name kubernetes.default.svc.cluster.local;

  location /healthz {
     proxy_pass                    https://127.0.0.1:6443/healthz;
     proxy_ssl_trusted_certificate /var/lib/kubernetes/ca.pem;
  }
}
EOF2

sudo mv kubernetes.default.svc.cluster.local \
  /etc/nginx/sites-available/kubernetes.default.svc.cluster.local

sudo ln -s /etc/nginx/sites-available/kubernetes.default.svc.cluster.local /etc/nginx/sites-enabled/

sudo systemctl enable nginx
sudo systemctl restart nginx
EOF
}

function _reload-control-plane() {
  local instance=$1
  # Start-up controller services.
  gcloud compute ssh "${instance}" --command "sudo systemctl daemon-reload"
  gcloud compute ssh "${instance}" --command "sudo systemctl enable kube-apiserver kube-controller-manager kube-scheduler"
  gcloud compute ssh "${instance}" --command "sudo systemctl start kube-apiserver kube-controller-manager kube-scheduler"
}

function _create-control-plane() {
  echo "creating control-plane..."
  for instance in controller-0 controller-1 controller-2; do
    echo "installing ${instance} kube-api-server service..."
    _install-kube-api-server ${instance}
    echo "installing ${instance} kube-controller-manager service..."
    _install-kube-controller-manager ${instance}
    echo "installing ${instance} -kube-scheduler service..."
    _install-kube-scheduler ${instance}
    echo "installing ${instance} nginx htp health-check..."
    _install-nginx-http-health-check ${instance}
  done
}

function _delete-control-plane() {
  echo "deleting control-plane..."
  for instance in controller-0 controller-1 controller-2; do
    echo "uninstalling ${instance} kube-api-server service..."
    _uninstall-kube-api-server ${instance}
    echo "uninstalling ${instance} kube-controller-manager service..."
    _uninstall-kube-controller-manager ${instance}
    echo "uninstalling ${instance} -kube-scheduler service..."
    _uninstall-kube-scheduler ${instance}
  done
}


# Control Plane ***************************************************************
#

function create-control-plane() {
  _create-control-plane
  # _install-kube-api-server controller-0
  # _install-kube-controller-manager controller-0
  # _install-kube-scheduler controller-0
  # _install-nginx-http-health-check controller-0 
}

function delete-control-plane() {
  _delete-control-plane
}

# Main ************************************************************************
#

# If provided, execute the specified function.
if [ ! -z "$1" ]; then
  $1
fi