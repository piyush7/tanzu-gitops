#!/bin/bash

export vcenterSsoUser=$(yq eval '.wcp.user' ./templates/values-template.yaml)
export vCenterAddress=$(yq eval '.vcenter.fqdn' ./templates/values-template.yaml)
export vcenterSsoPassword=$(yq eval '.wcp.password' ./templates/values-template.yaml)
export GOVC_URL=$(echo ${vcenterSsoUser}:${vcenterSsoPassword}@${vCenterAddress})
export GOVC_INSECURE=1
export MGT_IP_HARBOR=$(yq eval '.harbor.deploy.ip' ./templates/values-template.yaml)
export HARBOR_PASS=$(yq eval '.harbor.pass' ./templates/values-template.yaml)

govc vm.disk.change -vm=tanzu-harbor -disk.label "Hard disk 2" -size 250G

sshpass -p "${HARBOR_PASS}" ssh -t -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null  root@"${MGT_IP_HARBOR}"  << EOFSCRIPT
lsblk
echo 1 > /sys/class/block/sdb/device/rescan
parted /dev/sdb ---pretend-input-tty <<EOF
resizepart 1
Fix
1
Yes
100%
quit
EOF
resize2fs /dev/sdb1
lsblk
EOFSCRIPT