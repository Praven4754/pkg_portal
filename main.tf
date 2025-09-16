terraform {
  required_providers {
    aws   = { source = "hashicorp/aws", version = "~> 5.0" }
    tls   = { source = "hashicorp/tls", version = "~> 4.0" }
    local = { source = "hashicorp/local", version = "~> 2.0" }
    null  = { source = "hashicorp/null", version = "~> 3.2" }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = "ec2-tf"
}

# ----------------------
# Check existing Key Pair
# ----------------------
data "aws_key_pair" "existing_key" {
  key_name = var.key_name
  # ignore errors if key does not exist
  lifecycle {
    ignore_errors = true
  }
}

# Only create new key if not exists
resource "tls_private_key" "ec2_key" {
  count     = data.aws_key_pair.existing_key.id == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "pem_file" {
  count               = data.aws_key_pair.existing_key.id == "" ? 1 : 0
  content             = tls_private_key.ec2_key[0].private_key_pem
  filename            = var.private_key_path
  file_permission     = "0600"
  directory_permission = "0700"
}

resource "aws_key_pair" "generated_key" {
  count      = data.aws_key_pair.existing_key.id == "" ? 1 : 0
  key_name   = var.key_name
  public_key = tls_private_key.ec2_key[0].public_key_openssh
}

locals {
  key_name_to_use = data.aws_key_pair.existing_key.id != "" ? data.aws_key_pair.existing_key.key_name : aws_key_pair.generated_key[0].key_name
}

# ----------------------
# Check existing Security Group
# ----------------------
data "aws_security_group" "existing_pkg_portal_sg" {
  filter {
    name   = "group-name"
    values = ["pkg-portal-sg"]
  }

  # ignore errors if SG does not exist
  lifecycle {
    ignore_errors = true
  }
}

# Create SG only if it doesn't exist
resource "aws_security_group" "pkg_portal_sg" {
  count       = length(data.aws_security_group.existing_pkg_portal_sg.ids) == 0 ? 1 : 0
  name        = "pkg-portal-sg"
  description = "Allow SSH, HTTP, HTTPS, and app ports"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Custom App Ports"
    from_port   = 3000
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

locals {
  sg_id = length(data.aws_security_group.existing_pkg_portal_sg.ids) > 0 ? data.aws_security_group.existing_pkg_portal_sg.ids[0] : aws_security_group.pkg_portal_sg[0].id
}

# ----------------------
# Latest Ubuntu AMI
# ----------------------
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

# ----------------------
# EC2 Instance
# ----------------------
resource "aws_instance" "pkg_portal" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.medium"
  key_name                    = local.key_name_to_use
  vpc_security_group_ids      = [local.sg_id]
  associate_public_ip_address = true

  tags = merge(var.resource_tags, { Name = "pkg_portal-instance" })

  user_data = <<-EOF
    #!/bin/bash
    set -e
    exec > >(tee /var/log/user-data.log) 2>&1

    apt-get update -y
    apt-get install -y ca-certificates curl gnupg lsb-release unzip

    # Install Docker & Compose plugin
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    systemctl enable docker
    systemctl start docker
    usermod -aG docker ubuntu

    mkdir -p /home/ubuntu/pkg_portal
    chown ubuntu:ubuntu /home/ubuntu/pkg_portal
    chmod 755 /home/ubuntu/pkg_portal

    # Create Grafana directories with proper UID/GID
    mkdir -p /home/ubuntu/pkg_portal/data/grafana
    mkdir -p /home/ubuntu/pkg_portal/grafana/config
    chown -R 472:472 /home/ubuntu/pkg_portal/data/grafana
    chown -R 472:472 /home/ubuntu/pkg_portal/grafana/config
    chmod -R 755 /home/ubuntu/pkg_portal/data/grafana
    chmod -R 755 /home/ubuntu/pkg_portal/grafana/config

    touch /tmp/docker-ready
  EOF
}

# ----------------------
# Wait for Docker
# ----------------------
resource "null_resource" "wait_for_docker" {
  depends_on = [aws_instance.pkg_portal]

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      host        = aws_instance.pkg_portal.public_ip
      user        = "ubuntu"
      private_key = tls_private_key.ec2_key.count > 0 ? tls_private_key.ec2_key[0].private_key_pem : file(var.private_key_path)
      timeout     = "10m"
    }

    inline = [
      "timeout 300 bash -c 'while [ ! -f /tmp/docker-ready ]; do sleep 5; done'"
    ]
  }
}

# ----------------------
# Upload Files
# ----------------------
resource "null_resource" "upload_files" {
  depends_on = [null_resource.wait_for_docker]

  provisioner "file" {
    source      = "${var.docker_compose_dir}/docker-compose.yml"
    destination = "/home/ubuntu/pkg_portal/docker-compose.yml"

    connection {
      type        = "ssh"
      host        = aws_instance.pkg_portal.public_ip
      user        = "ubuntu"
      private_key = tls_private_key.ec2_key.count > 0 ? tls_private_key.ec2_key[0].private_key_pem : file(var.private_key_path)
    }
  }

  provisioner "file" {
    source      = var.env_file_path
    destination = "/home/ubuntu/pkg_portal/.env"

    connection {
      type        = "ssh"
      host        = aws_instance.pkg_portal.public_ip
      user        = "ubuntu"
      private_key = tls_private_key.ec2_key.count > 0 ? tls_private_key.ec2_key[0].private_key_pem : file(var.private_key_path)
    }
  }
}

# ----------------------
# Deploy Application
# ----------------------
resource "null_resource" "deploy_application" {
  depends_on = [null_resource.upload_files]

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      host        = aws_instance.pkg_portal.public_ip
      user        = "ubuntu"
      private_key = tls_private_key.ec2_key.count > 0 ? tls_private_key.ec2_key[0].private_key_pem : file(var.private_key_path)
      timeout     = "15m"
    }

    inline = [
      "cd /home/ubuntu/pkg_portal",
      "echo '🔑 Logging into GHCR...' ",
      "bash -c '. .env && echo \"$GHCR_TOKEN\" | sudo -E docker login ghcr.io -u \"$GHCR_USERNAME\" --password-stdin'",
      "echo '⬇️ Pulling Docker images (once)...'",
      "sudo -E docker compose pull --quiet",
      "echo '✅ Images pulled'",
      "echo '🚀 Starting containers...'",
      "sudo -E docker compose up -d",
      "echo '✅ Containers started'",
      "echo '🔍 Checking containers health...'",
      "for i in {1..30}; do STATUS=$(sudo -E docker compose ps --format \"{{.Name}} {{.State}}\" | grep -v \"running\"); [ -z \"$STATUS\" ] && break || sleep 10; done",
      "echo '🎉 Deployment finished!'",
      "sudo -E docker compose ps"
    ]
  }
}

# ----------------------
# Cleanup
# ----------------------
resource "null_resource" "cleanup" {
  depends_on = [null_resource.deploy_application]

  provisioner "local-exec" {
    command = "echo Cleanup complete"
  }
}

# ----------------------
# Outputs
# ----------------------
output "instance_public_ip" {
  value = aws_instance.pkg_portal.public_ip
}

output "ssh_command" {
  value = "ssh -i ${var.private_key_path} ubuntu@${aws_instance.pkg_portal.public_ip}"
}

output "application_urls" {
  value = {
    port_3000 = "http://${aws_instance.pkg_portal.public_ip}:3000"
    port_8000 = "http://${aws_instance.pkg_portal.public_ip}:8000"
    port_80   = "http://${aws_instance.pkg_portal.public_ip}"
  }
}
