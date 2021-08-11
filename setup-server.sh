#!/bin/bash
set -x

export AWS_UBUNTU_20_04_AMI_US_WEST_2=ami-0928f4202481dfdf6
export AWS_REGION=us-west-2

export ROUTE_53_HOSTED_ZONE_ID=$(sops --decrypt --extract '["ROUTE_53_HOSTED_ZONE_ID_unencrypted"]' secrets.yaml)
export EC2_VPC_ID=$(sops --decrypt --extract '["EC2_VPC_ID_unencrypted"]' secrets.yaml)
export SERVER_1_SUBNET_ID=$(sops --decrypt --extract '["SERVER_1_SUBNET_ID_unencrypted"]' secrets.yaml)
export SERVER_2_SUBNET_ID=$(sops --decrypt --extract '["SERVER_2_SUBNET_ID_unencrypted"]' secrets.yaml)
export SERVER_1_DOMAIN=$(sops --decrypt --extract '["SERVER_1_DOMAIN_unencrypted"]' secrets.yaml)
export SERVER_2_DOMAIN=$(sops --decrypt --extract '["SERVER_2_DOMAIN_unencrypted"]' secrets.yaml)
export WIREGUARD_DOCKER_IMAGE=$(sops --decrypt --extract '["WIREGUARD_DOCKER_IMAGE_unencrypted"]' secrets.yaml)
export SERVER_1_PUBLIC_KEY=$(sops --decrypt --extract '["SERVER_1_PUBLIC_KEY"]' secrets.yaml)
export SERVER_1_PRIVATE_KEY=$(sops --decrypt --extract '["SERVER_1_PRIVATE_KEY"]' secrets.yaml)
export SERVER_2_PUBLIC_KEY=$(sops --decrypt --extract '["SERVER_2_PUBLIC_KEY"]' secrets.yaml)
export SERVER_2_PRIVATE_KEY=$(sops --decrypt --extract '["SERVER_2_PRIVATE_KEY"]' secrets.yaml)

export EC2_SECURITY_GROUP_ID=$(aws ec2 create-security-group \
--group-name wireguard-ssh \
--description wireguard-ssh \
--vpc-id $EC2_VPC_ID \
--query GroupId)

export CURRENT_PUBLIC_IP=$(curl ifconfig.me)

aws ec2 authorize-security-group-ingress \
--group-name wireguard-ssh \
--protocol tcp \
--port 22 \
--cidr $CURRENT_PUBLIC_IP/32

aws ec2 create-key-pair \
--key-name wireguard-servers \
--query KeyMaterial \
--output text > wireguard-servers.pem

chmod 600 wireguard-servers.pem

aws ec2 run-instances \
--tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=wireguard1}]' 'ResourceType=volume,Tags=[{Key=Name,Value=wireguard1-disk}]'
--image-id $AWS_UBUNTU_20_04_AMI_US_WEST_2 \
--count 1 \
--instance-type t4g.micro \
--key-name wireguard \
--security-group-ids $EC2_SECURITY_GROUP_ID \
--associate-public-ip-address \
--subnet-id $SERVER_1_SUBNET_ID

aws ec2 run-instances \
--tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=wireguard2}]' 'ResourceType=volume,Tags=[{Key=Name,Value=wireguard2-disk}]' \
--image-id $AWS_UBUNTU_20_04_AMI_US_WEST_2 \
--count 1 \
--instance-type t4g.micro \
--key-name wireguard \
--security-group-ids $EC2_SECURITY_GROUP_ID \
-- associate-public-ip-address \
--subnet-id $SERVER_2_SUBNET_ID

aws ec2 wait instance-running --filters 'Name=tag:Name,Values=wireguard1'
aws ec2 wait instance-running --filters 'Name=tag:Name,Values=wireguard2'

export SERVER_1_PUBLIC_IP=$(aws ec2 describe-instances \
--filters 'Name=tag:Name,Values=wireguard1' \
--query Reservations[0].Instances[0].PublicIpAddress \
--output text)

export SERVER_2_PUBLIC_IP=$(aws ec2 describe-instances \
--filters 'Name=tag:Name,Values=wireguard2' \
--query Reservations[0].Instances[0].PublicIpAddress \
--output text)

aws route53 change-resource-record-sets --hosted-zone-id $ROUTE_53_HOSTED_ZONE_ID --change-batch '{ "Comment": "change", "Changes": [ { "Action": "UPSERT", "ResourceRecordSet": { "Name": "'"$SERVER_1_DOMAIN"'", "Type": "A", "TTL": 120, "ResourceRecords": [ { "Value": "'"$SERVER_1_PUBLIC_IP"'" } ] } } ] }'

aws route53 change-resource-record-sets --hosted-zone-id $ROUTE_53_HOSTED_ZONE_ID --change-batch '{ "Comment": "change", "Changes": [ { "Action": "UPSERT", "ResourceRecordSet": { "Name": "'"$SERVER_2_DOMAIN"'", "Type": "A", "TTL": 120, "ResourceRecords": [ { "Value": "'"$SERVER_2_PUBLIC_IP"'" } ] } } ] }'

scp -oStrictHostKeyChecking=no -i wireguard-servers.pem ./install-docker.sh ubuntu@$SERVER_1_PUBLIC_IP:/home/ubuntu/install-docker.sh
scp -oStrictHostKeyChecking=no -i wireguard-servers.pem ./install-docker.sh ubuntu@$SERVER_2_PUBLIC_IP:/home/ubuntu/install-docker.sh

ssh -i wireguard-servers.pem ubuntu@$SERVER_1_PUBLIC_IP 'chmod +x install-docker && ./install-docker.sh'
ssh -i wireguard-servers.pem ubuntu@$SERVER_2_PUBLIC_IP 'chmod +x install-docker && ./install-docker.sh'

ssh -i wireguard-servers.pem ubuntu@$SERVER_1_PUBLIC_IP 'docker run --tag wireguard --env PRIVATE_KEY='"$SERVER_1_PRIVATE_KEY"' --publish 51820:51820 --detach '"$WIREGUARD_DOCKER_IMAGE"''
ssh -i wireguard-servers.pem ubuntu@$SERVER_2_PUBLIC_IP 'docker run --tag wireguard --env PRIVATE_KEY='"$SERVER_2_PRIVATE_KEY"' --publish 51820:51820 --detach '"$WIREGUARD_DOCKER_IMAGE"''

# TODO: does peering need reference to private ip?
ssh -i wireguard-servers.pem ubuntu@$SERVER_1_PUBLIC_IP 'docker exec wireguard wg set wg0 peer '"$SERVER_2_PUBLIC_KEY"' allowed-ips 10.0.0.0/8 endpoint '"$SERVER_2_DOMAIN"':51820 persistent-keepalive 25'

ssh -i wireguard-servers.pem ubuntu@$SERVER_2_PUBLIC_IP 'docker exec wireguard wg set wg0 peer '"$SERVER_1_PUBLIC_KEY"' allowed-ips 10.0.0.0/8 endpoint '"$SERVER_1_DOMAIN"':51820 persistent-keepalive 25'

aws ec2 revoke-security-group-ingress \
--group-name wireguard-ssh \
--protocol tcp \
--port 22 \
--cidr $CURRENT_PUBLIC_IP/32

# generate pre-shared key
# wg genpsk > presharedkey

# generate client keys
# wg genkey | tee privatekey1 | wg pubkey > publickey1
# wg genkey | tee privatekey2 | wg pubkey > publickey2

# wg setconf wg0 myconfig.conf

