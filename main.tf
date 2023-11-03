terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
 region = "ap-northeast-2" # Region 서울 
 access_key = "your_access_key" # IAM Access Key
 secret_key = "your_secret_key" # IAM Secret Key
}

resource "tls_private_key" "rsa_4096" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

variable "key_name" {
  description = "pem file"
  type = string
  default = "lok_pem"
}

resource "aws_key_pair" "key_pair" {
  key_name   = var.key_name
  public_key = tls_private_key.rsa_4096.public_key_openssh
}

resource "local_file" "private_key" {
  content = tls_private_key.rsa_4096.private_key_pem
  filename = var.key_name
}

#VPC 생성하기
resource "aws_vpc" "demoVPC" {
  cidr_block = "10.10.0.0/16"
}
 
#서브넷 생성하기 ( 가용영역A )
resource "aws_subnet" "demoSubnet_a" {
  vpc_id     = aws_vpc.demoVPC.id
  cidr_block = "10.10.1.0/24"
  availability_zone = "ap-northeast-2a"
 
  tags = {
    Name = "demoSubnet_a"
  }
}
 
#서브넷 생성하기2 ( 가용영역B )
resource "aws_subnet" "demoSubnet_b" {
  vpc_id     = aws_vpc.demoVPC.id
  cidr_block = "10.10.2.0/24"
  availability_zone = "ap-northeast-2c"
 
  tags = {
    Name = "demoSubnet_b"
  }
}

#인터넷 게이트웨이 생성하기
resource "aws_internet_gateway" "demo-igw" {
  vpc_id = aws_vpc.demoVPC.id
 
  tags = {
    Name = "main"
  }
}
 
#라우팅 테이블 생성하기
resource "aws_route_table" "demo-rt" {
  vpc_id = aws_vpc.demoVPC.id
 
  route {
    cidr_block = "0.0.0.0/0" #인터넷 게이트웨이 
    gateway_id = aws_internet_gateway.demo-igw.id
  }
 
  tags = {
    Name = "demo-rt"
  }
}
 
# 라우팅 테이블 어소시에이션 생성하기1
resource "aws_route_table_association" "demo-rt-association_a" {
  subnet_id      = aws_subnet.demoSubnet_a.id 
  route_table_id = aws_route_table.demo-rt.id
}
 
# 라우팅 테이블 어소시에이션 생성하기2
resource "aws_route_table_association" "demo-rt-association_b" {
  subnet_id      = aws_subnet.demoSubnet_b.id 
  route_table_id = aws_route_table.demo-rt.id
}

resource "aws_security_group" "demoVPC-sg" {
  name        = "demoVPC-sg"
  vpc_id      = aws_vpc.demoVPC.id

  ingress {
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_tls"
  }
}

# 로드밸런서 생성하기
resource "aws_lb" "demo-alb" {
  name               = "demo-alb"
  internal           = false # 외부 트래픽 접근 가능
  load_balancer_type = "application"
  security_groups    = [aws_security_group.demoVPC-sg.id]
  subnets            = [aws_subnet.demoSubnet_a.id, aws_subnet.demoSubnet_b.id]
}
 
# 로드밸런서 Listener 생성하기
resource "aws_lb_listener" "demo-lb-listener" {
  load_balancer_arn = aws_lb.demo-alb.arn
  port              = "80"
  protocol          = "HTTP"
 
  default_action {
    type             = "forward" # forward or redirect or fixed-response
    target_group_arn = aws_lb_target_group.my_tg.arn
  }
}
 
# 대상그룹 생성하기
resource "aws_lb_target_group" "my_tg" {
  name     = "my-tg"
  target_type = "instance"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.demoVPC.id
}

# 인스턴스 생성하기
resource "aws_launch_template" "my_launch_template" {
 
  name = "my_launch_template"
  image_id = "ami-086cae3329a3f7d75" # 인스턴스 이미지
  instance_type = "t2.micro" # 인스턴스 타입
  key_name = aws_key_pair.key_pair.key_name #SSH Key 정보
 
  # 인스턴시 Lanuch시 실행될 명령어 모음
  user_data = filebase64("${path.module}/server.sh")
 
  network_interfaces {
    associate_public_ip_address = true # Public IP 생성
    security_groups = [ aws_security_group.demoVPC-sg.id ] #보안그룹 설정
  }
}
 
# AutoScaling Group 생성하기
resource "aws_autoscaling_group" "my-asg" {
  name                      = "my-asg"
  max_size                  = 2
  min_size                  = 2
  desired_capacity          = 2
  target_group_arns = [aws_lb_target_group.my_tg.arn]
  vpc_zone_identifier       = [ aws_subnet.demoSubnet_a.id, aws_subnet.demoSubnet_b.id ]
  
  launch_template {
    id      = aws_launch_template.my_launch_template.id
    version = "$Latest"
  }
} 