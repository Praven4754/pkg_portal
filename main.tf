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
# EC2 Key Pair
# ----------------------
resource "tls_private_key" "ec2_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "pem_file" {
  content  = tls_private_key.ec2_key.private_key_pem
  filename = var.private_key_path
}

# Fix PEM permissions on Windows
resource "null_resource" "fix_pem_permissions" {
  depends_on = [local_file.pem_file]

  provisioner "local-exec" {
    command     = <<EOT
      icacls "${replace(var.private_key_path, "/", "\\")}" /inheritance:r
      icacls "${replace(var.private_key_path, "/", "\\")}" /grant:r "$($env:USERNAME):(R)"
    EOT
    interpreter = ["PowerShell", "-Command"]
  }
}

resource "aws_key_pair" "generated_key" {
  key_name   = var.key_name
  public_key = tls_private_key.ec2_key.public_key_openssh
}

# ----------------------
# Security Group
# ----------------------
resource "aws_security_group" "pkg_portal_sg" {
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
  key_name                    = aws_key_pair.generated_key.key_name
  vpc_security_group_ids      = [aws_security_group.pkg_portal_sg.id]
  associate_public_ip_address = true

  tags = merge(var.resource_tags, { Name = "pkg_portal-instance" })

  user_data = <<-EOF
    #!/bin/bash
    set -e
    exec > >(tee /var/log/user-data.log) 2>&1

    apt-get update -y
    apt-get install -y ca-certificates curl gnupg lsb-release

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
      private_key = tls_private_key.ec2_key.private_key_pem
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
      private_key = tls_private_key.ec2_key.private_key_pem
    }
  }

  provisioner "file" {
    source      = var.env_file_path
    destination = "/home/ubuntu/pkg_portal/.env"

    connection {
      type        = "ssh"
      host        = aws_instance.pkg_portal.public_ip
      user        = "ubuntu"
      private_key = tls_private_key.ec2_key.private_key_pem
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
      private_key = tls_private_key.ec2_key.private_key_pem
      timeout     = "15m"
    }

    inline = [
      "cd /home/ubuntu/pkg_portal",
      "echo '🔑 Logging into GHCR...'",
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
