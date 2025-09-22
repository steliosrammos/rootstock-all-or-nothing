#!/bin/bash

# AON CLI Installation Script

set -e

echo "🚀 Installing AON CLI..."

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo "❌ Node.js is not installed. Please install Node.js >= 16.0.0"
    echo "   Visit: https://nodejs.org/"
    exit 1
fi

# Check Node version
NODE_VERSION=$(node -v | sed 's/v//')
REQUIRED_VERSION="16.0.0"

if [ "$(printf '%s\n' "$REQUIRED_VERSION" "$NODE_VERSION" | sort -V | head -n1)" != "$REQUIRED_VERSION" ]; then 
    echo "❌ Node.js version $NODE_VERSION is not supported. Please install Node.js >= 16.0.0"
    exit 1
fi

echo "✅ Node.js $NODE_VERSION detected"

# Remove any existing node_modules and package-lock.json to start fresh
if [ -d "node_modules" ]; then
    echo "🧹 Cleaning existing installation..."
    rm -rf node_modules
fi

if [ -f "package-lock.json" ]; then
    rm -f package-lock.json
fi

if [ -f "yarn.lock" ]; then
    rm -f yarn.lock
    echo "🧹 Removed yarn.lock to prevent conflicts"
fi

# Install dependencies
echo "📦 Installing dependencies with npm..."
npm install

# Build the CLI
echo "🔨 Building CLI..."
npm run build

# Ask user if they want to link globally
echo ""
read -p "🔗 Do you want to install the CLI globally (allows 'aon-cli' command)? [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🔗 Linking CLI globally..."
    npm link
    CLI_COMMAND="aon-cli"
    echo "✅ CLI linked globally! You can now use 'aon-cli' from anywhere."
else
    CLI_COMMAND="npm run dev"
    echo "ℹ️  CLI not linked globally. Use 'npm run dev' to run commands."
fi

# Check for .env file and offer to create it
echo ""
if [ ! -f "./.env" ] && [ -f "./env.example" ]; then
    read -p "📄 Do you want to create a .env file from env.example for easier usage? [y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cp ./env.example ./.env
        echo "✅ Created .env file from env.example"
        echo "ℹ️  You can now run commands without --private-key flag"
    fi
fi

# Initialize configuration
echo ""
echo "⚙️  Initializing configuration..."
if [[ $CLI_COMMAND == "aon-cli" ]]; then
    aon-cli setup init
else
    npm run dev setup init
fi

echo ""
echo "🎉 AON CLI installed successfully!"
echo ""
echo "Quick start:"
if [[ $CLI_COMMAND == "aon-cli" ]]; then
    echo "  aon-cli setup start -d        # Start local Anvil node"
    echo "  aon-cli deploy                # Deploy contracts"
    echo "  aon-cli --help                # Show all commands"
    echo ""
    echo "To uninstall globally: npm run unlink:global"
else
    echo "  npm run dev setup start -d    # Start local Anvil node"
    echo "  npm run dev deploy            # Deploy contracts"
    echo "  npm run dev --help            # Show all commands"
    echo ""
    echo "To install globally later: npm run link:global"
fi
echo ""
echo "For more information, see: cli/README.md"
