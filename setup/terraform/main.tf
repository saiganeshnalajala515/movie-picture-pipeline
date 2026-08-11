####################
# VPC Configuration
####################
# Create a VPC
resource "aws_vpc" "vpc" {
  tags = {
    "Name" = "udacity"
  }
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

# Create an internet gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
}

# Create a public subnet
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1${var.public_az}"
  map_public_ip_on_launch = true
  tags = {
    Name                     = "udacity-public"
    "kubernetes.io/role/elb" = "1"
  }
}

# Create public route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public"
  }
}

# Associate the route table
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public.id
}

# Create a private subnet
resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = "us-east-1${var.private_az}"
  cidr_block        = "10.0.2.0/24"
  tags = {
    Name                              = "udacity-private"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# Create private route table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "private"
  }
}

# Associate private route table
resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private.id
}

# Private workers need outbound access to EKS, ECR, S3, STS and package/image
# registries. A NAT route is complete and avoids the partial endpoint setup that
# previously left private nodes unable to bootstrap or pull CoreDNS.
resource "aws_eip" "nat" {
  count  = var.enable_private ? 1 : 0
  domain = "vpc"

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_nat_gateway" "nat" {
  count         = var.enable_private ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public_subnet.id

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route" "private_egress" {
  count                  = var.enable_private ? 1 : 0
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat[0].id
}

###################
# ECR Repositories
###################
resource "aws_ecr_repository" "frontend" {
  name                 = "frontend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "backend" {
  name                 = "backend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

################
# EKS Resources
################
# Create an EKS cluster
resource "aws_eks_cluster" "main" {
  name     = "cluster"
  version  = var.k8s_version
  role_arn = aws_iam_role.eks_cluster.arn
  vpc_config {
    subnet_ids              = [aws_subnet.private_subnet.id, aws_subnet.public_subnet.id]
    endpoint_public_access  = true
    endpoint_private_access = true
    public_access_cidrs     = var.cluster_public_access_cidrs
  }
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
  depends_on = [aws_iam_role_policy_attachment.eks_cluster]
}


# Create an IAM role for the EKS cluster
resource "aws_iam_role" "eks_cluster" {
  name = "eks_cluster_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })
}

# Attach policies to the EKS cluster IAM role
resource "aws_iam_role_policy_attachment" "eks_cluster" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

##################
# EKS Node Group
##################
# Udacity's organization SCP denies ec2:DescribeInstances to worker roles.
# AL2023 nodeadm can avoid that API call by using the immutable EC2 instance ID
# as the Kubernetes node name.
resource "aws_launch_template" "node_group" {
  name_prefix = "udacity-node-instance-id-"

  user_data = base64encode(<<-EOT
    MIME-Version: 1.0
    Content-Type: multipart/mixed; boundary="BOUNDARY"

    --BOUNDARY
    Content-Type: application/node.eks.aws

    ---
    apiVersion: node.eks.aws/v1alpha1
    kind: NodeConfig
    spec:
      featureGates:
        InstanceIdNodeName: true
    --BOUNDARY--
  EOT
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "udacity-eks-worker"
    }
  }
}

resource "aws_eks_node_group" "main" {
  node_group_name = "udacity-fixed"
  cluster_name    = aws_eks_cluster.main.name
  version         = aws_eks_cluster.main.version
  node_role_arn   = aws_iam_role.node_group.arn
  subnet_ids      = [var.enable_private == true ? aws_subnet.private_subnet.id : aws_subnet.public_subnet.id]
  ami_type        = "AL2023_x86_64_STANDARD"
  instance_types  = ["t3.small"]
  capacity_type   = "ON_DEMAND"

  launch_template {
    id      = aws_launch_template.node_group.id
    version = aws_launch_template.node_group.latest_version
  }

  scaling_config {
    desired_size = 1
    max_size     = 1
    min_size     = 1
  }


  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    aws_iam_role_policy_attachment.node_group_policy,
    aws_iam_role_policy_attachment.cni_policy,
    aws_iam_role_policy_attachment.ecr_policy,
    aws_eks_access_entry.node_group,
  ]

}

// IAM Configuration
resource "aws_iam_role" "node_group" {
  name               = "udacity-node-group-instance-id"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "node_group_policy" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "cni_policy" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "ecr_policy" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_eks_access_entry" "node_group" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.node_group.arn
  type          = "EC2"
}

######################
# CodeBuild Resources
######################
# Create a CodeBuild project
resource "aws_codebuild_project" "codebuild" {
  name          = "udacity"
  description   = "Udacity CodeBuild project"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 60
  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:5.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true
  }

  source {
    type            = "GITHUB"
    location        = "https://github.com/your-org/your-repo"
    git_clone_depth = 1
    buildspec       = "buildspec.yml"
  }

  cache {
    type = "NO_CACHE"
  }
}

# Create the Codebuild Role
resource "aws_iam_role" "codebuild" {
  name = "codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Attach the IAM policy to the codebuild role
resource "aws_iam_role_policy_attachment" "codebuild" {
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeBuildAdminAccess"
  role       = aws_iam_role.codebuild.name
}

# The Udacity lab does not permit creating an IAM OIDC provider. GitHub
# credentials are created outside Terraform and stored only as encrypted
# repository secrets, so secret values never enter Terraform state.
resource "aws_iam_user" "github_actions" {
  name = "github-action-user"
}

resource "aws_iam_user_policy" "github_actions" {
  name   = "movie-pipeline-deploy"
  user   = aws_iam_user.github_actions.name
  policy = data.aws_iam_policy_document.github_policy.json
}

data "aws_iam_policy_document" "github_policy" {
  statement {
    sid       = "EcrLogin"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid    = "PushApplicationImages"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [aws_ecr_repository.frontend.arn, aws_ecr_repository.backend.arn]
  }
  statement {
    sid       = "DescribeCluster"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = [aws_eks_cluster.main.arn]
  }
}

resource "aws_eks_access_entry" "github_actions" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_user.github_actions.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "github_actions" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_user.github_actions.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy"

  access_scope {
    type       = "namespace"
    namespaces = ["default"]
  }

  depends_on = [aws_eks_access_entry.github_actions]
}
