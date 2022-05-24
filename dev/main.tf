terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.14"
    }
  }
}

provider "aws" {
  profile    = local.profile
  region     = local.region
}

locals {
  profile             = "dev"
  environment         = "dev"
  region              = "eu-west-2"
  name                = "SOHOSME service ${local.environment}"
  bt_sohosme_sg_name  = "bt-sohosme-tf"
#Please specify the VPC ID for VPC attached from the Service catalog
  vpc_id              = "vpc-01ea94e87dd7374ee"
  subnet_name         = "Dcp-ConsumerVPC-Public-Subnet-AZc"
  subnet_id           = "subnet-00eb6cb2819a7a8db"
  cidr_marco          = "81.155.180.19/32"
  cidr_sucharita      = "148.252.128.227/32"
  cidr_sucharita_2    = "94.3.202.238/32"
  cidr_epam           = "85.223.209.18/32"
  cidr_public         = "0.0.0.0/0"

  key_name            = "bt-sohosme"
  ssh_key             = "bt-sohosme.pem"

  backup_frequency    = "Weekly"

  tags = {
    ScanGroup         = "Mon3amGroup"
    Name              = "BT - SoHoSME - STRAPI - ${local.environment}"
  }

  user_data = <<-EOT
  #!/bin/bash
  echo "Setup SOHOSME server"
  EOT

}

# data "aws_vpc" "main" {
#   id = local.vpc_id
# }

# data "aws_subnets" "all" {
#   filter {
#     name   = "tag:Name"
#     values = [local.subnet_name]
#   }
# }

# data "aws_subnet" "public" {
#   for_each = toset(data.aws_subnets.all.ids)
#   id       = each.value
# }


# output "subnet_cidr_blocks" {
#   value = [for s in data.aws_subnet.public : s.cidr_block]
# }

# output "subnet_id" {
#   value = [for s in data.aws_subnet.public : s.id]
# }

data "aws_ami" "ubuntu_linux" {
  most_recent = true
  owners      = ["099720109477"] #this can be obtained by execute "aws --region eu-west-2 ssm get-parameters --names /aws/service/canonical/meta/publisher-id"
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

    filter {
    name   = "architecture"
    values = ["x86_64"]
  }

    filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

output "ami_id" {
  value = data.aws_ami.ubuntu_linux.id
}

module "sohosme_servers_sg" {
  source = "terraform-aws-modules/security-group/aws"

  name        = local.bt_sohosme_sg_name
  description = "Security group for SOHOSME-servers"
  vpc_id      = local.vpc_id

  ingress_with_cidr_blocks = [
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "Https port"
      cidr_blocks = local.cidr_public
    },
    {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      description = "Http port"
      cidr_blocks = local.cidr_public
    },
    {
      from_port   = 1337
      to_port     = 1337
      protocol    = "tcp"
      description = "STRAPI port"
      cidr_blocks = local.cidr_public
    },
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      description = "SSH port EPAM"
      cidr_blocks = local.cidr_epam
    },
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      description = "SSH port Marco"
      cidr_blocks = local.cidr_marco
    },
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      description = "SSH port Sucharita"
      cidr_blocks = local.cidr_sucharita
    },
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      description = "SSH port Sucharita 2"
      cidr_blocks = local.cidr_sucharita_2
    }
  ]
}

resource "aws_placement_group" "strapi" {
  name     = local.name
  strategy = "spread"
}

resource "aws_kms_key" "this" {
}

module "ec2_strapi" {
  source = "terraform-aws-modules/ec2-instance/aws"

  name                 = "${local.name}-STRAPI-${local.environment}"
  create_spot_instance = false

  ami                         = data.aws_ami.ubuntu_linux.id
  instance_type               = "t2.medium"
  # key_name                    = local.key_name
  # ssh_key                     = local.ssh_key
  # provisioner_path            = local.provisioner_path
  availability_zone           = "eu-west-2c"
  subnet_id                   = local.subnet_id
  vpc_security_group_ids      = [module.sohosme_servers_sg.security_group_id]
  placement_group             = aws_placement_group.strapi.id
  associate_public_ip_address = true

  user_data_base64 = base64encode(local.user_data)

  capacity_reservation_specification = {
    capacity_reservation_preference = "open"
  }

  enable_volume_tags = false
  root_block_device = [
    { 
      encrypted   = true
      volume_type = "gp3"
      throughput  = 200
      volume_size = 16
      tags = {
        Name = "strapi-root-block"
        Backup-By-LifecycleManager = "${local.backup_frequency}"
      }
    },
  ]

  tags = local.tags
}
