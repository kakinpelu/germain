clusterName=eks-demo-cluster
clusterRoleName=eks-cluster-role
clusterRegion=us-west-2
clusterVpcName=eks-cluster-vpc

nodeKeyPairName=eks-demo-keypair
nodeKeyPairFileName=eks-demo-keypair.pem
nodeRoleName=eks-node-role
nodeGroupName=eks-node-group
nodeSecGrpName=nodegroup-sec-grp
minNodeGroupSize=10
maxNodeGroupSize=16
desiredNodeGroupSize=10
nodeInstanceType=t3.medium
nodeVolumeType=gp3
nodeVolumeSize=20
nodeGroupTemplate=EKSClusterNodeGroupTemplate
nodeGroupDescription=EKSClusterNodeGroup

#############################################################################################################################
# CLUSTER VPC
#############################################################################################################################

echo "Installation started at" $(date)

# Checking if exists
sleepTime=${defaultSleepTime}
echo "Checking if cluster vpc exists..."
vpcSecurityGroupIds=`aws cloudformation describe-stacks --stack-name ${clusterVpcName} --query "Stacks[0].Outputs[0].OutputValue" --output text 2>/dev/null`
clusterVpcId=`aws cloudformation describe-stacks --stack-name ${clusterVpcName} --query "Stacks[0].Outputs[1].OutputValue" --output text 2>/dev/null`
subnetIds=`aws cloudformation describe-stacks --stack-name ${clusterVpcName} --query "Stacks[0].Outputs[2].OutputValue" --output text 2>/dev/null`

if [[ ${vpcSecurityGroupIds} = "None" || ${clusterVpcId} = "None" || ${subnetIds} = "None" || ${vpcSecurityGroupIds} = "" || ${clusterVpcId} = "" || ${subnetIds} = "" ]]
then
	echo "Creating..."
	aws cloudformation create-stack --region ${clusterRegion} --stack-name ${clusterVpcName} --template-body file://"./amazon-eks-vpc.yaml" --no-cli-pager
else
	echo "Already exists. Skipping creation..."
fi

# Check creation status
while [[ ${vpcSecurityGroupIds} = "None" || ${clusterVpcId} = "None" || ${subnetIds} = "None" || ${vpcSecurityGroupIds} = "" || ${clusterVpcId} = "" || ${subnetIds} = "" ]]
do
	if [[ ${sleepTime} -eq ${defaultSleepTime} ]]
	then
		echo "Waiting for cluster vpc to be ready..."
		sleepTime=10
	fi
	vpcSecurityGroupIds=`aws cloudformation describe-stacks --stack-name ${clusterVpcName} --query "Stacks[0].Outputs[0].OutputValue" --output text 2>/dev/null`
	clusterVpcId=`aws cloudformation describe-stacks --stack-name ${clusterVpcName} --query "Stacks[0].Outputs[1].OutputValue" --output text 2>/dev/null`
	subnetIds=`aws cloudformation describe-stacks --stack-name ${clusterVpcName} --query "Stacks[0].Outputs[2].OutputValue" --output text 2>/dev/null`
	sleep ${sleepTime}
done

#############################################################################################################################
# CLUSTER ROLE
#############################################################################################################################

# Check if exists
sleepTime=${defaultSleepTime}
echo "Checking if cluster role exists..."
clusterRoleArn=`aws iam get-role --role-name ${clusterRoleName} --query "Role.Arn" --output text 2>/dev/null`

if [[ ${clusterRoleArn} = "" || ${clusterRoleArn} = "None" ]]
then
	echo "Creating..."
	aws iam create-role --role-name ${clusterRoleName} --assume-role-policy-document file://"./eks-cluster-role-trust-policy.json" --no-cli-pager
else
	echo "Already exists. Skipping creation..."
fi

# Check creation status
while [[ ${clusterRoleArn} = "" || ${clusterRoleArn} = "None" ]]
do
	if [[ ${sleepTime} -eq ${defaultSleepTime} ]]
	then
		echo "Waiting for cluster role to be ready..."
		sleepTime=5
	fi
	clusterRoleArn=`aws iam get-role --role-name ${clusterRoleName} --query "Role.Arn" --output text 2>/dev/null`
	sleep ${sleepTime}
done

# Attach policies
echo "Attaching policies to role..."
aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy --role-name ${clusterRoleName}
aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonEKSServicePolicy --role-name ${clusterRoleName}

#############################################################################################################################
# CLUSTER CREATION
#############################################################################################################################

# Check if exists
sleepTime=${defaultSleepTime}
echo "Checking if cluster exists..."
clusterStatus=`aws eks --region ${clusterRegion} describe-cluster --name ${clusterName} --query cluster.status --output text 2>/dev/null`

if [[ ${clusterStatus} != "ACTIVE" ]]
then
	echo "Creating..."
	aws eks create-cluster --region ${clusterRegion} --name ${clusterName} --role-arn ${clusterRoleArn} --resources-vpc-config subnetIds=${subnetIds},securityGroupIds=${vpcSecurityGroupIds} --no-cli-pager
else
	echo "Already exists. Skipping creation..."
fi

# Check creation status
clusterStatus=`aws eks --region ${clusterRegion} describe-cluster --name ${clusterName} --query cluster.status --output text 2>/dev/null`
while [[ ${clusterStatus} != "ACTIVE" ]]
do
	if [[ ${sleepTime} -eq ${defaultSleepTime} ]]
	then
		echo "Waiting for cluster to be ready..."
		sleepTime=30
	fi
	clusterStatus=`aws eks --region ${clusterRegion} describe-cluster --name ${clusterName} --query cluster.status --output text 2>/dev/null`
	sleep ${sleepTime}
done

#Attach kubectl to cluster once ready
echo "Attaching cluster to kubectl..."
aws eks --region ${clusterRegion} update-kubeconfig --name ${clusterName}

#############################################################################################################################
# WORKER NODES KEYPAIR
#############################################################################################################################

# Check if exists
sleepTime=${defaultSleepTime}
echo "Checking if keypair exists..."
keyStatus=`aws ec2 describe-key-pairs --key-names ${nodeKeyPairName} --output text 2>/dev/null`

if [[ ${keyStatus} = "" || ${keyStatus} = "None" ]]
then
	echo "Creating..."
	aws ec2 create-key-pair --key-name ${nodeKeyPairName} --key-type rsa --key-format pem --query "KeyMaterial" > ${nodeKeyPairFileName} --no-cli-pager
else
	echo "Already exists. Skipping creation..."
fi

# Check creation status
while [[ ${keyStatus} = "" || ${keyStatus} = "None" ]]
do
	if [[ ${sleepTime} -eq ${defaultSleepTime} ]]
	then
		echo "Waiting for keypair to be ready..."
		sleepTime=5
	fi
	keyStatus=`aws ec2 describe-key-pairs --key-names ${nodeKeyPairName} --output text 2>/dev/null`
	sleep ${sleepTime}
done

# Fix permission and character set issues in key file
sed -i 's|\\n|\n|g' ${nodeKeyPairFileName}
sed -i 's|"||g' ${nodeKeyPairFileName}
chmod 700 ${nodeKeyPairFileName}

#############################################################################################################################
# WORKER NODES ROLE
#############################################################################################################################

# Check if exists
sleepTime=${defaultSleepTime}
echo "Checking if nodegroupo role exists..."
nodeRoleArn=`aws iam get-role --role-name ${nodeRoleName} --query "Role.Arn" --output text 2>/dev/null`

if [[ ${nodeRoleArn} = "" || ${nodeRoleArn} = "None" ]]
then
	echo "Creating..."
	aws iam create-role --role-name ${nodeRoleName} --assume-role-policy-document file://"./node-role-trust-policy.json" --no-cli-pager
else
	echo "Already exists. Skipping creation..."
fi

# Check creation status
while [[ ${nodeRoleArn} = "" || ${nodeRoleArn} = "None" ]]
do
	if [[ ${sleepTime} -eq ${defaultSleepTime} ]]
	then
		echo "Waiting for nodegroup role to be ready..."
		sleepTime=5
	fi
	nodeRoleArn=`aws iam get-role --role-name ${nodeRoleName} --query "Role.Arn" --output text 2>/dev/null`
	sleep ${sleepTime}
done

# Attach policies
echo "Attaching policies to role..."
aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy --role-name ${nodeRoleName}
aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly --role-name ${nodeRoleName}
aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy --role-name ${nodeRoleName}

#############################################################################################################################
# WORKER NODES SECURITY GROUP
#############################################################################################################################

# Check if exists
sleepTime=${defaultSleepTime}
echo "Checking if nodegroup security group exists..."
nodeGrpSecId=`aws ec2 describe-security-groups --filters Name=group-name,Values=${nodeSecGrpName} Name=vpc-id,Values=${clusterVpcId} --query "SecurityGroups[0].GroupId" --output text 2>/dev/null`

if [[ ${nodeGrpSecId} = "" || ${nodeGrpSecId} = "None" ]]
then
	echo "Creating..."
	aws ec2 create-security-group --group-name ${nodeSecGrpName} --description "Worker nodes security group" --vpc-id ${clusterVpcId} --no-cli-pager
else
	echo "Already exists. Skipping creation..."
fi

# Check creation status
while [[ ${nodeGrpSecId} = "" || ${nodeGrpSecId} = "None" ]]
do
	if [[ ${sleepTime} -eq ${defaultSleepTime} ]]
	then
		echo "Waiting for nodegroup security group to be ready..."
		sleepTime=5
	fi
	nodeGrpSecId=`aws ec2 describe-security-groups --filters Name=group-name,Values=${nodeSecGrpName} Name=vpc-id,Values=${clusterVpcId} --query "SecurityGroups[0].GroupId" --output text 2>/dev/null`
	sleep ${sleepTime}
done

# Update security group to grant public access
echo "Updating nodegroup security group to grant public access..."
aws ec2 authorize-security-group-ingress --group-id ${nodeGrpSecId} --protocol tcp --port 22 --cidr 0.0.0.0/0 --no-cli-pager 2>/dev/null

#############################################################################################################################
# WORKER NODES TEMPLATE
#############################################################################################################################

# Check if exists
sleepTime=${defaultSleepTime}
echo "Checking if launch template exists..."
lauchTemplateId=`aws ec2 describe-launch-templates --launch-template-name ${nodeGroupTemplate} --query "LaunchTemplates[0].LaunchTemplateId" --output text 2>/dev/null`

if [[ ${lauchTemplateId} = "" || ${lauchTemplateId} = "None" ]]
then
	echo "Creating..."
	clusterSecurityGroupIds=`aws eks --region ${clusterRegion} describe-cluster --name ${clusterName} --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text 2>/dev/null`

	aws ec2 create-launch-template --launch-template-name ${nodeGroupTemplate} --version-description ${nodeGroupDescription} --launch-template-data "{\"NetworkInterfaces\":[{\"DeviceIndex\":0,\"AssociatePublicIpAddress\":true,\"Groups\":[\"${vpcSecurityGroupIds}\",\"${clusterSecurityGroupIds}\",\"${nodeGrpSecId}\"],\"DeleteOnTermination\":true}],\"KeyName\":\"${nodeKeyPairName}\",\"InstanceType\":\"${nodeInstanceType}\",\"TagSpecifications\":[{\"ResourceType\":\"instance\",\"Tags\":[{\"Key\":\"purpose\",\"Value\":\"eks-nodes\"}]}],\"BlockDeviceMappings\":[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":${nodeVolumeSize}, \"VolumeType\":\"${nodeVolumeType}\"}}]}" --region ${clusterRegion} --no-cli-pager
else
	echo "Already exists. Skipping creation..."
fi

# Check creation status
while [[ ${lauchTemplateId} = "" || ${lauchTemplateId} = "None" ]]
do
	if [[ ${sleepTime} -eq ${defaultSleepTime} ]]
	then
		echo "Waiting for lauch template to be ready..."
		sleepTime=5
	fi
	lauchTemplateId=`aws ec2 describe-launch-templates --launch-template-name ${nodeGroupTemplate} --query "LaunchTemplates[0].LaunchTemplateId" --output text 2>/dev/null`
	sleep ${sleepTime}
done

#############################################################################################################################
# WORKER NODES CREATION
#############################################################################################################################

# Check if exists
sleepTime=${defaultSleepTime}
echo "Checking if nodegroup exists..."
nodeGroup=`aws eks describe-nodegroup --cluster-name ${clusterName} --nodegroup-name ${nodeGroupName} --query "nodegroup.status" --output text 2>/dev/null`

if [[ ${nodeGroup} = "" || ${nodeGroup} = "None" ]]
then
	echo "Creating..."
	subnetIdsWithSpace=`echo "${subnetIds}" | tr , " "`

	# Create managed node group with template
	aws eks create-nodegroup --cluster-name ${clusterName} --nodegroup-name ${nodeGroupName} --node-role ${nodeRoleArn} --scaling-config minSize=${minNodeGroupSize},maxSize=${maxNodeGroupSize},desiredSize=${desiredNodeGroupSize} --subnets ${subnetIdsWithSpace} --launch-template version=1,id=${lauchTemplateId} --no-cli-pager

else
	echo "Already exists. Skipping creation..."
fi

# Check creation status
while [[ ${nodeGroup} = "" || ${nodeGroup} = "None" ]]
do
	if [[ ${sleepTime} -eq ${defaultSleepTime} ]]
	then
		echo "Waiting for nodegroup to be ready..."
		sleepTime=30
	fi
	nodeGroup=`aws eks describe-nodegroup --cluster-name ${clusterName} --nodegroup-name ${nodeGroupName} --query "nodegroup.status" --output text 2>/dev/null`
	sleep ${sleepTime}
done

#############################################################################################################################
# INSTALL EKSCTL - IF NOT ALREADY INSTALLED
#############################################################################################################################

# if [ ! -f "/usr/local/bin/eksctl" ]; then
	# architecture=""
	# case $(uname -m) in
	#     i386 | i686)   architecture="386" ;;
	#     x86_64) architecture="amd64" ;;
	#     arm)    dpkg --print-architecture | grep -q "arm64" && architecture="arm64" || architecture="arm" ;;
	# esac

	# curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_${architecture}.tar.gz" | tar xz -C /tmp;
	# sudo mv /tmp/eksctl /usr/local/bin
# fi

#############################################################################################################################
# INSTALL OIDC PROVIDER
#############################################################################################################################

# Check if exists
sleepTime=${defaultSleepTime}
echo "Checking if OIDC provider exists..."
clusterId=`aws eks describe-cluster --name ${clusterName} --query "cluster.identity.oidc.issuer" --output text | cut -d '/' -f 5 --output text 2>/dev/null`
oidcProvider=`aws iam list-open-id-connect-providers | grep ${clusterId} | cut -d "/" -f4`

if [[ ${oidcProvider} = "" ]]
then
	echo "Creating..."
	eksctl utils associate-iam-oidc-provider --cluster ${clusterName} --approve
else
	echo "Already exists. Skipping creation..."
fi

# Check creation status
while [[ ${oidcProvider} = "" ]]
do
	if [[ ${sleepTime} -eq ${defaultSleepTime} ]]
	then
		echo "Waiting for OIDC provider to be ready..."
		sleepTime=5
	fi
	oidcProvider=`aws iam list-open-id-connect-providers | grep ${clusterId} | cut -d "/" -f4`
	sleep ${sleepTime}
done

#############################################################################################################################
# CREATE EBS ROLE
#############################################################################################################################

# Check if exists
sleepTime=${defaultSleepTime}
echo "Checking if ebs driver role exists..."
ebsDriverRoleName=AmazonEKS_EBS_CSI_DriverRole
ebsRoleArn=`aws iam get-role --role-name ${ebsDriverRoleName} --query "Role.Arn" --output text 2>/dev/null`

if [[ ${ebsRoleArn} = "" || ${ebsRoleArn} = "None" ]]
then
	awsAccountId=`aws sts get-caller-identity --query "Account" --output text`
	rm -f ./aws-ebs-csi-driver-trust-policy.json
	cp ./aws-ebs-csi-driver-trust-policy-template.json ./aws-ebs-csi-driver-trust-policy.json
	sed -i "s|{{awsAccountId}}|${awsAccountId}|g" ./aws-ebs-csi-driver-trust-policy.json
	sed -i "s|{{clusterId}}|${clusterId}|g" ./aws-ebs-csi-driver-trust-policy.json
	sed -i "s|{{clusterRegion}}|${clusterRegion}|g" ./aws-ebs-csi-driver-trust-policy.json

	echo "Creating..."
	aws iam create-role --role-name ${ebsDriverRoleName} --assume-role-policy-document file://"./aws-ebs-csi-driver-trust-policy.json" --no-cli-pager
else
	echo "Already exists. Skipping creation..."
fi

# Check creation status
while [[ ${ebsRoleArn} = "" || ${ebsRoleArn} = "None" ]]
do
	if [[ ${sleepTime} -eq ${defaultSleepTime} ]]
	then
		echo "Waiting for ebs driver role to be ready..."
		sleepTime=5
	fi
	ebsRoleArn=`aws iam get-role --role-name ${ebsDriverRoleName} --query "Role.Arn" --output text 2>/dev/null`
	sleep ${sleepTime}
done

# Attach policies
echo "Attaching policies to role..."
aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy --role-name ${ebsDriverRoleName}

#############################################################################################################################
# INSTALL EBS DRIVER ADDON
#############################################################################################################################

# Check if exists
sleepTime=${defaultSleepTime}
echo "Checking if ebs addon exists..."
ebsAddonStatus=`aws eks describe-addon --region ${clusterRegion} --cluster-name ${clusterName} --addon-name aws-ebs-csi-driver --query "addon.status" --output text 2>/dev/null`

if [[ ${ebsAddonStatus} = "" ]]
then
	echo "Creating..."
	aws eks create-addon --cluster-name ${clusterName} --addon-name aws-ebs-csi-driver --service-account-role-arn ${ebsRoleArn} --no-cli-pager
else
	echo "Already exists. Skipping creation..."
fi

# Check creation status
ebsAddonStatus=`aws eks describe-addon --region ${clusterRegion} --cluster-name ${clusterName} --addon-name aws-ebs-csi-driver --query "addon.status" --output text 2>/dev/null`
while [[ ${ebsAddonStatus} != "ACTIVE" ]]
do
	if [[ ${sleepTime} -eq ${defaultSleepTime} ]]
	then
		echo "Waiting for ebs addon to be ready..."
		sleepTime=10
	fi
	ebsAddonStatus=`aws eks describe-addon --region ${clusterRegion} --cluster-name ${clusterName} --addon-name aws-ebs-csi-driver --query "addon.status" --output text 2>/dev/null`
	sleep ${sleepTime}
done

echo "Installation ended at" $(date)