# Provider Configuration
provider "aws" {
  region = "us-east-1"
}

# VPC
resource "lamars_aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = {
    Name = "main-vpc"
  }
}

# Subnets
resource "aws_subnet" "lamars_public_subnet" {
  vpc_id     = lamars_aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone = "us-east-1a"
  tags = {
    Name = "public-subnet"
  }
}

resource "aws_subnet" "lamars_private_subnet" {
  vpc_id     = lamars_aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name = "private-subnet"
  }
}

# Internet Gateway
resource "lamars_internet_gateway" "main" {
  vpc_id = lamars_aws_vpc.main.id
  tags = {
    Name = "main-igw"
  }
}

# Route Table for Public Subnet
resource "lamars_route_table" "public_rt" {
  vpc_id = lamars_aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = lamars_internet_gateway.main.id
  }

  tags = {
    Name = "public_rt"
  }
}

resource "lamars_route_table_association" "lamars_public_subnet_association" {
  subnet_id      = aws_subnet.lamars_public_subnet.id
  route_table_id = lamars_route_table.public_rt.id
}

# Security Groups
resource "lamars_mysql_sg" "mysql_sg" {
  vpc_id = lamars_aws_vpc.main.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [lamars_mysql_sg.wordpress_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "mysql-sg"
  }
}

resource "lamars_mysql_sg" "wordpress_sg" {
  vpc_id = lamars_aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
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
    Name = "wordpress-sg"
  }
}

# MySQL Instance
resource "lamars_mysql_server" "mysql_instance" {
  ami           = "ami-0e2c8caa4b6378d8c" 
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.lamars_private_subnet.id
  security_groups = [lamars_mysql_sg.mysql_sg.name]

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update
              sudo apt install -y mysql-server
              sudo sed -i "s/bind-address.*/bind-address = 0.0.0.0/" /etc/mysql/mysql.conf.d/mysqld.cnf
              sudo systemctl restart mysql
              sudo mysql -e "CREATE DATABASE wordpress_db;"
              sudo mysql -e "CREATE USER 'wp_user'@'%' IDENTIFIED BY 'secure_password';"
              sudo mysql -e "GRANT ALL PRIVILEGES ON wordpress_db.* TO 'wp_user'@'%';"
              sudo mysql -e "FLUSH PRIVILEGES;"
            EOF

  tags = {
    Name = "mysql-instance"
  }
}

# WordPress Instance
resource "lamars_wp_server" "wordpress_instance" {
  ami           = "ami-0e2c8caa4b6378d8c" 
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.lamars_public_subnet.id
  security_groups = [lamars_mysql_sg.wordpress_sg.name]

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update
              sudo apt install -y apache2 php php-mysql wget
              wget https://wordpress.org/latest.tar.gz
              tar -xvzf latest.tar.gz
              sudo mv wordpress /var/www/html/
              sudo chown -R www-data:www-data /var/www/html/wordpress
              sudo chmod -R 755 /var/www/html/wordpress
              echo "Database Host: ${aws_instance.mysql_instance.private_ip}" > /tmp/db.txt
            EOF

  tags = {
    Name = "wordpress-instance"
  }
}

# Output EC2 instance public IP
output "public_ip" {
  value = lamars_wp_server.wordpress_instance.public_ip
}