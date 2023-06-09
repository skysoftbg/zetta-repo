locals {
  azs = data.aws_availability_zones.available.names
}
data "aws_availability_zones" "available" {}

resource "aws_key_pair" "wordpress_auth" {
  key_name   = var.key_name
  public_key = file(var.public_key_path)
}

resource "aws_instance" "wordpress" {
  count                  = var.instance_count
  ami                    = "ami-007855ac798b5175e"
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.sg.id]
  subnet_id              = aws_subnet.public_subnet[count.index].id
  key_name               = aws_key_pair.wordpress_auth.id

  tags = {
    Name = "wordpress-instance-${count.index + 1}"
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("./id_rsa")
    host        = self.public_ip
  }


  provisioner "remote-exec" {
    inline = [
      "sudo apt update -y",
      "sudo apt install python3-pip -y",
      "python3 -m pip install --user ansible",
    ]
  }
  depends_on = [aws_key_pair.wordpress_auth]

}
resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "wordpress-vpc"
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "wordpress_igw"
  }
}

resource "aws_subnet" "public_subnet" {
  count                   = length(local.azs)
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = var.public_cidr[count.index]
  map_public_ip_on_launch = true
  availability_zone       = local.azs[count.index]


  tags = {
    Name = "wordpress-public-${count.index + 1}"

  }
}

resource "aws_security_group" "sg" {
  name        = "public_sg"
  description = "Security group for public instances"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    from_port        = 22
    to_port          = 22
    protocol         = "TCP"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    from_port        = 80
    to_port          = 80
    protocol         = "TCP"
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
}
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "wordpress-public"
  }
}

resource "aws_route" "default_route" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_assoc" {
  count          = length(local.azs)
  subnet_id      = aws_subnet.public_subnet.*.id[count.index]
  route_table_id = aws_route_table.public_rt.id
}


output "wordpress_access" {
  value = { for i in aws_instance.wordpress[*] : i.tags.Name => "${i.public_ip}" }
}

output "instance_ips" {
  value = [for i in aws_instance.wordpress[*] : i.public_ip]
}

output "instance_ids" {
  value = [for i in aws_instance.wordpress[*] : i.id]
}
