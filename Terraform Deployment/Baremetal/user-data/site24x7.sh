#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "=== ZylkerKart ${service_name}: Installing Site24x7 Full Stack Agent ==="
wget -q https://staticdownloads.site24x7.com/server/Site24x7FullStackAgent_LinuxIns.sh
bash Site24x7FullStackAgent_LinuxIns.sh -i -key=${site24x7_key} -automation=true -apm_insight=true -ebpf=true
echo "=== Site24x7 Agent Installation Complete ==="
