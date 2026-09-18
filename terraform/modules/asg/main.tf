terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }
}

# --- Dynamic AMI Lookup: Ubuntu 24.04 LTS ---
data "aws_ami" "ubuntu" {
  count       = var.custom_ami_id == "" ? 1 : 0
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  ami_id = var.custom_ami_id != "" ? var.custom_ami_id : data.aws_ami.ubuntu[0].id
}

# --- EC2 Launch Template ---
resource "aws_launch_template" "app" {
  name_prefix   = "${var.project_name}-${var.environment}-lt-"
  image_id      = local.ami_id
  instance_type = var.instance_type

  iam_instance_profile {
    arn = var.instance_profile_arn
  }

  vpc_security_group_ids = [var.ec2_security_group_id]

  # Enforce IMDSv2 for high security
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  # Encrypted gp3 Root EBS Volume
  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_size           = var.root_volume_size
      volume_type           = "gp3"
      iops                  = 3000
      throughput            = 125
      encrypted             = true
      delete_on_termination = true
    }
  }

  # User Data Script for Bootstrapping
  user_data = base64encode(templatefile("${path.module}/user_data.sh.tpl", {
    project_name   = var.project_name
    environment    = var.environment
    app_port       = var.app_port
    db_secret_arn  = var.db_secret_arn
    db_endpoint    = var.db_endpoint
    s3_bucket_name = var.s3_bucket_name
    aws_region     = var.aws_region
  }))

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      var.common_tags,
      {
        Name = "${var.project_name}-${var.environment}-app-server"
        Tier = "Private-App"
      }
    )
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(
      var.common_tags,
      {
        Name = "${var.project_name}-${var.environment}-app-volume"
      }
    )
  }

  lifecycle {
    create_before_destroy = true
  }
}

# --- Auto Scaling Group ---
resource "aws_autoscaling_group" "app" {
  name_prefix         = "${var.project_name}-${var.environment}-asg-"
  vpc_zone_identifier = var.private_app_subnet_ids

  desired_capacity = var.desired_capacity
  min_size         = var.minimum_capacity
  max_size         = var.maximum_capacity

  target_group_arns         = [var.target_group_arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  force_delete              = false
  wait_for_capacity_timeout = "10m"

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  dynamic "tag" {
    for_each = merge(
      var.common_tags,
      {
        Name = "${var.project_name}-${var.environment}-asg-instance"
        Tier = "Private-App"
      }
    )
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity]
  }
}

# --- Target Tracking Dynamic Scaling Policy (Target CPU: 60%) ---
resource "aws_autoscaling_policy" "cpu_scaling" {
  name                   = "${var.project_name}-${var.environment}-cpu-scaling-policy"
  policy_type            = "TargetTrackingScaling"
  autoscaling_group_name = aws_autoscaling_group.app.name

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 60.0
  }
}
