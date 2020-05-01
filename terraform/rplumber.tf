provider "aws" {
  region = "us-east-2"
  access_key = "xxx"
  secret_key = "xxx"
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"]
}

resource "aws_ecr_repository" "rplumber" {
  name                 = "rplumber"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_default_vpc" "default" {
  tags = {
    Name = "Default VPC"
  }
}

resource "aws_subnet" "elb-1" {
  vpc_id     = aws_default_vpc.default.id
  cidr_block = "172.31.128.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "elb-1"
  }
}

resource "aws_subnet" "elb-2" {
  vpc_id     = aws_default_vpc.default.id
  cidr_block = "172.31.129.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "elb-2"
  }
}

resource "aws_security_group" "elb" {
  name        = "elb-secgroup"
  description = "Allow HTTP/HTTPS inbound traffic"
  vpc_id      = aws_default_vpc.default.id

  ingress {
    description = "Allow HTTPS"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "elb-secgroup"
  }
}

resource "aws_lb" "rplumber-elb" {
  name               = "rplumber-elb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.elb.id]
  subnets            = [aws_subnet.elb-1.id, aws_subnet.elb-2.id]

  tags = {
    Environment = "interview"
  }
}

resource "aws_security_group" "rplumber-node-secgroup" {
  name        = "rplumber-node-secgroup"
  description = "Allow SSH and HTTP 8000 inbound traffic"
  vpc_id      = aws_default_vpc.default.id

  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTP Port 8000"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    security_groups = [aws_security_group.elb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "rplumber-node-secgroup"
  }
}

resource "aws_iam_role" "rplumber-role" {
  name = "rplumber-role"
  path = "/"

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Principal": {
               "Service": "ec2.amazonaws.com"
            },
            "Effect": "Allow",
            "Sid": ""
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "rplumber-policy-attach" {
  role       = aws_iam_role.rplumber-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "rplumber-profile" {
  name = "rplumber-profile"
  role = aws_iam_role.rplumber-role.name
}

resource "aws_instance" "rplumber-1" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  key_name = "rplumber"
  vpc_security_group_ids = [aws_security_group.rplumber-node-secgroup.id]
  subnet_id = aws_subnet.elb-1.id
  iam_instance_profile = aws_iam_instance_profile.rplumber-profile.id

  tags = {
    Name = "rplumber-1"
  }

  depends_on = [
    aws_security_group.rplumber-node-secgroup
  ]
}

resource "aws_instance" "rplumber-2" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  key_name = "rplumber"
  vpc_security_group_ids = [aws_security_group.rplumber-node-secgroup.id]
  subnet_id = aws_subnet.elb-2.id
  iam_instance_profile = aws_iam_instance_profile.rplumber-profile.id

  tags = {
    Name = "rplumber-2"
  }

  depends_on = [
    aws_security_group.rplumber-node-secgroup
  ]
}

resource "aws_lb_target_group" "rplumber-targetgroup" {
  name     = "rplumber-targetgroup"
  port     = 8000
  protocol = "HTTP"
  vpc_id   = aws_default_vpc.default.id
}

resource "aws_lb_target_group_attachment" "rplumber-1-targetgroup-attach" {
  target_group_arn = aws_lb_target_group.rplumber-targetgroup.arn
  target_id        = aws_instance.rplumber-1.id
  port             = 8000
}

resource "aws_lb_target_group_attachment" "rplumber-2-targetgroup-attach" {
  target_group_arn = aws_lb_target_group.rplumber-targetgroup.arn
  target_id        = aws_instance.rplumber-2.id
  port             = 8000
}

resource "aws_lb_listener" "rplumber" {
  load_balancer_arn = aws_lb.rplumber-elb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.rplumber-targetgroup.arn
  }
}
