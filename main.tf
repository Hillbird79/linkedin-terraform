data "aws_ami" "app_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["bitnami-tomcat-*-x86_64-hvm-ebs-nami"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["979382823631"] # Bitnami
}

module "blog_vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "dev"
  cidr = "10.0.0.0/16"

  azs            = ["us-west-2a","us-west-2b","us-west-2c"]
  public_subnets = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

module "blog_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "4.13.0"

  vpc_id  = module.blog_vpc.vpc_id
  name    = "blog"

  ingress_rules       = ["https-443-tcp","http-80-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]

  egress_rules        = ["all-all"]
  egress_cidr_blocks  = ["0.0.0.0/0"]
}

# --- Minimal ALB without GPU/inference flags ---
resource "aws_lb" "blog" {
  name               = "blog-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [module.blog_sg.security_group_id]
  subnets            = module.blog_vpc.public_subnets
}

resource "aws_lb_target_group" "blog" {
  name     = "blog-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.blog_vpc.vpc_id
  target_type = "instance"
}

resource "aws_lb_listener" "blog" {
  load_balancer_arn = aws_lb.blog.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blog.arn
  }
}

module "blog_autoscaling" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "6.5.2"

  name = "blog"

  min_size            = 1
  max_size            = 2
  vpc_zone_identifier = module.blog_vpc.public_subnets
  target_group_arns   = [aws_lb_target_group.blog.arn]
  security_groups     = [module.blog_sg.security_group_id]
  instance_type       = var.instance_type # set to "t3.nano" for Free Tier
  image_id            = data.aws_ami.app_ami.id
}
