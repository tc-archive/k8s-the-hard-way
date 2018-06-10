#!/bin/bash

# Install containerd **********************************************************
#

# Download containerd binaries.
#
wget -q --show-progress --https-only --timestamping   https://github.com/kubernetes-incubator/cri-tools/releases/download/v1.0.0-beta.0/crictl-v1.0.0-beta.0-linux-amd64.tar.gz   https://storage.googleapis.com/kubernetes-the-hard-way/runsc   https://github.com/opencontainers/runc/releases/download/v1.0.0-rc5/runc.amd64   https://github.com/containerd/containerd/releases/download/v1.1.0/containerd-1.1.0.linux-amd64.tar.gz


# Install containerd binaries.
#
sudo tar -xvf crictl-v1.0.0-beta.0-linux-amd64.tar.gz -C /usr/local/bin/
sudo mv runc.amd64 runc
chmod +x runc runsc
sudo cp runc runsc /usr/local/bin/
sudo tar -xvf containerd-1.1.0.linux-amd64.tar.gz -C /


# Configure Containerd.
#

sudo mkdir -p /etc/containerd/

# Untrusted workloads will be run using the runc runtime.
# Untrusted workloads will be run using the gVisor (runsc) runtime.
#
cat << EOF2 | sudo -E tee /etc/containerd/config.toml
[plugins]
  [plugins.cri.containerd]
    snapshotter = "overlayfs"
    [plugins.cri.containerd.default_runtime]
      runtime_type = "io.containerd.runtime.v1.linux"
      runtime_engine = "/usr/local/bin/runc"
      runtime_root = ""
    [plugins.cri.containerd.untrusted_workload_runtime]
      runtime_type = "io.containerd.runtime.v1.linux"
      runtime_engine = "/usr/local/bin/runsc"
      runtime_root = "/run/containerd/runsc"
EOF2

# Create containerd service file.
#
cat <<EOF2 | sudo -E tee /etc/systemd/system/containerd.service
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target

[Service]
ExecStartPre=/sbin/modprobe overlay
ExecStart=/bin/containerd
Restart=always
RestartSec=5
Delegate=yes
KillMode=process
OOMScoreAdjust=-999
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity

[Install]
WantedBy=multi-user.target
EOF2
