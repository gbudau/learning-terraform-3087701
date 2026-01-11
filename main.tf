data "aws_ami" "app_ami" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

module "blog_vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "dev"
  cidr = "10.0.0.0/16"

  azs             = ["us-west-2a", "us-west-2b", "us-west-2c"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  tags = {
    Terraform = "true"
    Environment = "dev"
  }
}

module "autoscaling" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "9.1.0"

  name     = "blog"
  min_size = 1
  max_size = 2

  image_id            = data.aws_ami.app_ami.id
  instance_type       = var.instance_type

  vpc_zone_identifier = module.blog_vpc.public_subnets
  security_groups     = [module.blog_sg.security_group_id]

  # Installs Nginx and creates a custom page
  user_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y nginx
    echo '<h1>Hello from Terraform Nginx!</h1>' > /var/www/html/index.html
    systemctl enable nginx
    systemctl start nginx
  EOF
  )

  traffic_source_attachments = {
    ex-alb = {
      traffic_source_identifier = module.blog_alb.target_groups["ex-instance"].arn
      traffic_source_type = "elbv2"
    }
  }
}

module "blog_alb" {
  source = "terraform-aws-modules/alb/aws"

  name    = "blog-alb"
  vpc_id  = module.blog_vpc.vpc_id
  subnets = module.blog_vpc.public_subnets

  security_groups = [module.blog_sg.security_group_id]

  target_groups = {
    ex-instance = {
      name_prefix      = "blog-"
      protocol         = "HTTP"
      port             = 80
      target_type      = "instance"
      create_attachment = false
    }
  }

  listeners = {
    ex-http = {
      port            = 80
      protocol        = "HTTP"

      forward = {
        target_group_key = "ex-instance"
      }
    }
  }

  tags = {
    Environment = "dev"
  }
}

module "blog_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.3.1"
  name    = "blog"

  vpc_id = module.blog_vpc.vpc_id

  ingress_rules       = ["http-80-tcp", "https-443-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]


  egress_rules       = ["all-all"]
  egress_cidr_blocks = ["0.0.0.0/0"]
}
