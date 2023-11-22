#!/bin/bash

if [ $# -ne 1 ]; then
    echo "Usage: $0 gen-cert|prep|deploy-harbor|import-cli|import-packages|post-install|login"
    exit 1
fi


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
    echo "All binaries are present."
fi

yq eval '.' ./templates/values-template.yaml
export yaml_check=$?

if [ $yaml_check -eq 0 ]; then
    echo "Valid yaml structure for: values-template.yaml . Continuing."
else
    echo ""
    echo "Invalid yaml structure for: values-template.yaml . Check values-template.yaml"
    exit 1
fi

export TLD_DOMAIN=$(yq eval '.tld_domain' ./templates/values-template.yaml)
export DOMAIN=*.$TLD_DOMAIN
export std_repo=$(yq eval '.std_repo' ./templates/values-template.yaml)
export tmc_repo=$(yq eval '.tmc_repo' ./templates/values-template.yaml)
export TMC_SM_DL_URL="https://artifactory.eng.vmware.com/artifactory/tmc-generic-local/bundle-$tmc_repo.tar"

if [ "$1" = "prep" ]; then
    echo prep
    mkdir -p airgapped-files/images/inspection
    mkdir -p airgapped-files/tools
    mkdir -p airgapped-files/ova
    mkdir -p airgapped-files/chart-images
    wget -P airgapped-files/ "$TMC_SM_DL_URL"
    templates/carvel.sh download
    wget --content-disposition -P airgapped-files/ "https://dl.min.io/client/mc/release/linux-amd64/mc" && chmod +x airgapped-files/mc
    imgpkg copy -b projects.registry.vmware.com/tkg/packages/standard/repo:$std_repo --to-tar airgapped-files/$std_repo.tar --include-non-distributable-layers --concurrency 30
    imgpkg copy -i ghcr.io/carvel-dev/kapp-controller@sha256:8011233b43a560ed74466cee4f66246046f81366b7695979b51e7b755ca32212 --to-tar=airgapped-files/images/kapp-controller.tar --concurrency 30
    imgpkg copy -i projects.registry.vmware.com/tanzu_meta_pocs/tools/busybox:latest --to-tar=airgapped-files/images/busybox.tar --concurrency 30
    imgpkg copy -i projects.registry.vmware.com/tanzu_meta_pocs/tools/openldap:1.2.4 --to-tar=airgapped-files/images/openldap.tar --concurrency 30
    imgpkg copy -i projects.registry.vmware.com/tanzu_meta_pocs/sample-app/postgres:latest --to-tar=airgapped-files/images/postgres.tar --concurrency 30
    imgpkg copy -i projects.registry.vmware.com/tanzu_meta_pocs/sample-app/mongo:latest --to-tar=airgapped-files/images/mongo.tar --concurrency 30
    imgpkg copy -i projects.registry.vmware.com/tanzu_meta_pocs/sample-app/redis:latest --to-tar=airgapped-files/images/redis.tar --concurrency 30
    imgpkg copy -i projects.registry.vmware.com/tanzu_meta_pocs/sample-app/elasticsearch:7.2.1 --to-tar=airgapped-files/images/elasticsearch.tar --concurrency 30
    imgpkg copy -i projects.registry.vmware.com/tanzu_meta_pocs/sample-app/bitnami-shell:10-debian-10-r138 --to-tar=airgapped-files/images/bitnami-shell.tar --concurrency 30
    imgpkg copy -i projects.registry.vmware.com/tanzu_meta_pocs/sample-app/mysql:5.7 --to-tar=airgapped-files/images/mysql.tar --concurrency 30
    imgpkg copy -i projects.registry.vmware.com/tanzu_meta_pocs/sample-app/rabbitmq:3.8 --to-tar=airgapped-files/images/rabbitmq.tar --concurrency 30
    imgpkg copy -i projects.registry.vmware.com/tanzu_meta_pocs/sample-app/sample-app:v0.3.27 --to-tar=airgapped-files/images/sample-app.tar --concurrency 30
    imgpkg copy -b projects.registry.vmware.com/tanzu_meta_pocs/tools/gitea:1.15.3_3 --to-tar=airgapped-files/images/gitea-bundle.tar --include-non-distributable-layers --concurrency 30
    imgpkg copy -i projects.registry.vmware.com/tanzu_meta_pocs/extensions/kibana:7.2.1 --to-tar=airgapped-files/images/kibana.tar --concurrency 30
    imgpkg copy -i projects.registry.vmware.com/tanzu_meta_pocs/tools/minio:latest --to-tar=airgapped-files/images/minio.tar --concurrency 30
    imgpkg copy -i projects.registry.vmware.com/tanzu_meta_pocs/tools/dex:v2.35.3 --to-tar=airgapped-files/images/dex.tar --concurrency 30
    imgpkg copy -i projects.registry.vmware.com/tanzu_meta_pocs/tools/octant-dashboard:v0.25.1 --to-tar=airgapped-files/images/octant.tar --concurrency 30
    imgpkg copy -i projects.registry.vmware.com/tanzu_meta_pocs/tools/oauth2-proxy:7.2.1 --to-tar=airgapped-files/images/oauth2-proxy.tar --concurrency 30
    imgpkg copy -i projects.registry.vmware.com/tanzu_meta_pocs/monitoring/kube-state-metrics/kube-state-metrics:v2.3.0 --to-tar=airgapped-files/images/kube-state-metrics.tar --concurrency 30
    imgpkg copy -i projects.registry.vmware.com/tanzu_meta_pocs/monitoring/prom/node-exporter:latest --to-tar=airgapped-files/images/node-exporter.tar --concurrency 30
    imgpkg copy -i projects.registry.vmware.com/tanzu_meta_pocs/monitoring/prom/prometheus:latest --to-tar=airgapped-files/images/prometheus.tar --concurrency 30
    imgpkg copy -i projects.registry.vmware.com/tanzu_meta_pocs/monitoring/grafana/grafana:latest --to-tar=airgapped-files/images/grafana.tar --concurrency 30
    imgpkg copy -i projects.registry.vmware.com/tanzu_meta_pocs/tools/utils:latest --to-tar=airgapped-files/images/utils.tar --concurrency 30
    wget --content-disposition -P airgapped-files/ova "https://via.vmw.com/tanzu-poc-harbor-int" && mv airgapped-files/ova/photon-4-harbor-v2.6.3+vmware.1-9c5c48c408fac6cef43c4752780c4b048e42d562.ova airgapped-files/ova/photon-4-harbor-v2.6.3.ova
    wget --content-disposition -P airgapped-files/ova "https://via.vmw.com/tanzu-poc-sivt"
    wget --content-disposition -P airgapped-files/ "https://github.com/bitnami/charts/archive/refs/heads/main.zip" && mv airgapped-files/charts-main.zip airgapped-files/bitnami-charts.zip
    wget --content-disposition -P airgapped-files/ "https://github.com/vmware-labs/distribution-tooling-for-helm/releases/download/v0.2.2/distribution-tooling-for-helm_0.2.2_linux_amd64.tar.gz"
    #export k8s_versions=(v1.23.8 v1.23.15 v1.24.9)
    #wget -P airgapped-files/ "https://github.com/vmware-tanzu/sonobuoy/releases/download/v0.56.16/sonobuoy_0.56.16_linux_amd64.tar.gz"
    #tar -xvf airgapped-files/sonobuoy*.tar.gz
    #for i in "${k8s_versions[@]}"
    #do
    #   ./sonobuoy images list --kubernetes-version $i > images_$i.txt
    #   while read image
    #   do
    #     export base=$(basename "$image")
    #     export output=${image#*/*}
    #     imgpkg copy -i $image --to-tar=airgapped-files/images/inspection/$base.tar --concurrency 30
    #   done < images_$i.txt
    #done
    git clone https://github.com/gorkemozlu/tanzu-gitops airgapped-files/tanzu-gitops && rm -rf airgapped-files/tanzu-gitops/.git
    wget --content-disposition -P airgapped-files/tools/ "https://code.visualstudio.com/sha/download?build=stable&os=win32-x64-archive"
    wget --content-disposition -P airgapped-files/tools/ "https://code.visualstudio.com/sha/download?build=stable&os=darwin-universal"
    wget --content-disposition -P airgapped-files/tools/ "https://the.earth.li/~sgtatham/putty/latest/w64/putty.exe"
    wget --content-disposition -P airgapped-files/tools/ "https://winscp.net/download/WinSCP-6.1.1-Setup.exe"
    wget --content-disposition -P airgapped-files/tools/ "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.5.4/npp.8.5.4.portable.x64.zip"
    cd airgapped-files/chart-images && dt wrap oci://docker.io/bitnamicharts/nginx
elif [ "$1" = "import-cli" ]; then
    echo import-cli
    templates/carvel.sh install
    cp airgapped-files/mc /usr/local/bin/mc
    cd airgapped-files/ && tar -xvf distribution-tooling-for-helm_0.2.2_linux_amd64.tar.gz && cp dt /usr/local/bin/dt
elif [ "$1" = "deploy-harbor" ]; then
    echo deploy-harbor
    templates/harbor/harbor-deploy.sh
elif [ "$1" = "import-packages" ]; then
    echo import-packages
    if [ -f tmc-ca.crt ] ; then
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
        cp tmc-ca.crt /etc/ssl/certs/
        echo "required files exist, continuing."
        if [ ! -f all-ca.crt ] ; then
            export OTHER_CA_CERT=$(yq eval '.trustedCAs.other_ca' ./templates/values-template.yaml)
            export ALL_CA_CERT=$(echo -e "$TMC_CA_CERT""\n""$OTHER_CA_CERT")
            echo "$ALL_CA_CERT" > ./all-ca.crt
            echo "$ALL_CA_CERT" > /etc/ssl/certs/all-ca.crt
        else
            export ALL_CA_CERT=$(cat ./all-ca.crt)
        fi
    else
        echo "no tmc-ca.crt fall back to values-template.yaml"
        export TMC_CA_CERT=$(yq eval '.trustedCAs.tmc_ca' ./templates/values-template.yaml)
        export OTHER_CA_CERT=$(yq eval '.trustedCAs.other_ca' ./templates/values-template.yaml)
        export ALL_CA_CERT=$(echo -e "$TMC_CA_CERT""\n""$OTHER_CA_CERT")
        echo "$ALL_CA_CERT" > ./all-ca.crt
        echo "$ALL_CA_CERT" > /etc/ssl/certs/all-ca.crt
    fi
    export HARBOR_URL=$(yq eval '.harbor.fqdn' ./templates/values-template.yaml)
    export HARBOR_USER=$(yq eval '.harbor.user' ./templates/values-template.yaml)
    export HARBOR_PASS=$(yq eval '.harbor.pass' ./templates/values-template.yaml)
    export HARBOR_CERT=$(echo | openssl s_client -connect $HARBOR_URL:443 2>&1 | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p') && [[ -z "$HARBOR_CERT" ]] && { echo "HARBOR_CERT is empty"; exit 1; }
    openssl verify -CAfile <(echo "$ALL_CA_CERT") <(echo "$HARBOR_CERT")
    export harbor_cert_check=$?
    if [ $harbor_cert_check -eq 0 ]; then
        echo "Valid Harbor Cert , Continuing."
    else
        echo ""
        echo "INVALID Harbor Cert , Check Harbor Cert and CA Cert."
        exit 1
    fi
    tar -xvf airgapped-files/bundle*.tar
    export IMGPKG_REGISTRY_USERNAME=$HARBOR_USER && export IMGPKG_REGISTRY_PASSWORD=$HARBOR_PASS &&  export IMGPKG_REGISTRY_HOSTNAME=$HARBOR_URL
    curl -u "${IMGPKG_REGISTRY_USERNAME}:${IMGPKG_REGISTRY_PASSWORD}" -X POST -H "content-type: application/json" "https://$HARBOR_URL/api/v2.0/projects" -d "{\"project_name\": \"tmc\", \"public\": true, \"storage_limit\": -1 }" -k
    curl -u "${IMGPKG_REGISTRY_USERNAME}:${IMGPKG_REGISTRY_PASSWORD}" -X POST -H "content-type: application/json" "https://$HARBOR_URL/api/v2.0/projects" -d "{\"project_name\": \"bitnami-chart-images\", \"public\": true, \"storage_limit\": -1 }" -k
    ./tmc-sm push-images harbor --project $HARBOR_URL/tmc --username $HARBOR_USER --password $HARBOR_PASS --concurrency 10
    imgpkg copy --tar airgapped-files/$std_repo.tar --to-repo $HARBOR_URL/tmc/498533941640.dkr.ecr.us-west-2.amazonaws.com/packages/standard/repo --include-non-distributable-layers
    imgpkg copy --tar airgapped-files/images/kapp-controller.tar --to-repo $HARBOR_URL/tmc/kapp-controller --include-non-distributable-layers
    imgpkg copy --tar airgapped-files/images/busybox.tar --to-repo $HARBOR_URL/tmc/busybox --include-non-distributable-layers
    imgpkg copy --tar airgapped-files/images/openldap.tar --to-repo $HARBOR_URL/tmc/openldap --include-non-distributable-layers
    curl -u "${IMGPKG_REGISTRY_USERNAME}:${IMGPKG_REGISTRY_PASSWORD}" -X POST -H "content-type: application/json" "https://$HARBOR_URL/api/v2.0/projects" -d "{\"project_name\": \"apps\", \"public\": true, \"storage_limit\": -1 }" -k
    imgpkg copy --tar airgapped-files/images/postgres.tar --to-repo $HARBOR_URL/apps/postgres --include-non-distributable-layers
    imgpkg copy --tar airgapped-files/images/mongo.tar --to-repo $HARBOR_URL/apps/mongo --include-non-distributable-layers
    imgpkg copy --tar airgapped-files/images/redis.tar --to-repo $HARBOR_URL/apps/redis --include-non-distributable-layers
    imgpkg copy --tar airgapped-files/images/elasticsearch.tar --to-repo $HARBOR_URL/apps/elasticsearch --include-non-distributable-layers
    imgpkg copy --tar airgapped-files/images/bitnami-shell.tar --to-repo $HARBOR_URL/apps/bitnami-shell --include-non-distributable-layers
    imgpkg copy --tar airgapped-files/images/mysql.tar --to-repo $HARBOR_URL/apps/mysql --include-non-distributable-layers
    imgpkg copy --tar airgapped-files/images/rabbitmq.tar --to-repo $HARBOR_URL/apps/rabbitmq --include-non-distributable-layers
    imgpkg copy --tar airgapped-files/images/sample-app.tar --to-repo $HARBOR_URL/apps/sample-app --include-non-distributable-layers
    imgpkg copy --tar airgapped-files/images/kibana.tar --to-repo $HARBOR_URL/apps/kibana --include-non-distributable-layers
    imgpkg copy --tar airgapped-files/images/gitea-bundle.tar --to-repo $HARBOR_URL/apps/gitea --include-non-distributable-layers
    imgpkg copy --tar airgapped-files/images/minio.tar --to-repo $HARBOR_URL/apps/minio --include-non-distributable-layers
    imgpkg copy --tar airgapped-files/images/dex.tar --to-repo $HARBOR_URL/apps/dex --include-non-distributable-layers
    imgpkg copy --tar airgapped-files/images/octant.tar --to-repo $HARBOR_URL/apps/octant-dashboard --include-non-distributable-layers
    imgpkg copy --tar airgapped-files/images/oauth2-proxy.tar --to-repo $HARBOR_URL/apps/oauth2-proxy --include-non-distributable-layers
    imgpkg copy --tar airgapped-files/images/kube-state-metrics.tar --to-repo $HARBOR_URL/apps/kube-state-metrics --include-non-distributable-layers
    imgpkg copy --tar airgapped-files/images/node-exporter.tar --to-repo $HARBOR_URL/apps/node-exporter --include-non-distributable-layers
    imgpkg copy --tar airgapped-files/images/prometheus.tar --to-repo $HARBOR_URL/apps/prometheus --include-non-distributable-layers
    imgpkg copy --tar airgapped-files/images/grafana.tar --to-repo $HARBOR_URL/apps/grafana --include-non-distributable-layers
    imgpkg copy --tar airgapped-files/images/utils.tar --to-repo $HARBOR_URL/apps/utils --include-non-distributable-layers
    docker login $HARBOR_URL  -u $HARBOR_USER -p $HARBOR_PASS
    dt unwrap airgapped-files/chart-images/nginx-15.4.3.wrap.tgz $HARBOR_URL/bitnami-chart-images --yes
    #for file in airgapped-files/images/inspection/*.tar; do
    #    if [ -f "$file" ]; then
    #        section="${file%%:*}"
    #        base=$(basename "$section")
    #        echo $section $base
    #        imgpkg copy --tar "$file" --to-repo "${HARBOR_URL}/tmc/498533941640.dkr.ecr.us-west-2.amazonaws.com/extensions/inspection-images/$base" --include-non-distributable-layers
    #    fi
    #done
    export es_old_image='projects.registry.vmware.com/tanzu_meta_pocs/extensions/elasticsearch:7.2.1' && export es_new_image=$HARBOR_URL/apps/elasticsearch:7.2.1 && sed -i -e "s~$es_old_image~$es_new_image~g" airgapped-files/tanzu-gitops/tmc-cg/apps/efk/elasticsearch.yaml
    export kb_old_image='projects.registry.vmware.com/tanzu_meta_pocs/extensions/kibana:7.2.1' && export kb_new_image=$HARBOR_URL/apps/kibana:7.2.1 && sed -i -e "s~$kb_old_image~$kb_new_image~g" airgapped-files/tanzu-gitops/tmc-cg/apps/efk/kibana.yaml
    export sh_old_image='projects.registry.vmware.com/tanzu_meta_pocs/extensions/bitnami-shell:10-debian-10-r138' && export sh_new_image=$HARBOR_URL/apps/bitnami-shell:10-debian-10-r138 && sed -i -e "s~$sh_old_image~$sh_new_image~g" airgapped-files/tanzu-gitops/tmc-cg/apps/efk/elasticsearch.yaml
    export pkgr_old_image='projects.registry.vmware.com/tkg/packages/standard/repo:v2.2.0_update.2' && export pkgr_new_image=$HARBOR_URL/tmc/498533941640.dkr.ecr.us-west-2.amazonaws.com/packages/standard/repo:v2.2.0_update.2 && sed -i -e "s~$pkgr_old_image~$pkgr_new_image~g" airgapped-files/tanzu-gitops/tmc-cg/02-service-accounts/package-repo/package-repo.yaml
    templates/tld-local-fix.sh
elif [ "$1" = "gen-cert" ]; then
    templates/gen-cert.sh
elif [ "$1" = "post-install" ]; then
    kubectl get httpproxy -A
    echo "-------------------"
    kubectl get svc -A|grep LoadBalancer
    echo "-------------------"
    echo "on vSphere 8, run below command on supervisor level before creating workload cluster "
    echo " "
    echo "ytt -f templates/values-template.yaml -f templates/vsphere-8/cluster-config.yaml | kubectl apply -f -"
elif [ "$1" = "login" ]; then
    export wcp_ip=$(yq eval '.wcp.ip' ./templates/values-template.yaml)
    export wcp_user=$(yq eval '.wcp.user' ./templates/values-template.yaml)
    export wcp_pass=$(yq eval '.wcp.password' ./templates/values-template.yaml)
    export namespace=$(yq eval '.shared_cluster.namespace' ./templates/values-template.yaml)
    export KUBECTL_VSPHERE_PASSWORD=$wcp_pass
    kubectl vsphere login --server=$wcp_ip --vsphere-username $wcp_user --insecure-skip-tls-verify
    kubectl vsphere login --server=$wcp_ip --tanzu-kubernetes-cluster-name shared --tanzu-kubernetes-cluster-namespace $namespace --vsphere-username $wcp_user --insecure-skip-tls-verify 2>/dev/null
fi