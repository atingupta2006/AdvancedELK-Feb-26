#!/bin/bash

# Setup passwordless sudo for osboxes user
# Run this ONCE on your VirtualBox

echo "Setting up passwordless sudo for osboxes user..."

ssh -o StrictHostKeyChecking=no osboxes@192.168.56.101 << 'SUDOSETUP'
# Add osboxes to sudoers for passwordless sudo
echo "osboxes ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/osboxes-nopass > /dev/null

echo "✓ Passwordless sudo configured"
echo "You can now run: sudo <command> without entering password"
SUDOSETUP

echo "Done! Now run: bash run-multinode-test.sh"
