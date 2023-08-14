installArgoCdClient="true"
argoCdGitSyncInterval="30s"

#############################################################################################################################
# DEPLOY ARGOCD TO CLUSTER
#############################################################################################################################

echo "Deploying ArgoCD to cluster..."
kubectl create namespace argocd 2>/dev/null
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
defaultPass=`kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d`

# GET DETAILS OF FRONTEND
echo "Retrieving ArgoCD frontend details..."
argoCdUrl=`kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'`
while [[ ${argoCdUrl} = "" || ${argoCdUrl} = "None" ]]
do
	argoCdUrl=`kubectl get svc server-lb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'`
	sleep ${sleepTime}
done

echo "ArgoCD public URL:" ${argoCdUrl}
echo "ArgoCD Username: admin"
echo "ArgoCD Password:" ${defaultPass}

#############################################################################################################################
# APPLY CUSTOM CONFIGURATIONS
#############################################################################################################################

rm -f ./argocd-custom.yaml
cp ./argocd-custom-template.yaml ./argocd-custom.yaml
sed -i "s|{{argoCdGitSyncInterval}}|${argoCdGitSyncInterval}|g" ./argocd-custom.yaml
kubectl apply -f ./argocd-custom.yaml
kubectl rollout restart deployment argocd-repo-server -n argocd

#############################################################################################################################
# INSTALL ARGOCD CLIENT
#############################################################################################################################

if [[ ${installArgoCdClient} = "true" ]]
then
	if [ ! -f "/usr/local/bin/argocd" ]; then
		echo "Installing ArgoCD client to local machine..."
		curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
		chmod +x /usr/local/bin/argocd
	fi
fi

echo "Installation completed at" $(date)

#############################################################################################################################


