#!/bin/bash

# PostgreSQL Toggle Script for External Drive
# This script toggles PostgreSQL on/off and provides status

case "$1" in
    start)
        ~/dotfiles/postgres-external-scripts/pg-startup.sh
        ;;
    stop)
        ~/dotfiles/postgres-external-scripts/pg-shutdown.sh
        ;;
    status)
        echo "📊 PostgreSQL Status:"
        echo ""
        
        # Check service status
        if brew services list | grep -q "postgresql@16.*started"; then
            echo "✅ PostgreSQL is RUNNING"
            
            # Check if we can connect
            if psql -d postgres -c "SELECT 1;" > /dev/null 2>&1; then
                echo "✅ Database connection is ACTIVE"
            else
                echo "⚠️  Service is running but cannot connect to database"
            fi
        else
            echo "🛑 PostgreSQL is STOPPED"
        fi
        
        echo ""
        
        # Check external drive
        if [ -d "/Volumes/Expansion" ]; then
            echo "💾 External drive 'Expansion' is MOUNTED"
            
            # Check data directory
            if [ -d "/Volumes/Expansion/postgresql@16" ]; then
                echo "✅ PostgreSQL data directory found on external drive"
                
                # Show disk usage
                SIZE=$(du -sh /Volumes/Expansion/postgresql@16 2>/dev/null | cut -f1)
                echo "📏 Data directory size: $SIZE"
            else
                echo "❌ PostgreSQL data directory NOT FOUND on external drive"
            fi
        else
            echo "❌ External drive 'Expansion' is NOT MOUNTED"
        fi
        ;;
    *)
        echo "PostgreSQL External Drive Manager"
        echo ""
        echo "Usage:"
        echo "  $0 start   - Start PostgreSQL (checks if drive is mounted)"
        echo "  $0 stop    - Stop PostgreSQL (prepares for safe drive removal)"
        echo "  $0 status  - Show PostgreSQL and drive status"
        echo ""
        echo "Quick aliases you can add to ~/.zshrc:"
        echo "  alias pgstart='~/dotfiles/postgres-external-scripts/pg-toggle.sh start'"
        echo "  alias pgstop='~/dotfiles/postgres-external-scripts/pg-toggle.sh stop'"
        echo "  alias pgstatus='~/dotfiles/postgres-external-scripts/pg-toggle.sh status'"
        ;;
esac
