clusterVpcName=eks-cluster-vpc
germainDbHostname=""
germainDbInstanceType=db.t3.medium
germainDbSize=20
germainDbInstanceId=germain-db
germainDbName=germain
germainDbType=mysql
germainDbUser=germain
germainDbPass=germain-db
germainDbSubnetGrpName=germain-db-subnet-group

#############################################################################################################################
# DATABASE SUBNET GROUP
#############################################################################################################################

# Check if exists
sleepTime=${defaultSleepTime}
echo "Checking if DB subnet group exists..."
germainDbSubnetGrpArn=`aws rds describe-db-subnet-groups --db-subnet-group-name ${germainDbSubnetGrpName} --query "DBSubnetGroups[0].DBSubnetGroupArn" --output text 2>/dev/null`

if [[ ${germainDbSubnetGrpArn} = "None" || ${germainDbSubnetGrpArn} = "" ]]
then
	echo "Creating..."
	subnetIds=`aws cloudformation describe-stacks --stack-name ${clusterVpcName} --query "Stacks[0].Outputs[2].OutputValue" --output text 2>/dev/null`
	subnetIdsWithSpace=`echo "${subnetIds}" | tr , " "`
	aws rds create-db-subnet-group --db-subnet-group-name ${germainDbSubnetGrpName} --db-subnet-group-description "Germain DB subnet group" --subnet-ids ${subnetIdsWithSpace} --no-cli-pager
else
	echo "Already exists. Skipping creation..."
fi

# Check creation status
while [[ ${germainDbSubnetGrpArn} = "" || ${germainDbSubnetGrpArn} = "None" ]]
do
	if [[ ${sleepTime} -eq ${defaultSleepTime} ]]
	then
		echo "Waiting for DB subnet group to be ready..."
		sleepTime=5
	fi
	germainDbSubnetGrpArn=`aws rds describe-db-subnet-groups --db-subnet-group-name ${germainDbSubnetGrpName} --query "DBSubnetGroups[0].DBSubnetGroupArn" --output text 2>/dev/null`
	sleep ${sleepTime}
done

#############################################################################################################################
# DATABASE CREATION
#############################################################################################################################

if [[ ${germainDbHostname} = "" ]]
then
	# Check if exists
	sleepTime=${defaultSleepTime}
	echo "Checking if DB exists..."
	germainDbHostname=`aws rds describe-db-instances --db-instance-identifier germain-db --query "DBInstances[0].Endpoint.Address" --output text 2>/dev/null`

	if [[ ${germainDbHostname} = "None" || ${germainDbHostname} = "" ]]
	then
		echo "Creating..."
		aws rds create-db-instance --db-name ${germainDbName} --db-instance-class ${germainDbInstanceType} --allocated-storage ${germainDbSize} --engine ${germainDbType} --master-username ${germainDbUser} --master-user-password ${germainDbPass} --publicly-accessible --db-instance-identifier ${germainDbInstanceId} --db-subnet-group-name ${germainDbSubnetGrpName} --vpc-security-group-ids ${vpcSecurityGroupIds} --no-cli-pager
	else
		echo "Already exists. Skipping creation..."
	fi

	# Check creation status
	while [[ ${germainDbHostname} = "" || ${germainDbHostname} = "None" ]]
	do
		if [[ ${sleepTime} -eq ${defaultSleepTime} ]]
		then
			echo "Waiting for DB to be ready..."
			sleepTime=30
		fi
		germainDbHostname=`aws rds describe-db-instances --db-instance-identifier germain-db --query "DBInstances[0].Endpoint.Address" --output text 2>/dev/null`
		sleep ${sleepTime}
	done

	# Update security group to grant public access
	echo "Updating DB security group to grant public access..."
	aws ec2 authorize-security-group-ingress --group-id ${vpcSecurityGroupIds} --protocol tcp --port 3306 --cidr 0.0.0.0/0 --no-cli-pager 2>/dev/null
fi

echo "Installation ended at" $(date)

#############################################################################################################################
# PRINTOUT ANY REQUIRED PARAMETERS
#############################################################################################################################

# Update Database hostname in manifest file, if known
if [[ ${germainDbHostname} != "" ]]
then
	echo "Database Hostname:" ${germainDbHostname}
fi