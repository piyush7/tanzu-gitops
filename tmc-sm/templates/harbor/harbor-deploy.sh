#!/bin/bash

export TLD_DOMAIN=$(yq eval '.tld_domain' ./templates/values-template.yaml)
export HARBOR_URL=$(yq eval '.harbor.fqdn' ./templates/values-template.yaml)
export HARBOR_USER=$(yq eval '.harbor.user' ./templates/values-template.yaml)
export HARBOR_PASS=$(yq eval '.harbor.pass' ./templates/values-template.yaml)
export vcenterSsoUser=$(yq eval '.wcp.user' ./templates/values-template.yaml)
export vCenterAddress=$(yq eval '.vcenter.fqdn' ./templates/values-template.yaml)
export vcenterSsoPassword=$(yq eval '.wcp.password' ./templates/values-template.yaml)
export GOVC_URL=$(echo ${vcenterSsoUser}:${vcenterSsoPassword}@${vCenterAddress})
export GOVC_INSECURE=1
export DNS_DOMAIN=$(yq eval '.harbor.deploy.dns_domain' ./templates/values-template.yaml)
export DNS_SERVER=$(yq eval '.harbor.deploy.dns' ./templates/values-template.yaml)
export MGT_IP_HARBOR=$(yq eval '.harbor.deploy.ip' ./templates/values-template.yaml)
export MGT_GW=$(yq eval '.harbor.deploy.gateway' ./templates/values-template.yaml)
export MGT_NETMASK=$(yq eval '.harbor.deploy.netmask' ./templates/values-template.yaml)
export PORT_GROUP=$(yq eval '.harbor.deploy.port_group_name' ./templates/values-template.yaml)
export DATASTORE=$(yq eval '.harbor.deploy.datastore_name' ./templates/values-template.yaml)

export CA_CERT_=$(yq eval '.harbor.deploy.ca_crt' ./templates/values-template.yaml)
export SERVER_CERT_=$(yq eval '.harbor.deploy.server_crt' ./templates/values-template.yaml)
export SERVER_KEY_=$(yq eval '.harbor.deploy.server_key' ./templates/values-template.yaml)

export HARBOR_CA_CERT=$(./templates/harbor/newline.sh <(echo "$CA_CERT_"))
export SERVER_CERT=$(./templates/harbor/newline.sh <(echo "$SERVER_CERT_"))
export SERVER_KEY=$(./templates/harbor/newline.sh <(echo "$SERVER_KEY_"))

govc library.create -ds=$DATASTORE local-harbor
govc library.import -k=true -m=true -n photon-4-harbor-v2.6.3.ova local-harbor airgapped-files/ova/photon-4-harbor-v2.6.3.ova

cat > ./templates/harbor/harbor.json <<-EOF
{
    "DiskProvisioning": "thin",
    "IPAllocationPolicy": "dhcpPolicy",
    "IPProtocol": "IPv4",
    "PropertyMapping": [
        {
            "Key": "guestinfo.root_password",
            "Value": "${HARBOR_PASS}"
        },
        {
            "Key": "guestinfo.allow_root_ssh",
            "Value": "True"
        },
        {
            "Key": "guestinfo.harbor_hostname",
            "Value": "${HARBOR_URL}"
        },
        {
            "Key": "guestinfo.harbor_admin_password",
            "Value": "${HARBOR_PASS}"
        },
        {
            "Key": "guestinfo.harbor_database_password",
            "Value": "${HARBOR_PASS}"
        },
        {
            "Key": "guestinfo.harbor_scanner_enable",
            "Value": "False"
        },
        {
            "Key": "guestinfo.harbor_selfsigned_cert",
            "Value": "False"
        },
        {
            "Key": "guestinfo.harbor_ca",
            "Value": "${HARBOR_CA_CERT}"
        },
        {
            "Key": "guestinfo.harbor_server_cert",
            "Value": "${SERVER_CERT}"
        },
        {
            "Key": "guestinfo.harbor_server_key",
            "Value": "${SERVER_KEY}"
        },
        {
            "Key": "guestinfo.network_ip_address",
            "Value": "${MGT_IP_HARBOR}"
        },
        {
            "Key": "guestinfo.network_netmask",
            "Value": "${MGT_NETMASK}"
        },
        {
            "Key": "guestinfo.network_gateway",
            "Value": "${MGT_GW}"
        },
        {
            "Key": "guestinfo.network_dns_server",
            "Value": "${DNS_SERVER}"
        },
        {
            "Key": "guestinfo.network_dns_domain",
            "Value": "${DNS_DOMAIN}"
        }
    ],
    "NetworkMapping": [
        {
            "Name": "nic0",
            "Network": "${PORT_GROUP}"
        }
    ],
    "Annotation": "Harbor ova vSphere image - VMware Photon OS 64-bit and Harbor v2.6.3+vmware.1",
    "MarkAsTemplate": false,
    "PowerOn": false,
    "InjectOvfEnv": false,
    "WaitForIP": false,
    "Name": null
}
EOF

govc library.deploy -options ./templates/harbor/harbor.json local-harbor/photon-4-harbor-v2.6.3.ova tanzu-harbor
govc vm.power -on tanzu-harbor
govc vm.disk.change -vm=tanzu-harbor -disk.label "Hard disk 2" -size 200G