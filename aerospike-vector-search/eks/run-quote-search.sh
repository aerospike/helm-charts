#!/bin/bash -e
WORKSPACE="$(git rev-parse --show-toplevel)"
REGION=""

if [ -z "$REGION" ]; then
    echo "Set Region"
    exit 1
fi

VPC_ID="$(aws ec2 describe-vpcs \
--region "$REGION" \
--filters "Name=isDefault,Values=true" \
--query 'Vpcs[0].VpcId' \
--output text)"

AMI_ID="$(aws ec2 describe-images \
--region "$REGION" \
--owners 099720109477 \
--filters "Name=name,Values=*ubuntu/images/*ubuntu-mantic-23.10-amd64-server-*" \
"Name=root-device-type,Values=ebs" "Name=virtualization-type,Values=hvm" \
--query 'Images | sort_by(@, &CreationDate) | [-1].[ImageId]' \
--output text)"

SG_ID="$(aws ec2 create-security-group \
--region "$REGION" \
--group-name proximus-quote-search-sg \
--description "Proximus Quote Search Security Group" \
--vpc-id "$VPC_ID" \
--output text)"

aws ec2 authorize-security-group-ingress \
--region "$REGION" --group-id "$SG_ID" --protocol tcp --port 80 --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress \
--region "$REGION" --group-id "$SG_ID" --protocol tcp --port 443 --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress \
--region "$REGION" --group-id "$SG_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0

SUBNET_ID="$(aws ec2 describe-subnets \
--region "$REGION" \
--filters "Name=vpc-id,Values=$VPC_ID" \
--query 'Subnets[0].SubnetId' \
--output text)"

aws ec2 create-key-pair \
--region "$REGION" \
--key-name proximus-quote-search-key \
--query 'KeyMaterial' \
--output text > "$WORKSPACE/aerospike-proximus/eks/proximus-quote-search.pem"

chmod 400 "$WORKSPACE/aerospike-proximus/eks/proximus-quote-search.pem"

cat <<-EOF > "$WORKSPACE/aerospike-proximus/eks/user-data.sh"
#!/bin/bash -e
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
rm -f get-docker.sh
usermod -aG docker ubuntu
EOF

echo "Creating Instance"
aws ec2 run-instances \
--region "$REGION" \
--image-id "$AMI_ID" \
--count 1 \
--instance-type t3.medium \
--key-name proximus-quote-search-key \
--subnet-id "$SUBNET_ID" \
--security-group-ids "$SG_ID" \
--block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=30,DeleteOnTermination=true}' \
--tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=proximus-quote-search}]" \
--user-data "file://$WORKSPACE/aerospike-proximus/eks/user-data.sh" > /dev/null

INSTANCE_ID="$(aws ec2 describe-instances \
--region "$REGION" \
--filters "Name=tag:Name,Values=proximus-quote-search" \
--query 'Reservations[*].Instances[?!contains(State.Name, `terminated`)].InstanceId' \
--output text)"

rm "$WORKSPACE/aerospike-proximus/eks/user-data.sh"
echo "Waiting for Instance to be ready"
aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE_ID"
aws ec2 wait instance-status-ok --region "$REGION" --instance-ids "$INSTANCE_ID"

PUBLIC_IP="$(aws ec2 describe-instances \
--region "$REGION" \
--instance-ids "$INSTANCE_ID" \
--query 'Reservations[*].Instances[*].PublicIpAddress' \
--output text)"

cat <<-EOF > "$WORKSPACE/aerospike-proximus/eks/build-app.sh"
#!/bin/bash -e
git clone --branch VEC-95 https://github.com/aerospike/proximus-examples.git
cd ./proximus-examples/quote-semantic-search
docker build -f "Dockerfile-quote-search" -t "quote-search" .
cd -
rm -rf ./proximus-examples
EOF
chmod +x "$WORKSPACE/aerospike-proximus/eks/build-app.sh"

scp -o StrictHostKeyChecking=no -i "$WORKSPACE/aerospike-proximus/eks/proximus-quote-search.pem" \
"$WORKSPACE/aerospike-proximus/eks/build-app.sh" ubuntu@"$PUBLIC_IP":/home/ubuntu
rm "$WORKSPACE/aerospike-proximus/eks/build-app.sh"

ssh -o StrictHostKeyChecking=no \
-i "$WORKSPACE/aerospike-proximus/eks/proximus-quote-search.pem" ubuntu@"$PUBLIC_IP" bash /home/ubuntu/build-app.sh

cat <<-EOF > "$WORKSPACE/aerospike-proximus/eks/run-app.sh"
#!/bin/bash -e
mkdir -p ./data
curl -L -o "./data/quotes.csv.tgz" \
https://github.com/aerospike/proximus-examples/raw/main/quote-semantic-search/container-volumes/quote-search/data/quotes.csv.tgz
docker run -d \
--name "quote-search" \
-v "./data:/container-volumes/quote-search/data" \
-p "8080:8080" \
-e "PROXIMUS_HOST=$(kubectl -n aerospike get svc/as-proximus-eks-aerospike-proximus-lb \
-o=jsonpath='{.status.loadBalancer.ingress[0].hostname}')" \
-e "PROXIMUS_PORT=5000" \
-e "APP_NUM_QUOTES=5000" \
-e "GRPC_DNS_RESOLVER=native" \
-e "PROXIMUS_IS_LOADBALANCER=True" quote-search
EOF

chmod +x "$WORKSPACE/aerospike-proximus/eks/run-app.sh"
scp -o StrictHostKeyChecking=no \
-i "$WORKSPACE/aerospike-proximus/eks/proximus-quote-search.pem" \
"$WORKSPACE/aerospike-proximus/eks/run-app.sh" ubuntu@"$PUBLIC_IP":/home/ubuntu
rm "$WORKSPACE/aerospike-proximus/eks/run-app.sh"

ssh -o StrictHostKeyChecking=no  \
-i "$WORKSPACE/aerospike-proximus/eks/proximus-quote-search.pem" ubuntu@"$PUBLIC_IP" bash /home/ubuntu/run-app.sh
