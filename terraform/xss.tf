provider "aws" {
  region = "us-east-2"
}

# Define a list of availability zones
variable "availability_zones" {
  default = ["us-east-2a", "us-east-2b"]
}

resource "aws_vpc" "example" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "subnets" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.example.id
  availability_zone       = var.availability_zones[count.index]
  cidr_block              = "10.0.${4 + count.index}.0/24"
  map_public_ip_on_launch = true
}

resource "aws_security_group" "instance" {
  name        = "example-instance-sg"
  description = "Security group for the example instance"
  vpc_id      = aws_vpc.example.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ssh" {
  name        = "allow-ssh-from-internet"
  description = "Allow SSH access from the internet"
  vpc_id      = aws_vpc.example.id

  # Inbound rule to allow SSH from any source (0.0.0.0/0)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "example" {
  ami           = "ami-080c09858e04800a1"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.subnets[0].id
  key_name = "DomkoLaptop"
  security_groups = [aws_security_group.ssh.id]
  user_data = <<-EOF
#!/bin/bash
sudo yum update -y
sudo amazon-linux-extras install docker -y
sudo service docker start
sudo usermod -a -G docker ec2-user
sudo systemctl enable docker  # Start Docker on boot
git clone https://github.com/hashtagcyber/xss-sample
cd xss-sample
sudo docker build -t myscript .
sudo docker run -d --restart always -p 80:8080 myscript
EOF

  tags = {
    Name = "example-instance"
  }
}

resource "aws_lb" "example" {
  name               = "example-lb"
  internal           = false
  load_balancer_type = "application"
  subnets            = aws_subnet.subnets[*].id
}

resource "aws_lb_listener" "example" {
  load_balancer_arn = aws_lb.example.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.example.arn
  }
}

resource "aws_lb_target_group" "example" {
  name     = "example-target-group"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.example.id

  health_check {
    path                = "/"
    port                = "8080"
    protocol            = "HTTP"
    timeout             = 5
    interval            = 30
    unhealthy_threshold = 2
    healthy_threshold   = 2
  }
}

resource "aws_lb_target_group_attachment" "example" {
  count            = length(aws_subnet.subnets)
  target_group_arn = aws_lb_target_group.example.arn
  target_id        = aws_instance.example.id
}

resource "aws_internet_gateway" "example" {
  vpc_id = aws_vpc.example.id
}

# Define a public route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.example.id
}

# Create a route in the public route table to direct internet-bound traffic to the Internet Gateway
resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.example.id
}

# Associate public subnets with the public route table
resource "aws_route_table_association" "public_subnet_associations" {
  count          = length(aws_subnet.subnets)
  subnet_id      = aws_subnet.subnets[count.index].id
  route_table_id = aws_route_table.public.id
}

output "load_balancer_url" {
    value = aws_lb.example.dns_name
}
output "EC2_Instance_Connect" {
    value = "ssh ec2-user@${aws_instance.example.public_ip}"
}
