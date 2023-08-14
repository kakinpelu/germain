manifestDirectory=germainux

#############################################################################################################################
# DEPLOYMENT
#############################################################################################################################

kubectl apply -f ./${manifestDirectory} --recursive

#############################################################################################################################
# GET ADDRESS OF WORKSPACE
#############################################################################################################################

# Check creation status
germainUrl=`kubectl get svc server-lb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'`
while [[ ${germainUrl} = "" || ${germainUrl} = "None" ]]
do
	echo "Waiting for public URL to be ready..."
	germainUrl=`kubectl get svc server-lb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'`
	sleep ${sleepTime}
done

echo "Germain public URL:" ${germainUrl}

################################################################################################################