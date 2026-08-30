#!/bin/bash

# Set up environment variables
app_name="metrix_druid_master"
env_name="dev"
region="us-east-1"
package_name="druid_master_1_current.zip"

base_dir="/opt/talech"
config_dir="${base_dir}/config"
scripts_dir="${base_dir}/helperscripts"
download_dir="${base_dir}/download"

###  Remove any proxy setting from dnf (cleanup step)
sed -i '/^proxy=/d' /etc/dnf/dnf.conf

###  System update & install dependencies
dnf update -y
dnf install -y python3 python3-pip docker zlib unzip nvme-cli

###  Fix permissions for libz (important for some builds/tools)
chmod 755 /usr/lib64/libz.so.1 || true
chmod 755 /usr/lib64/libz.so.1.* || true

###  Start & Enable Docker service
systemctl enable --now docker
chkconfig docker on || true   # Keep this for compatibility

###  Install Python packages
##### pip3 install boto3 --> This command was failing, hence commented.

dnf install -y python3-boto3

###  Install Docker Compose (latest release)
COMPOSE_VERSION=1.29.2
curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

chmod +x /usr/local/bin/docker-compose
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
mount /tmp -o remount,exec

# Validate both Docker and Docker Compose Versions
docker --version
docker-compose --version

###  Clean up old directories
rm -rf /opt/talech/download/* /opt/talech/config/* /root/.aws /home/ec2-user/.aws

# Create the below directory paths.
mkdir -p $base_dir $config_dir $scripts_dir $download_dir

###  CloudWatch Agent (fetch config from SSM)
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
-a fetch-config -m ec2 -c ssm:dev-druid-cw-agent-config -s

###  Attach and mount EBS volume  by Volume ID
VOLUME_ID="vol080095ea40cea67bb"   # Verify the Volume ID which is attached to your instance
MOUNT_POINT="/opt/talech/data"

# Verify volume is attached (no mount/format)
DEVICE=$(readlink -f /dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_${VOLUME_ID} 2>/dev/null || true)

if [ -z "$DEVICE" ]; then
    DEVICE=$(nvme list 2>/dev/null | awk "/${VOLUME_ID}/{print \$1}")
fi

if [ -z "$DEVICE" ]; then
    echo "ERROR: Volume $VOLUME_ID not found. Please check the Volume ID."
    exit 1
fi

echo "Volume $VOLUME_ID is attached as device $DEVICE"

# Create mount point directory (no mount, no format)
mkdir -p "$MOUNT_POINT"

# Validate that the volume is actually mounted
if ! mountpoint -q "$MOUNT_POINT"; then
    if ! mount "$DEVICE" "$MOUNT_POINT"; then
        echo "ERROR: Failed to mount volume $VOLUME_ID at $MOUNT_POINT"
        exit 1
    fi
fi

###  Script: writeawsenv
cat <<EOF > ${scripts_dir}/writeawsenv
with open('/opt/talech/config/envvars', 'r') as reader:
    for line in reader:
        line = line.strip()
        if line:
            print('SetEnv' + line.replace('=', ' "') + '"')
EOF

chmod +x ${scripts_dir}/writeawsenv

###  Script: getpackage (download from S3)
cat <<EOF > ${scripts_dir}/getpackage
#!/usr/bin/env python3
import boto3, argparse, sys
from botocore.exceptions import ClientError

parser = argparse.ArgumentParser(description='Downloads Package from S3 Bucket')
parser.add_argument('-a', '--app_name',     type=str, required=True, help='Name of the App          to download the package for')
parser.add_argument('-e', '--env_name',     type=str, required=True, help='Name of the Environment to download the package for')
parser.add_argument('-p', '--package_name', type=str, required=True, help='Name of the Environment to download the package for')
parser.add_argument('-r', '--region',       type=str, required=True, help='Name of the Environment to download the package for')
args = parser.parse_args()

download_dir = "${download_dir}"
package_object = f"{args.app_name}/druid-master-1-{args.env_name}/{args.package_name}"
bucket_name = f"491085383807-{args.region}-{args.env_name}-talech-deployments"

print(f"SUCCESS: Download s3://{bucket_name}/{package_object} to {download_dir}/{args.package_name}") 

s3 = boto3.resource('s3', region_name=args.region)

try:
    s3.Bucket(bucket_name).download_file(package_object, f"{download_dir}/{package_name}")
    print("Download completed successfully.")
except botocore.exceptions.ClientError as e:
    print(f"ERROR: Could not download {args.package_name} from {bucket_name}")
    print(e)
EOF

chmod +x "${scripts_dir}/getpackage"

###  Placeholders for read_secret (Only if required)

cat <<EOF > ${scripts_dir}/readsecret
#!/bin/bash
# Placeholder script. Replace with actual logic if needed.
echo "readsecret logic is currently handled by secrets_download.py inside deploy.sh"
EOF

chmod +x ${scripts_dir}/readsecret

###  Prepare data directories
mkdir -p /opt/talech/data/logs /opt/talech/data/druid 
chmod 755 /opt/talech/data/logs /opt/talech/data/druid
chmod 755 "$download_dir"

###  Download and extract deployment zip
python3 ${scripts_dir}/getpackage -a $app_name -e $env_name -p ${package_name} -r $region

# Verify S3 download succeeded
if [ ! -f "${download_dir}/${package_name}" ]; then
   echo "ERROR: Package not found after s3 download attempt - aborting setup."
   exit 1
fi

cd $download_dir
rm -rf ${base_dir}/build
unzip -o ${package_name}
mv druid_master_1_current/build "${base_dir}"
rm -rf "${package_name}" druid_master_1_current

cd "${base_dir}/build"
chmod +x ${base_dir}/build/*.sh
chmod +x ${base_dir}/build/*.py

###  Deploy Druid Master
# export DOCKER_IMAGE_LAYERS=5
# bash deploy.sh $app_name $env_name
