#!/bin/bash

# Ask for user description identifier
read -p "Enter Your Security Group rule description: " partDescription
echo ""

# Get your current IP address
myIP=`curl checkip.amazonaws.com 2>/dev/null`

# Get the details of the security groups where your (possibly) old IP address is configured and replace with current IP address
sGroupsMyIp=`aws ec2 describe-security-groups | jq -r --arg partDescription "$partDescription"  '.SecurityGroups[]? as $sg | $sg.IpPermissions[]? as $ipPerm | $ipPerm.IpRanges[]? as $ipRange | {sgId: $sg.GroupId, fromPort: $ipPerm.FromPort, ipProtocol: $ipPerm.IpProtocol, cidrIp: $ipRange.CidrIp, description: $ipRange.Description} | select (.description | try contains($partDescription))'`

for sGroupId in `echo $sGroupsMyIp | jq '.sgId' | sort | uniq | sed 's:"::g'`
do
  sgRuleDetail=`echo $sGroupsMyIp | jq --arg sGroupId "$sGroupId" 'select(.sgId | contains($sGroupId))'`
  fromPort=`echo $sgRuleDetail | jq '.fromPort'`
  ipProtocol=`echo $sgRuleDetail | jq '.ipProtocol' | sed 's:"::g'`
  cidrIp=`echo $sgRuleDetail | jq '.cidrIp' | sed 's:"::g'`

  # There can be multiple IP allowlisted for same person
  ipCount=`echo $cidrIp | awk '{print NF}'`

  for i in $(seq 1 $ipCount)
  do
    protocol=`echo $ipProtocol | awk '{print $'$i'}'`
    port=`echo $fromPort | awk '{print $'$i'}'`
    cidr=`echo $cidrIp | awk '{print $'$i'}'`

    # Delete existing(old) IP allowlisting
    echo -e "Revoking Inbound rule for Security Group ($sGroupId): Protocol=$protocol, Port=$port, Source=$cidr"
    aws ec2 revoke-security-group-ingress --group-id $sGroupId --protocol $protocol --port $port --cidr $cidr

    # Add current IP allowlisting
    echo -e "Adding Inbound rule for Security Group ($sGroupId): Protocol=$protocol, Port=$port, Source=$myIP/32\n"
    ipVar="IpProtocol=$protocol,FromPort=$port,ToPort=$port,IpRanges=[{CidrIp=$myIP/32,Description=\"$partDescription\"}]"
    aws ec2 authorize-security-group-ingress --group-id $sGroupId --ip-permissions "$ipVar"
  done
done
