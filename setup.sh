#!/bin/bash

# Setup script for Lexi

echo "🚀 Setting up Lexi..."

# Check if .env file exists
if [ ! -f .env ]; then
    echo "📝 Creating .env file from template..."
    cp .env.example .env
    echo "⚠️  Please edit .env file and add your ANTHROPIC_API_KEY"
else
    echo "✅ .env file already exists"
fi

# Check if Swift is installed
if ! command -v swift &> /dev/null; then
    echo "❌ Swift is not installed. Please install Xcode from the App Store."
    exit 1
fi

echo "✅ Swift is installed"

# Resolve dependencies
echo "📦 Resolving Swift package dependencies..."
swift package resolve

echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "1. Edit .env and add your ANTHROPIC_API_KEY"
echo "2. Run: swift run Lexi"
echo "3. Grant Accessibility permissions when prompted"