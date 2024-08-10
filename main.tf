terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket = "jenkins-3tierapp-yb"
    key    = "backend/tf-backend-jenkins.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "tags" {
  default = ["postgresql", "nodejs", "react"]
}

variable "user" {
  default = "yanis"
}

resource "aws_iam_role" "jenkins_project_role" {
  name = "jenkins-project-role-${var.user}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      },
    ]
  })
}

resource "aws_iam_policy" "jenkins_project_policy" {
  name        = "jenkins-project-policy-${var.user}"
  description = "Policy for Jenkins project role"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "ec2:DescribeInstances",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:ListImages",
          "ecr:DescribeRepositories",
          "ecr:GetRepositoryPolicy",
          "ecr:SetRepositoryPolicy",
          "ecr:DeleteRepository",
          "ecr:DeleteRepositoryPolicy",
          "ecr:GetAuthorizationToken",
          "ecr:ListRepositories"    
        ],
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "jenkins_project_role_policy_attachment" {
  role       = aws_iam_role.jenkins_project_role.name
  policy_arn  = aws_iam_policy.jenkins_project_policy.arn
}

resource "aws_iam_instance_profile" "jenkins_project_instance_profile" {
  name = "jenkins-project-profile-${var.user}"
  role = aws_iam_role.jenkins_project_role.name
}

resource "aws_security_group" "tf-sec-gr" {
  name = "jenkins-project-sec-gr-${var.user}"
  tags = {
    Name = "jenkins-project-sec-gr"
  }

  ingress {
    from_port   = 22
    protocol    = "tcp"
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 5000
    protocol    = "tcp"
    to_port     = 5000
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 3000
    protocol    = "tcp"
    to_port     = 3000
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 5432
    protocol    = "tcp"
    to_port     = 5432
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    protocol    = -1
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "managed_nodes" {
  ami                    = "ami-0583d8c7a9c35822c"
  count                  = 3
  instance_type          = "t2.micro"
  key_name               = "Projects_key-1"
  vpc_security_group_ids = [aws_security_group.tf-sec-gr.id]
  iam_instance_profile   = aws_iam_instance_profile.jenkins_project_instance_profile.name
  tags = {
    Name        = "ansible_${element(var.tags, count.index)}"
    stack       = "ansible_project"
    environment = "development"
  }
  user_data = <<-EOF
                #! /bin/bash
                dnf update -y
                EOF
}

output "react_ip" {
  value = "http://${aws_instance.managed_nodes[2].public_ip}:3000"
}

output "node_public_ip" {
  value = aws_instance.managed_nodes[1].public_ip
}

output "postgre_private_ip" {
  value = aws_instance.managed_nodes[0].private_ip
}
