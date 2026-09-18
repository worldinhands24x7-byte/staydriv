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

# Create StayDriv Backend Bootstrap / Health Service
cat << 'EOF' > /opt/staydriv/server.js
const http = require('http');

const PORT = process.env.PORT || ${app_port};

const server = http.createServer((req, res) => {
  if (req.url === '/' || req.url === '/api/health' || req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      status: 'UP',
      service: 'staydriv-backend',
      environment: '${environment}',
      timestamp: new Date().toISOString()
    }));
  } else {
    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Not Found' }));
  }
});

server.listen(PORT, '0.0.0.0', () => {
  console.log('StayDriv Production Service running on port ' + PORT);
});
EOF

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
