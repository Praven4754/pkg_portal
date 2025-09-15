variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-2"
}

variable "key_name" {
  description = "Name of the EC2 key pair"
  type        = string
  default     = "pkg_portal_key"
}

variable "private_key_path" {
  description = "Windows path to PEM private key"
  type        = string
  default     = "C:/Users/prakumar/.ssh/pkg_portal-key.pem"
}

variable "docker_compose_dir" {
  description = "Local folder path containing docker-compose.yml"
  type        = string
}

variable "env_file_path" {
  description = "Local path to the .env file for the application"
  type        = string
}

variable "ghcr_username" {
  description = "GitHub Container Registry username"
  type        = string
}

variable "ghcr_token" {
  description = "GitHub Container Registry token"
  type        = string
  sensitive   = true
}

variable "resource_tags" {
  description = "Tags for AWS resources"
  type        = map(string)
}
