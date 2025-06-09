#!/bin/bash
exec > >(tee /var/log/user-data.log) 2>&1

# === System prep ===
sudo yum update -y
amazon-linux-extras install docker -y
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -a -G docker ec2-user

# === Mount EBS volume ===
DEVICE=$(lsblk -ndo NAME | grep -w disk | grep -v nvme0n1 | head -n 1)
sudo mkfs -t ext4 /dev/$DEVICE
sudo mkdir -p /mnt/db
sudo mount /dev/$DEVICE /mnt/db
echo "/dev/${DEVICE} /mnt/db ext4 defaults,nofail 0 2" >> /etc/fstab

# === Install Git ===
sudo yum install git -y
cd /home/ec2-user

# === Clone repositories ===
sudo git clone https://github.com/3d014/htec_backend.git
sudo git clone https://github.com/3d014/htec_frontend.git

# === Get Public IP ===
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

# === Create Docker network ===
docker network create htec_network

# === Build Docker images ===
sudo docker build \
  --build-arg VITE_BACKEND_URL="http://$PUBLIC_IP:5000" \
  -t htec_frontend_image ./htec_frontend

sudo docker build -t htec_backend_image ./htec_backend

# === Start MySQL ===
sudo docker run -d --name htec_mysql --network htec_network \
  -e MYSQL_ROOT_PASSWORD=root \
  -e MYSQL_DATABASE=htec \
  -v /mnt/db:/var/lib/mysql \
  mysql:8.0

# === Wait for MySQL to be ready ===
until docker exec htec_mysql mysqladmin ping -h "localhost" -u root -proot --silent; do
  sleep 2
done

# === Init DB ===
sudo docker exec htec_mysql mysql -u root -proot -e "CREATE DATABASE IF NOT EXISTS htec;"

# === Start backend ===
sudo docker run -d --name htec_backend --network htec_network \
  -e DB_NAME=htec \
  -e DB_USER=root \
  -e DB_PASSWORD=root \
  -e DB_HOST=htec_mysql \
  -e JWT_SECRET_KEY=e6KQpx9DnQ2ecwgAn5RqXzHefN0KRTXL \
  -e SMTP_USER=MS_j886YX@trial-neqvygm9708l0p7w.mlsender.net \
  -e SMTP_PASSWORD=mo21HlHYkMVf9OWU \
  -e SMTP_PORT=587 \
  -e SMTP_HOST=smtp.mailersend.net \
  -e APP_URL=http://$PUBLIC_IP/ \
  -e EXCHANGE_API_KEY=3182dfdf82d7f23578880c6f \
  -e EXCHANGE_API_URL=https://api.exchangerate-api.com/v4/latest/BAM \
  -p 5000:5000 \
  htec_backend_image

# === Start frontend (with Nginx) ===
# Dockerfile for frontend must serve /dist with nginx
sudo docker run -d --name htec_frontend --network htec_network \
  -p 80:80 \
  htec_frontend_image
