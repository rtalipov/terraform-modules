provider "aws" {
  region = "eu-west-1"
}

# Define variables as Locals instead of Variables. 
# Will have impact only on the module

locals {
  http_port = 80
  any_port = 0
  any_protocol = "-1"
  tcp_protocol = "tcp"
  all_ips = ["0.0.0.0/0"]
}

resource "aws_launch_configuration" "example" {
  image_id           = "ami-0943382e114f188e8"
  instance_type = var.instance_type
  security_groups = [aws_security_group.instance_sg.id]

  # The template_file data source has two arguments: 
  # template, which is a string to render, and vars, which is a map of variables 
  # to make available while rendering. It has one output attribute called rendered, 
  # which is the result of rendering template.
  
  user_data = data.template_file.user_data.rendered

  lifecycle {
    create_before_destroy = true
  }
}

# To allow the EC2 Instance to receive traffic on port 8080

resource "aws_security_group" "instance_sg" {
  name = "${var.cluster_name}-instance"

  ingress {
    from_port   = var.server_port
    to_port     = var.server_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource aws_autoscaling_group "asg" {
  launch_configuration = aws_launch_configuration.example.name
  vpc_zone_identifier = data.aws_subnet_ids.default-subnet.ids

  target_group_arns = [aws_lb_target_group.asg-tg.arn]
  health_check_type = "ELB"

  max_size                  = var.max_size
  min_size                  = var.min_size

  tag {
      key                 = "Name"
      value               = "var.cluster_name"
      propagate_at_launch = true
    }
}

// Instruct terraform to find default VPC

data "aws_vpc" "default-vpc" {
  default = true
}

#data.<PROVIDER>_<TYPE>.<NAME>.<ATTRIBUTE>
data "aws_subnet_ids" "default-subnet" {
  vpc_id = data.aws_vpc.default-vpc.id
}

resource "aws_lb" "example_lb" {
  name = "${var.cluster_name}-alb"
  load_balancer_type = "application"
  subnets = data.aws_subnet_ids.default-subnet.ids
  security_groups = [aws_security_group.alb-sg.id]
}

resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.example_lb.arn
  port = local.http_port
  protocol = "HTTP"

  # By default, return a simple 404 page

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code  = 404
    }
  }
}

resource "aws_security_group" "alb-sg" {
  name = "${var.cluster_name}-alb"
}

resource "aws_security_group_rule" "allow_http_inbound" {
  type = "ingress"
  security_group_id = aws_security_group.alb-sg.id

  # Allow inbound HTTP requests
    from_port   = local.http_port
    to_port     = local.http_port
    protocol    = local.tcp_protocol
    cidr_blocks = local.all_ips
}

resource "aws_security_group_rule" "allow_all_outgound"{
  type = "egress"
  security_group_id = aws_security_group.alb-sg.id

  # Allow all outbound requests
    from_port   = local.any_port
    to_port     = local.any_port
    protocol    = local.any_protocol
    cidr_blocks = local.all_ips
}

resource "aws_lb_target_group" "asg-tg" {
  name = "terraform-asg-target-group"
  port = var.server_port
  protocol = "HTTP"
  vpc_id = data.aws_vpc.default-vpc.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener_rule" "asg" {
  listener_arn = aws_lb_listener.http_listener.arn
  priority = 100

  condition {
    path_pattern {
      values = ["*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.asg-tg.arn
  }
}


#Terraform State rosource, pointing the key to SQL state file

data "terraform_remote_state" "db" {
    backend = "s3"

    config = {
        bucket = var.db_remote_state_bucket
        key = var.db_remote_state_key
        region = "eu-west-1"
    }
}

# now we read the output values from remote_state using the format:
# data.terraform_remote_state.<NAME>.outputs.<ATTRIBUTE>


data "template_file" "user_data" {
  # path.modul - returns the filesystem path of the module where the expression is defined.
    template = file("${path.module}/user-data.sh")

    vars = {
        server_port = var.server_port
        db_address = data.terraform_remote_state.db.outputs.address
        db_port = data.terraform_remote_state.db.outputs.port
    }
}

#comment for test