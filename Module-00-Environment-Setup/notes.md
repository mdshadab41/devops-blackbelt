# Module 00 — Environment Setup

## Completed
- M00-P01: Launched EC2 instance (Ubuntu 26.04 LTS, t3.micro, ap-south-1)
- M00-P02: Verified SSH security posture (password auth disabled, root login blocked)
- M00-P03: SSH lockout simulation — caused and recovered lockout using a backup session
- M00-P04: Installed and verified core toolchain — git, Docker, aws-cli, kubectl, helm, Terraform

## Key learnings
- Security Group "My IP" rule needs refreshing if your public IP changes (causes SSH timeouts)
- Ubuntu cloud images override sshd_config via a separate sshd_config.d/*.conf file
- Docker requires adding your user to the `docker` group to run without sudo
- Always prefer official tool install methods over distro-packaged versions for current, secure releases
