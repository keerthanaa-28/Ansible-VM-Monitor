terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.9.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.0.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

# Generate a new RSA private key
resource "tls_private_key" "ansible_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Create AWS key pair using the generated public key
resource "aws_key_pair" "ansible_key" {
  key_name   = "AK-ansible"
  public_key = tls_private_key.ansible_key.public_key_openssh
}

# Save the private key to a local file with restricted permissions
resource "local_file" "private_key" {
  content          = tls_private_key.ansible_key.private_key_pem
  filename         = "${path.module}/ansible_key.pem"
  file_permission  = "0600"
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "ansible-vpc"
  }
}

resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  tags = {
    Name = "ansible-subnet"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "ansible-igw"
  }
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "ansible-public-rt"
  }
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "rt_assoc" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.rt.id
}

resource "aws_security_group" "ansible_sg" {
  name        = "ansible-sg"
  description = "Security group for ansible"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 587
    to_port     = 587
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 3000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "ansible_master" {
  ami                         = "ami-021a584b49225376d"  # Ubuntu 22.04 LTS (x86) Mumbai region
  instance_type               = "t2.medium"
  subnet_id                   = aws_subnet.main.id
  associate_public_ip_address = true
  key_name                   = aws_key_pair.ansible_key.key_name
  vpc_security_group_ids      = [aws_security_group.ansible_sg.id]

  root_block_device {
    volume_size = 20  # 20GB storage
    volume_type = "gp2"
  }

  tags = {
    Name = "Ansible-Master"
    Role = "master"
  }
}

resource "aws_instance" "web" {
  count                      = 10
  ami                        = "ami-021a584b49225376d"
  instance_type              = "t2.small"
  subnet_id                  = aws_subnet.main.id
  associate_public_ip_address = true
  key_name                   = aws_key_pair.ansible_key.key_name
  vpc_security_group_ids     = [aws_security_group.ansible_sg.id]

  root_block_device {
    volume_size = 15  # 15GB storage
    volume_type = "gp2"
  }

  tags = {
    Name        = "web${count.index + 1}"
    Environment = "dev"
    Role        = "web"
  }
}
