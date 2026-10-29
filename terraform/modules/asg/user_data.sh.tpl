#!/usr/bin/env bash
set -xe

# Update and install dependencies
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl gnupg2 ca-certificates lsb-release jq unzip git

# Install AWS CLI v2 if not present
if ! command -v aws &> /dev/null; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
    unzip -q /tmp/awscliv2.zip -d /tmp
    /tmp/aws/install
    rm -rf /tmp/aws /tmp/awscliv2.zip
fi

# Install Node.js 20 LTS
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# Install CloudWatch Agent
wget -q https://s3.${aws_region}.amazonaws.com/amazoncloudwatch-agent-${aws_region}/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb -O /tmp/amazon-cloudwatch-agent.deb
dpkg -i -E /tmp/amazon-cloudwatch-agent.deb || true
rm -f /tmp/amazon-cloudwatch-agent.deb

# Create StayDriv Application Directory
mkdir -p /opt/staydriv
mkdir -p /var/log/staydriv
chown -R ubuntu:ubuntu /opt/staydriv /var/log/staydriv

# Install Docker for MongoDB
which docker || (apt-get update -y && apt-get install -y docker.io)
systemctl enable docker --now
docker ps -a | grep -q staydriv-mongo || docker run -d --name staydriv-mongo -p 27017:27017 --restart always mongo:7.0

# Download and install StayDriv production backend from S3
aws s3 cp s3://${s3_bucket_name}/staydriv_core_backend.tar.gz /tmp/staydriv_core_backend.tar.gz --region ${aws_region}
tar -xzf /tmp/staydriv_core_backend.tar.gz -C /opt/staydriv
cd /opt/staydriv && npm install --omit=dev
chown -R ubuntu:ubuntu /opt/staydriv

# Fetch DB and API Secrets from AWS Secrets Manager if configured
if [ -n "${db_secret_arn}" ]; then
  echo "Fetching secrets from AWS Secrets Manager: ${db_secret_arn}"
  SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id "${db_secret_arn}" --region "${aws_region}" --query SecretString --output text || echo "{}")
  echo "$SECRET_JSON" > /opt/staydriv/secrets.json
  chmod 600 /opt/staydriv/secrets.json
fi

# Write systemd service for StayDriv
cat << EOF > /etc/systemd/system/staydriv.service
[Unit]
Description=StayDriv Backend Service
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/staydriv
Environment=PORT=${app_port}
Environment=NODE_ENV=${environment}
Environment=DB_HOST=${db_endpoint}
Environment=S3_BUCKET=${s3_bucket_name}
Environment=AWS_DEFAULT_REGION=${aws_region}
ExecStart=/usr/bin/node /opt/staydriv/server.js
Restart=always
RestartSec=5
StandardOutput=append:/var/log/staydriv/app.log
StandardError=append:/var/log/staydriv/error.log

[Install]
WantedBy=multi-user.target
EOF

# Configure CloudWatch Agent
cat << EOF > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/staydriv/app.log",
            "log_group_name": "/aws/staydriv/${environment}/app",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 14
          },
          {
            "file_path": "/var/log/staydriv/error.log",
            "log_group_name": "/aws/staydriv/${environment}/error",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 30
          }
        ]
      }
    }
  },
  "metrics": {
    "append_dimensions": {
      "AutoScalingGroupName": "$${aws:AutoScalingGroupName}",
      "InstanceId": "$${aws:InstanceId}"
    },
    "metrics_collected": {
      "mem": {
        "measurement": ["mem_used_percent"]
      },
      "disk": {
        "measurement": ["used_percent"],
        "resources": ["/"]
      }
    }
  }
}
EOF

# Start CloudWatch Agent & StayDriv Service
systemctl daemon-reload
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json || true
systemctl enable staydriv
systemctl start staydriv

# Create StayDriv ASG Instance CLI helper command
cat << 'EOF' > /usr/local/bin/${project_name}-${environment}-asg-instance
#!/bin/bash
echo "============================================================"
echo "          STAYDRIV PRODUCTION ASG INSTANCE INFO"
echo "============================================================"
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null)
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || hostname)
LOCAL_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null || hostname -I | awk '{print $1}')
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone 2>/dev/null || echo "${aws_region}")

echo "Instance Name : ${project_name}-${environment}-asg-instance"
echo "Instance ID   : $INSTANCE_ID"
echo "Private IP    : $LOCAL_IP"
echo "AZ / Region   : $AZ"
echo "------------------------------------------------------------"
echo "Backend Status:"
if systemctl is-active staydriv &>/dev/null; then
  echo "  Service staydriv: ACTIVE (RUNNING)"
else
  echo "  Service staydriv: INACTIVE"
fi
echo ""
echo "Health Check (http://127.0.0.1:${app_port}/health):"
curl -s http://127.0.0.1:${app_port}/health
echo ""
echo "------------------------------------------------------------"
echo "Useful Commands:"
echo "  View live logs  : sudo journalctl -u staydriv -f"
echo "  Restart service: sudo systemctl restart staydriv"
echo "============================================================"
EOF
chmod +x /usr/local/bin/${project_name}-${environment}-asg-instance
ln -sf /usr/local/bin/${project_name}-${environment}-asg-instance /usr/bin/${project_name}-${environment}-asg-instance

