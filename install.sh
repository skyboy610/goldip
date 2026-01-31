#!/bin/bash

# GOLDIP Auto Installer & Runner
# Download, install and run in one command

clear
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  GOLDIP Tunnel Manager - Auto Installer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check root
if [[ $EUID -ne 0 ]]; then
    echo "❌ This script must be run as root"
    echo "Please run: sudo bash install.sh"
    exit 1
fi

echo "📥 Downloading GOLDIP..."
if ! wget -q --show-progress https://raw.githubusercontent.com/skyboy610/goldip/main/goldip.sh -O /usr/local/bin/goldip 2>/dev/null; then
    if ! curl -# -L https://raw.githubusercontent.com/skyboy610/goldip/main/goldip.sh -o /usr/local/bin/goldip 2>/dev/null; then
        echo "❌ Download failed. Please check your internet connection."
        exit 1
    fi
fi

echo "⚙️  Setting up..."
chmod +x /usr/local/bin/goldip

# Create aliases
echo "🔗 Creating command aliases..."

# For bash
if [ -f ~/.bashrc ]; then
    if ! grep -q "alias gip=" ~/.bashrc 2>/dev/null; then
        echo "alias gip='goldip'" >> ~/.bashrc
    fi
fi

# For zsh
if [ -f ~/.zshrc ]; then
    if ! grep -q "alias gip=" ~/.zshrc 2>/dev/null; then
        echo "alias gip='goldip'" >> ~/.zshrc
    fi
fi

# Create symlink for 'gip' command
ln -sf /usr/local/bin/goldip /usr/local/bin/gip 2>/dev/null

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Installation Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "You can run GOLDIP using any of these commands:"
echo "  • gip"
echo "  • goldip"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Ask to run now
read -p "Do you want to run GOLDIP now? (y/n): " run_now

if [[ "$run_now" == "y" || "$run_now" == "Y" || "$run_now" == "yes" ]]; then
    echo ""
    exec /usr/local/bin/goldip
else
    echo ""
    echo "You can run it later using: gip"
    echo ""
fi
