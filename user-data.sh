#!/bin/bash
apt-get update -y
apt-get install -y unzip curl
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
aws s3 cp s3://devops-blackbelt-806528484602/artifacts/deploy-artifact.sh /home/ubuntu/deploy-artifact.sh
chmod +x /home/ubuntu/deploy-artifact.sh
/home/ubuntu/deploy-artifact.sh
chown ubuntu:ubuntu /home/ubuntu/deploy-artifact.sh /home/ubuntu/deployment-proof.txt
