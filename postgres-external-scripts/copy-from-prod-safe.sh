#!/bin/bash

# Safe version that checks for existing data before copying
# Based on copy-from-prod.sh but skips tables with existing data

# Configuration - EDIT THESE VALUES
REMOTE_HOST="localhost"
REMOTE_PORT="9001"
REMOTE_DB="app"
REMOTE_USER="v-oidc-822-reader-i-6V8Dy4a5Bwlp5bPOXmqI-1750357823"
REMOTE_PASS="R3-c-huKVO2Gx8f0ARHe"
LOCAL_DB="implentio_local"

# Schemas to copy (space-separated list)
SCHEMAS_TO_COPY="cdm client"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check if table has data
table_has_data() {
    local schema=$1
    local table=$2
    local count=$(psql -d $LOCAL_DB -t -c "SELECT COUNT(*) FROM $schema.$table" 2>/dev/null || echo "0")
    count=$(echo $count | tr -d ' ')
    [ "$count" -gt "0" ]
}

# Function to copy tables selectively
copy_tables_safe() {
    echo -e "${GREEN}Starting selective table copy...${NC}"
    
    # Get list of tables from remote
    for schema in $SCHEMAS_TO_COPY; do
        echo -e "${YELLOW}Processing schema: $schema${NC}"
        
        # Get table list
        tables=$(PGPASSWORD=$REMOTE_PASS psql -h $REMOTE_HOST -p $REMOTE_PORT -U $REMOTE_USER -d $REMOTE_DB -t -c "
            SELECT table_name 
            FROM information_schema.tables 
            WHERE table_schema = '$schema' 
            AND table_type = 'BASE TABLE'
            ORDER BY table_name")
        
        for table in $tables; do
            table=$(echo $table | tr -d ' ')
            if [ -z "$table" ]; then continue; fi
            
            # Check if table exists and has data
            if table_has_data "$schema" "$table"; then
                row_count=$(psql -d $LOCAL_DB -t -c "SELECT COUNT(*) FROM $schema.$table")
                echo -e "${YELLOW}⏭️  Skipping $schema.$table (already has $row_count rows)${NC}"
            else
                echo -e "${GREEN}📥 Copying $schema.$table...${NC}"
                
                # Copy table structure and data
                if [ -f "/opt/homebrew/opt/postgresql@16/bin/pg_dump" ]; then
                    PGPASSWORD=$REMOTE_PASS /opt/homebrew/opt/postgresql@16/bin/pg_dump \
                        -h $REMOTE_HOST -p $REMOTE_PORT -U $REMOTE_USER -d $REMOTE_DB \
                        -t $schema.$table --no-owner --no-acl | \
                        sed "s/CREATE TABLE/CREATE TABLE IF NOT EXISTS/g" | \
                        psql -d $LOCAL_DB -q
                else
                    echo -e "${RED}Error: PostgreSQL 16 required${NC}"
                    exit 1
                fi
            fi
        done
    done
}

# Main execution
echo -e "${GREEN}Safe Production Database Copy Tool${NC}"
echo -e "${YELLOW}This version skips tables that already contain data${NC}"
echo ""

# Create database and extensions if needed
createdb $LOCAL_DB 2>/dev/null || true
psql -d $LOCAL_DB -c "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";" 2>/dev/null || true

# Create schemas
for schema in $SCHEMAS_TO_COPY; do
    psql -d $LOCAL_DB -c "CREATE SCHEMA IF NOT EXISTS $schema;" 2>/dev/null || true
    if [ "$schema" = "cdm" ]; then
        psql -d $LOCAL_DB -c "CREATE OR REPLACE FUNCTION cdm.uuid_generate_v4() RETURNS uuid AS 'SELECT public.uuid_generate_v4()' LANGUAGE SQL;" 2>/dev/null || true
    fi
done

# Copy tables
copy_tables_safe

echo -e "${GREEN}✅ Copy completed!${NC}"