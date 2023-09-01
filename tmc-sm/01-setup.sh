#!/bin/bash

if [ $# -ne 1 ]; then
    echo "Usage: $0 vsphere-7|vsphere-8"
    exit 1
fi
echo "###############################################################################Checking CLIs/Binaries files#"
binaries=("kubectl" "openssl" "jq" "yq" "govc" "dig" "kubectl-vsphere" "ytt" "curl" "git" "wget" "imgpkg")
missing_binaries=""
for binary in "${binaries[@]}"; do
    if ! command -v "$binary" >/dev/null 2>&1; then
        missing_binaries+="$binary "
    fi
done
if [ -n "$missing_binaries" ]; then
    echo "The following binaries are missing: $missing_binaries"
    exit 1
else
    echo "All CLIs are present."
fi
echo "#################################################################################Checking Certificate files#"
if [ -f tmc-ca.crt ] && [ -f tmc-ca-no-pass.key ]; then
    export TMC_CA_CERT=$(cat ./tmc-ca.crt)
    export TMC_CA_CERT_VAL=$(yq eval '.trustedCAs.tmc_ca' ./templates/values-template.yaml)
    if [[ ! -z "$TMC_CA_CERT_VAL" ]];then
        diff <(echo "$TMC_CA_CERT") <(echo "$TMC_CA_CERT_VAL")
        export ca_cert_check=$?
        if [ $ca_cert_check -eq 0 ]; then
            echo "tmc-ca.crt and tmca_ca value in values-template.yaml matches. Continue."
        else
            echo ""
            echo "tmc-ca.crt and tmc_ca value in values-template.yaml does not match. Check both files. Did you create certificates two times ?"
            exit 1
        fi
    fi
    export TMC_CA_KEY=$(cat ./tmc-ca-no-pass.key)
    export TMC_CA_KEY_VAL=$(yq eval '.trustedCAs.tmc_key' ./templates/values-template.yaml)
    if [[ ! -z "$TMC_CA_KEY_VAL" ]];then
        diff <(echo "$TMC_CA_KEY") <(echo "$TMC_CA_KEY_VAL")
        export ca_key_check=$?
        if [ $ca_key_check -eq 0 ]; then
            echo "tmc-ca-no-pass.key and tmca_key value in values-template.yaml matches. Continue."
        else
            echo ""
            echo "tmc-ca-no-pass.key and tmca_key value in values-template.yaml does not match. Check both files. Did you create certificates two times ?"
            exit 1
        fi
    fi
    echo "required files exist, continuing."
else
    export TMC_CA_CERT=$(yq eval '.trustedCAs.tmc_ca' ./templates/values-template.yaml)
    export TMC_CA_KEY=$(yq eval '.trustedCAs.tmc_key' ./templates/values-template.yaml)
    export OTHER_CA_CERT=$(yq eval '.trustedCAs.other_ca' ./templates/values-template.yaml)
    export ALL_CA_CERT=$(echo -e "$TMC_CA_CERT""\n""$OTHER_CA_CERT")
    echo "$ALL_CA_CERT" > ./all-ca.crt
    echo "$TMC_CA_CERT" > ./tmc-ca.crt
    echo "$TMC_CA_KEY" > ./tmc-ca-no-pass.key
    if [ -s tmc-ca.crt ] && [ -s tmc-ca-no-pass.key ] && [ -s all-ca.crt ]; then
        echo "tmc-ca.crt, all-ca.crt and tmc-ca-no-pass.crt files created."
    else
        echo "The file is empty or does not exist."
        echo "check tmc-ca.crt and/or tmc-ca-no-pass.key and/or all-ca.crt"
        echo "check ./templates/values-template.yaml file for CA Certs and Key"
        exit 1
    fi
fi
echo "###################################################################################Checking vCenter version#"
export GOVC_URL=$(yq eval '.vcenter.fqdn' ./templates/values-template.yaml)
export GOVC_USERNAME=$(yq eval '.wcp.user' ./templates/values-template.yaml)
export GOVC_PASSWORD=$(yq eval '.wcp.password' ./templates/values-template.yaml)
export GOVC_INSECURE=1

export vCenter_version=$(govc about|grep Version|awk '{ print $2 }')
export vCenter_build=$(govc about|grep Build|awk '{ print $2 }')

if [[ "$vCenter_version" == "7.0.3" ]]; then
    if [[ $vCenter_build -le "21290409" ]]; then
        echo "vCenter version: " "$vCenter_version "/ Build" $vCenter_build, upgrade vCenter. Exiting"
        exit 1
    fi
elif [[ "$vCenter_version" == "8.0.1" ]]; then
    if [[ $vCenter_build == "22088981" ]]; then
        echo "vCenter version: " "$vCenter_version "/ Build" $vCenter_build, this version is not supported by TMC-SM, use vCenter 8u1b or below. Exiting"
        exit 1
    fi
    if [[ $vCenter_build -le "21457384" ]]; then
        echo "vCenter version: " "$vCenter_version "/ Build" $vCenter_build, upgrade vCenter. Exiting"
        exit 1
    fi
else
    echo "wrong vcenter build/version. Exiting"
    exit 1
fi

echo "##################################################################################Checking proxy on vCenter#"
export session_id=$(curl -s -k -X POST https://$GOVC_URL/rest/com/vmware/cis/session -u $GOVC_USERNAME:$GOVC_PASSWORD|jq '.value'| tr -d '"')
export httpproxystate=$(curl -s -k -X GET -H "vmware-api-session-id: ${session_id}" https://{$GOVC_URL}/api/appliance/networking/proxy|jq '.http.enabled')
export httpsproxystate=$(curl -s -k -X GET -H "vmware-api-session-id: ${session_id}" https://{$GOVC_URL}/api/appliance/networking/proxy|jq '.https.enabled')
if [ "$httpproxystate" = true ] || [ "$httpsproxystate" = true ]; then
    echo ""
    echo "Proxy is enabled on vCenter."
    echo "Please make sure that Proxy Server's IP:Port is reachable from Management and Workload Subnet."
    echo "Source: Management Subnet - Destination: Proxy IP - Port: Proxy Port"
    echo "Source: Workload Subnet - Destination: Proxy IP - Port: Proxy Port"
    echo ""
    echo "Or remove the proxy configuration from vCenter and retry again."
    exit 1
fi

echo "#######################################################################################Setting-up variables#"
export wcp_ip=$(yq eval '.wcp.ip' ./templates/values-template.yaml)
export wcp_user=$(yq eval '.wcp.user' ./templates/values-template.yaml)
export wcp_pass=$(yq eval '.wcp.password' ./templates/values-template.yaml)
export namespace=$(yq eval '.shared_cluster.namespace' ./templates/values-template.yaml)
export tmc_cluster='shared'
export ldap_auth=$(yq eval '.auth.ldap.enabled' ./templates/values-template.yaml)
export tmc_dns=$(yq eval '.tld_domain' ./templates/values-template.yaml)
export hostnames=($tmc_dns *.$tmc_dns)
echo "#####################################################################################Checking DNS A Records#"
for hostname in "${hostnames[@]}"; do
    output=$(dig +short "$hostname")
    if [[ -n "$output" ]]; then
        echo "DNS A record is resolvable for $hostname"
    else
        echo "DNS A record is not resolvable for $hostname"
        exit 1
    fi
done

cp all-ca.crt /etc/ssl/certs/

if [ "$1" = "vsphere-7" ]; then
    echo "####################################################################################Logging into Supervisor#"
    echo vsphere-7
    export KUBECTL_VSPHERE_PASSWORD=$wcp_pass
    kubectl vsphere login --server=$wcp_ip --vsphere-username $wcp_user --insecure-skip-tls-verify
    kubectx $wcp_ip
    echo "##############################################################Patching TkgServiceConfiguration with CA Cert#"
    export ALL_CA_CERT_B64=$(cat ./all-ca.crt|base64 -w0)
    kubectl --context=$wcp_ip patch TkgServiceConfiguration tkg-service-configuration --type merge -p '{"spec":{"trust":{"additionalTrustedCAs":[{"name":"root-ca-tmc","data":"'$(echo -n "$ALL_CA_CERT_B64")'"}]}}}'
    echo "################################################################################Checking vSphere Namespaces#"
    if [[ $(kubectl --context=$wcp_ip get ns $namespace -o=jsonpath='{.status.phase}') != "Active" ]]; then
        echo "$namespace has not created on vSphere or is not ready. Please check $namespace namespace on vSphere in Workload Management."
        exit 1
    fi
    echo "####################################################################################Creating Shared Cluster#"
    ytt -f templates/values-template.yaml -f templates/vsphere-7/shared-cluster.yaml | kubectl apply -f -
    while [[ $(kubectl --context=$wcp_ip get tkc shared -o=jsonpath='{.status.conditions[?(@.type=="Ready")].status}' -n $namespace) != "True" ]]; do
        echo "Waiting for cluster to be ready"
        sleep 30
    done
    echo "################################################################################Logging into shared cluster#"
    kubectl vsphere login --server=$wcp_ip --tanzu-kubernetes-cluster-name shared --tanzu-kubernetes-cluster-namespace $namespace --vsphere-username $wcp_user --insecure-skip-tls-verify
    echo "#################################################################Changing kubectl context to shared cluster#"
    kubectx $tmc_cluster
    echo "###############################################################################################creating psp#"
    kubectl --context=$tmc_cluster create clusterrolebinding default-tkg-admin-privileged-binding --clusterrole=psp:vmware-system-privileged --group=system:authenticated
    echo "##################################################################################Deploying kapp-controller#"
    ytt -f templates/common/kapp-controller.yaml -f templates/values-template.yaml | kubectl --context=$tmc_cluster apply -f -
    while [[ $(kubectl --context=$tmc_cluster get deployment kapp-controller -n kapp-controller -o=jsonpath='{.status.conditions[?(@.type=="Available")].status}') != "True" ]]; do
        echo "Waiting for kapp-controller to be ready"
        sleep 10
        kubectl --context=$tmc_cluster get pods -n kapp-controller | grep -E 'ImagePullBackOff|ErrImagePull' | awk '{ print $1 }' | xargs kubectl --context=$tmc_cluster delete pod -n kapp-controller 2>/dev/null
    done
elif [ "$1" = "vsphere-8" ]; then
    echo "####################################################################################Logging into Supervisor#"
    echo vsphere-8
    export KUBECTL_VSPHERE_PASSWORD=$wcp_pass
    kubectl vsphere login --server=$wcp_ip --vsphere-username $wcp_user --insecure-skip-tls-verify
    kubectx $wcp_ip
    echo "################################################################################Checking vSphere Namespaces#"
    if [[ $(kubectl --context=$wcp_ip get ns $namespace -o=jsonpath='{.status.phase}') != "Active" ]]; then
        echo "$namespace has not created on vSphere or is not ready. Please check $namespace namespace on vSphere in Workload Management."
        exit 1
    fi
    echo "####################################################################################Creating Shared Cluster#"
    ytt -f templates/values-template.yaml -f templates/vsphere-8/shared-cluster.yaml | kubectl apply -f -
    while [[ $(kubectl --context=$wcp_ip get cluster shared -o=jsonpath='{.status.conditions[?(@.type=="Ready")].status}' -n $namespace) != "True" ]]; do
        echo "Waiting for cluster to be ready"
        sleep 30
    done
    echo "################################################################################Logging into shared cluster#"
    kubectl vsphere login --server=$wcp_ip --tanzu-kubernetes-cluster-name shared --tanzu-kubernetes-cluster-namespace $namespace --vsphere-username $wcp_user --insecure-skip-tls-verify
    kubectx $tmc_cluster
    export node_names=$(kubectl --context=$tmc_cluster get nodes -o=jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
    while [[ -z "$node_names" ]]; do
        node_names=$(kubectl --context=$tmc_cluster get nodes -o=jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
        if [[ -z "$node_names" ]]; then
            echo "Waiting for cluster to be ready"
            sleep 30
        fi
    done
    echo "###############################################################################################creating psp#"
    kubectl --context=$tmc_cluster create clusterrolebinding default-tkg-admin-privileged-binding --clusterrole=psp:vmware-system-privileged --group=system:authenticated
fi

kubectx $tmc_cluster
echo "######################################################################Deploying Tanzu Standard Package Repo#"
ytt -f templates/common/std-repo.yaml -f templates/values-template.yaml | kubectl --context=$tmc_cluster apply -f -
while [[ $(kubectl --context=$tmc_cluster get pkgr tanzu-std-repo -n packages -o=jsonpath='{.status.conditions[?(@.type=="ReconcileSucceeded")].status}') != "True" ]]; do
    echo "Waiting for std-repo to be ready: " $(kubectl --context=$tmc_cluster get pkgr tanzu-std-repo -n packages -o=jsonpath='{.status.conditions[0].type}')
    sleep 10
    if [[ $(kubectl --context=$tmc_cluster get pkgr tanzu-std-repo -n packages -o=jsonpath='{.status.conditions[?(@.type=="ReconcileFailed")].status}') == "True" ]]; then
        kubectl --context=$tmc_cluster get pkgr tanzu-std-repo -n packages -o=jsonpath='{.status.usefulErrorMessage}'
        ytt -f templates/common/std-repo.yaml -f templates/values-template.yaml | kubectl --context=$tmc_cluster delete -f -
        sleep 5
        ytt -f templates/common/std-repo.yaml -f templates/values-template.yaml | kubectl --context=$tmc_cluster apply -f -
    fi
done
echo "#############################################################################Deploying Cert-Manager Package#"
ytt -f templates/common/cert-manager.yaml -f templates/values-template.yaml | kubectl apply -f -
while [[ $(kubectl --context=$tmc_cluster get pkgi cert-manager -n packages -o=jsonpath='{.status.conditions[?(@.type=="ReconcileSucceeded")].status}') != "True" ]]; do
    echo "Waiting for cert-manager to be ready: " $(kubectl get pkgi cert-manager -n packages -o=jsonpath='{.status.conditions[0].type}')
    sleep 10
    kubectl --context=$tmc_cluster get pods -n cert-manager | grep -E 'ImagePullBackOff|ErrImagePull' | awk '{ print $1 }' | xargs kubectl --context=$tmc_cluster delete pod -n cert-manager 2>/dev/null
done
echo "#####################################################################Creating ClusterIssuer on Cert-Manager#"
kubectl --context=$tmc_cluster create secret tls local-ca --key tmc-ca-no-pass.key --cert tmc-ca.crt -n cert-manager
kubectl --context=$tmc_cluster apply -f templates/common/local-issuer.yaml
ytt -f templates/values-template.yaml -f templates/common/tmc-values-template.yaml > values.yaml
echo "##############################################################################Deploying TMC-SM Package Repo#"
ytt -f templates/values-template.yaml -f templates/common/tmc-repo.yaml | kubectl --context=$tmc_cluster apply -f -
while [[ $(kubectl --context=$tmc_cluster get pkgr tanzu-mission-control-packages -n tmc-local -o=jsonpath='{.status.conditions[?(@.type=="ReconcileSucceeded")].status}') != "True" ]]; do
    echo "Waiting for tmc-repo to be ready: " $(kubectl --context=$tmc_cluster get pkgr tanzu-mission-control-packages -n tmc-local -o=jsonpath='{.status.conditions[0].type}')
    sleep 10
done

export valuesContent=$(cat values.yaml)
echo "###################################################################################Deploying TMC-SM Package#"
ytt -f templates/values-template.yaml --data-value valuesContent="$valuesContent" -f templates/common/tmc-install.yaml | kubectl --context=$tmc_cluster apply -f -
while [[ $(kubectl get pkgi tanzu-mission-control -n tmc-local -o=jsonpath='{.status.conditions[?(@.type=="ReconcileSucceeded")].status}') != "True" ]]; do
    echo "Waiting for tanzu-mission-control to be ready: " $(kubectl --context=$tmc_cluster get pkgi tanzu-mission-control -n tmc-local -o=jsonpath='{.status.conditions[0].type}')
    sleep 10
done
if [ "$ldap_auth" = "true" ]; then
    echo "#########################################################################################Deploying OpenLDAP#"
    ytt -f templates/values-template.yaml -f templates/common/openldap.yaml | kubectl --context=$tmc_cluster apply -f -
    kubectl --context=$tmc_cluster apply -f templates/common/ldap-overlay.yaml
    while [[ $(kubectl --context=$tmc_cluster get deployment openldap -n openldap -o=jsonpath='{.status.conditions[?(@.type=="Available")].status}') != "True" ]]; do
        echo "Waiting for openldap to be ready"
        export openldapCaCert=$(kubectl --context=$tmc_cluster get secret ldap -n openldap -o json | jq -r '.data."ca.crt"')
        sleep 10
    done
    sleep 30
    export openldapCaCert=$(kubectl --context=$tmc_cluster get secret ldap -n openldap -o json | jq -r '.data."ca.crt"')
    echo "######################################################################################Applying LDAP Overlay#"
    ytt -f  templates/common/ldap-auth.yaml --data-value ldapCa=$openldapCaCert | kubectl --context=$tmc_cluster apply -f -
    kubectl --context=$tmc_cluster annotate packageinstalls tanzu-mission-control -n tmc-local ext.packaging.carvel.dev/ytt-paths-from-secret-name.0=tmc-overlay-override
    kubectl --context=$tmc_cluster patch -n tmc-local --type merge pkgi tanzu-mission-control --patch '{"spec": {"paused": true}}'
    kubectl --context=$tmc_cluster patch -n tmc-local --type merge pkgi tanzu-mission-control --patch '{"spec": {"paused": false}}'
fi

kubectx $wcp_ip
export caCert=$(yq eval '.trustedCAs."custom-ca.pem"' ./values.yaml)
export tmcURL=$(yq eval '.dnsZone' ./values.yaml)
export tmcNS=$(kubectl get ns|grep svc-tmc|awk '{ print $1 }')
yq e -i ".spec.caCerts = strenv(caCert)" ./templates/common/agentconfig.yaml
yq e -i ".spec.allowedHostNames = [env(tmcURL)]" ./templates/common/agentconfig.yaml
yq e -i ".metadata.namespace = strenv(tmcNS)" ./templates/common/agentconfig.yaml
yq e -i ".metadata.namespace = strenv(tmcNS)" ./templates/common/agentinstall.yaml
echo "#######################################################################################Applying AgentConfig#"
kubectl --context=$wcp_ip apply -f ./templates/common/agentconfig.yaml

kubectx $tmc_cluster
echo "##################################################################################Finished Deploying TMC-SM#"
echo "-------------------"
echo Open TMC-SM via this URL: https://$tmc_dns
echo "-------------------"

echo "##########################################################################################Deploy EFK#"
ytt -f templates/values-template.yaml -f templates/demo/efk.yaml | kubectl --context=$tmc_cluster apply -f -
echo "##########################################################################################Deploy Sample App#"
ytt -f templates/values-template.yaml -f templates/demo/sample-app.yaml | kubectl --context=$tmc_cluster apply -f -
echo "#################################################################################################Deploy Dex#"
ytt -f templates/values-template.yaml -f templates/common/dex.yaml | kubectl --context=$tmc_cluster apply -f -
echo "##############################################################################################Deploy Octant#"
ytt -f templates/values-template.yaml -f templates/demo/octant.yaml | kubectl --context=$tmc_cluster apply -f -
echo "##############################################################################################Deploy Monitoring#"
kubectl --context=$tmc_cluster apply -f templates/demo/monitoring/00-namespace.yaml
kubectl --context=$tmc_cluster apply -f templates/demo/monitoring/01-dashboards/ --server-side
kubectl --context=$tmc_cluster apply -f templates/demo/monitoring/01-dashboards/tmc/ --server-side
ytt -f templates/values-template.yaml -f templates/demo/monitoring/02-deploy/ | kubectl --context=$tmc_cluster apply -f -
echo "###############################################################################################Deploy Minio#"
ytt -f templates/values-template.yaml -f templates/demo/minio.yaml | kubectl --context=$tmc_cluster apply -f -
while [[ $(kubectl --context=$tmc_cluster get deployment minio-deployment -n minio -o=jsonpath='{.status.conditions[?(@.type=="Available")].status}') != "True" ]]; do
    echo "Waiting for minio to be ready"
    sleep 10
    kubectl --context=$tmc_cluster get pods -n minio | grep -E 'ImagePullBackOff|ErrImagePull' | awk '{ print $1 }' | xargs kubectl --context=$tmc_cluster delete pod -n minio 2>/dev/null
done
mc alias set minio https://minio.$tmc_dns  minio minio123 --insecure
mc mb minio/velero --insecure
mc anonymous set download minio/velero --insecure
echo "################################################################################################Deploy Gitea#"
ytt -f templates/values-template.yaml -f templates/demo/git.yaml | kubectl --context=$tmc_cluster apply -f -
export gitea=git.$(yq eval '.tld_domain' ./templates/values-template.yaml)
while [[ $(kubectl --context=$tmc_cluster get pkgi gitea -n packages -o=jsonpath='{.status.conditions[?(@.type=="ReconcileSucceeded")].status}') != "True" ]]; do
    echo "Waiting for gitea to be ready"
    sleep 10
    kubectl --context=$tmc_cluster get pods -n gitea | grep -E 'ImagePullBackOff|ErrImagePull' | awk '{ print $1 }' | xargs kubectl --context=$tmc_cluster delete pod -n gitea 2>/dev/null
done
curl https://$gitea -k|grep html
export gitea_check=$?
if [ $gitea_check -eq 0 ]; then
    echo "Gitea is ready"
else
    echo ""
    echo "Gitea is not accessible"
    exit 1
fi
export gitea_pass='VMware1!'
export gitea_token=$(curl -X POST "https://tanzu:$gitea_pass@git.$tmc_dns/api/v1/users/tanzu/tokens" -H  "accept: application/json" -H "Content-Type: application/json" -d "{\"name\": \"token_name\"}" -k|jq -r .sha1)
curl -k -X POST "https://git.$tmc_dns/api/v1/user/repos" -H "content-type: application/json" -H "Authorization: token $gitea_token" --data '{"name":"tanzu-gitops","default_branch":"main"}' -k
cd airgapped-files/tanzu-gitops

git config --global user.email "tanzu@vmware.com"
git config --global user.name "tanzu"
git init
git checkout -b main
git add .
git commit -m "big bang"
git config http.sslVerify "false"
git remote add origin https://git.$tmc_dns/tanzu/tanzu-gitops.git
echo ""
echo "git user: tanzu / pass: VMware1!"
git push -u origin main
echo "##################################################################################Finished Deploying TMC-SM#"
echo "-------------------"
echo Open TMC-SM via this URL: https://$tmc_dns
echo "-------------------"