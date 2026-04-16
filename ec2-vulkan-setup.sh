#!/bin/bash
# MiniPrem Vulkan Test Setup Script for EC2 Ubuntu 22.04
# Run this on the EC2 instance after SSH connection

set -e

echo "🚀 MiniPrem Vulkan Test Setup"
echo "=============================="
echo ""

# Update system
echo "📦 Updating system packages..."
sudo apt-get update

# Install Docker
echo "🐳 Installing Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker ubuntu
rm get-docker.sh

# Install Docker Compose
echo "🔧 Installing Docker Compose..."
sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.5/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Install NVIDIA drivers 580.82.09 (UneeQ recommended good version)
echo "🎮 Installing NVIDIA Driver 580.82.09..."
sudo apt-get install -y linux-headers-$(uname -r)
wget https://us.download.nvidia.com/XFree86/Linux-x86_64/580.82.09/NVIDIA-Linux-x86_64-580.82.09.run
sudo sh NVIDIA-Linux-x86_64-580.82.09.run --silent --dkms
rm NVIDIA-Linux-x86_64-580.82.09.run

# Install NVIDIA Container Toolkit
echo "📦 Installing NVIDIA Container Toolkit..."
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# Clone MiniPrem repo and checkout Vulkan branch
echo "📥 Cloning MiniPrem repository..."
cd ~
git clone https://gitlab.com/tgmerritt/miniprem-2025.git
cd miniprem-2025
git checkout origin/fix/renny-vulkan-driver-580-rtx5090-support

# Verify setup
echo ""
echo "✅ Setup Complete!"
echo "=================="
echo ""
echo "📊 System Information:"
echo "----------------------"
echo "Docker version:"
docker --version
echo ""
echo "Docker Compose version:"
docker-compose --version
echo ""
echo "NVIDIA Driver version:"
nvidia-smi --query-gpu=driver_version --format=csv,noheader
echo ""
echo "GPU Information:"
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
echo ""
echo "🎯 Next Steps:"
echo "--------------"
echo "1. Log out and back in (or run: newgrp docker)"
echo "2. cd ~/miniprem-2025"
echo "3. Run: ./docker/scripts/install_miniprem.sh"
echo "4. Test single Renny container"
echo "5. Test multiple Renny containers for GPU pegging"
echo ""
echo "📝 Branch checked out: fix/renny-vulkan-driver-580-rtx5090-support"
echo "🔧 Driver version: 580.82.09 (UneeQ recommended)"
echo ""
