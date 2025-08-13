#!/bin/bash

# PostgreSQL Shutdown Script for External Drive
# This script safely shuts down PostgreSQL before you can remove your external drive

echo "🛑 Stopping PostgreSQL..."

# Stop PostgreSQL service
brew services stop postgresql@16

# Wait a moment for the service to fully stop
sleep 2

# Check if PostgreSQL is still running
if brew services list | grep -q "postgresql@16.*started"; then
    echo "❌ Failed to stop PostgreSQL. Please check manually."
    exit 1
else
    echo "✅ PostgreSQL stopped successfully!"
    echo ""
    echo "📦 You can now safely eject your external drive:"
    echo "   - Use Finder to eject 'Expansion'"
    echo "   - Or run: diskutil eject /Volumes/Expansion"
    echo ""
fi