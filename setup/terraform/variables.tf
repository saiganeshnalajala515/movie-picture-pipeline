variable "aws_region" {
  type        = string
  description = "AWS region used by EKS and ECR"
  default     = "us-east-1"
}

variable "k8s_version" {
  type    = string
  default = "1.33"
}

variable "enable_private" {
  type        = bool
  description = "Place worker nodes in the private subnet; creates a NAT gateway for required outbound access"
  default     = false
}

variable "cluster_public_access_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to reach the public Kubernetes API endpoint"
  default     = ["0.0.0.0/0"]
}

variable "public_az" {
  type        = string
  description = "Change this to a letter a-f only if you encounter an error during setup"
  default     = "a"
}

variable "private_az" {
  type        = string
  description = "Change this to a letter a-f only if you encounter an error during setup"
  default     = "b"
}
