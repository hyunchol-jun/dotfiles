#!/bin/bash

# PostgreSQL Startup Script for External Drive
# This script checks if the external drive is mounted and starts PostgreSQL

echo "🚀 Starting PostgreSQL..."

# Check if external drive is mounted
if [ ! -d "/Volumes/Expansion" ]; then
    echo "❌ External drive 'Expansion' is not mounted!"
    echo "   Please connect your external drive first."
    exit 1
fi

# Check if PostgreSQL data directory exists on external drive
if [ ! -d "/Volumes/Expansion/postgresql@16" ]; then
    echo "❌ PostgreSQL data directory not found on external drive!"
    echo "   Expected location: /Volumes/Expansion/postgresql@16"
    exit 1
fi

# Start PostgreSQL service
brew services start postgresql@16

# Wait a moment for the service to start
sleep 3

# Verify PostgreSQL is running
if brew services list | grep -q "postgresql@16.*started"; then
    echo "✅ PostgreSQL started successfully!"
    
    # Test connection
    if psql -d postgres -c "SELECT version();" > /dev/null 2>&1; then
        echo "✅ Database connection verified!"
    else
        echo "⚠️  PostgreSQL is running but connection test failed."
        echo "   This might be normal during startup. Try again in a few seconds."
    fi
else
    echo "❌ Failed to start PostgreSQL. Check logs for details:"
    echo "   brew services info postgresql@16"
    exit 1
fi
