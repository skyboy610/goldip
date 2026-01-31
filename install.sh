#!/bin/bash

# GOLDIP - Quick Installation & Setup Guide
# ==========================================

echo "Installing GOLDIP Tunnel Manager..."

# Download and install the script
wget -O /usr/local/bin/gip https://raw.githubusercontent.com/your-repo/goldip/main/goldip.sh 2>/dev/null || \
curl -o /usr/local/bin/gip https://raw.githubusercontent.com/your-repo/goldip/main/goldip.sh 2>/dev/null

# Make it executable
chmod +x /usr/local/bin/gip

# Create alias 'gip' for easy access
if ! grep -q "alias gip=" ~/.bashrc 2>/dev/null; then
    echo "alias gip='/usr/local/bin/gip'" >> ~/.bashrc
fi

if ! grep -q "alias gip=" ~/.zshrc 2>/dev/null; then
    echo "alias gip='/usr/local/bin/gip'" >> ~/.zshrc 2>/dev/null
fi

echo ""
echo "✓ Installation complete!"
echo ""
echo "You can now run GOLDIP using any of these commands:"
echo "  - gip"
echo "  - /usr/local/bin/gip"
echo ""
echo "Please restart your terminal or run: source ~/.bashrc"
echo ""
