#!/bin/bash

# Script to copy large tables from production database in chunks
# This handles tables that are too large for a single pg_dump operation

# Configuration - matches copy-from-prod.sh
REMOTE_HOST="localhost"
REMOTE_PORT="9001"
REMOTE_DB="app"
REMOTE_USER="v-oidc-822-reader-i-WUuYUAEuYikxyZsvNrQX-1750482124"
REMOTE_PASS="B9N1n9yMqN-8iyOxOgLp"
LOCAL_DB="implentio_local"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Chunk size (number of rows per batch)
# Reduced from 100000 to avoid SSL timeouts
CHUNK_SIZE=50000

# Function to copy a large table in chunks
copy_large_table() {
    local schema=$1
    local table=$2
    local order_column=${3:-"id"}  # Default to 'id' if not specified
    
    echo -e "${GREEN}Copying large table: $schema.$table${NC}"
    
    # Get total row count
    local total_rows=$(PGPASSWORD=$REMOTE_PASS psql -h $REMOTE_HOST -p $REMOTE_PORT -U $REMOTE_USER -d $REMOTE_DB -t -c "SELECT COUNT(*) FROM $schema.$table")
    total_rows=$(echo $total_rows | tr -d ' ')
    echo -e "${YELLOW}Total rows: $total_rows${NC}"
    
    # Create table structure if it doesn't exist
    echo -e "${YELLOW}Creating table structure...${NC}"
    if [ -f "/opt/homebrew/opt/postgresql@16/bin/pg_dump" ]; then
        PGPASSWORD=$REMOTE_PASS /opt/homebrew/opt/postgresql@16/bin/pg_dump -h $REMOTE_HOST -p $REMOTE_PORT -U $REMOTE_USER -d $REMOTE_DB \
            --schema-only -t $schema.$table | psql -d $LOCAL_DB 2>/dev/null || true
    else
        echo -e "${RED}Error: PostgreSQL 16 client tools are required for this server version${NC}"
        echo -e "${YELLOW}Please install with: brew install postgresql@16${NC}"
        exit 1
    fi
    
    # Clear existing data
    echo -e "${YELLOW}Clearing existing data...${NC}"
    psql -d $LOCAL_DB -c "TRUNCATE TABLE $schema.$table CASCADE" 2>/dev/null || true
    
    # Copy data in chunks
    local offset=0
    local chunk_num=1
    local total_chunks=$((($total_rows + $CHUNK_SIZE - 1) / $CHUNK_SIZE))
    
    # Set connection parameters for all copy operations
    export PGCONNECT_TIMEOUT=120
    export PGOPTIONS='-c tcp_keepalives_idle=30 -c tcp_keepalives_interval=10 -c tcp_keepalives_count=6'
    
    while [ $offset -lt $total_rows ]; do
        echo -e "${YELLOW}Copying chunk $chunk_num/$total_chunks (rows $offset to $(($offset + $CHUNK_SIZE)))...${NC}"
        
        # Use COPY with LIMIT and OFFSET
        PGPASSWORD=$REMOTE_PASS psql -h $REMOTE_HOST -p $REMOTE_PORT -U $REMOTE_USER -d $REMOTE_DB -c "\
            COPY (SELECT * FROM $schema.$table ORDER BY $order_column LIMIT $CHUNK_SIZE OFFSET $offset) \
            TO STDOUT WITH (FORMAT BINARY)" | \
        psql -d $LOCAL_DB -c "\
            COPY $schema.$table FROM STDIN WITH (FORMAT BINARY)"
        
        if [ $? -ne 0 ]; then
            echo -e "${RED}Error copying chunk $chunk_num. Retrying with smaller chunk...${NC}"
            # Retry with progressively smaller chunks
            local retry_sizes=(25000 10000 5000)
            local success=0
            
            for retry_chunk in ${retry_sizes[@]}; do
                echo -e "${YELLOW}Retrying with chunk size: $retry_chunk rows${NC}"
                sleep 2  # Brief pause before retry
                
                # Set connection timeout and keepalive options
                export PGCONNECT_TIMEOUT=120
                export PGOPTIONS='-c tcp_keepalives_idle=30 -c tcp_keepalives_interval=10 -c tcp_keepalives_count=6'
                
                PGPASSWORD=$REMOTE_PASS psql -h $REMOTE_HOST -p $REMOTE_PORT -U $REMOTE_USER -d $REMOTE_DB -c "\
                    COPY (SELECT * FROM $schema.$table ORDER BY $order_column LIMIT $retry_chunk OFFSET $offset) \
                    TO STDOUT WITH (FORMAT BINARY)" | \
                psql -d $LOCAL_DB -c "\
                    COPY $schema.$table FROM STDIN WITH (FORMAT BINARY)"
                
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}Successfully copied with chunk size $retry_chunk${NC}"
                    offset=$(($offset + $retry_chunk))
                    success=1
                    break
                fi
            done
            
            if [ $success -eq 0 ]; then
                echo -e "${RED}Failed to copy chunk after all retries. Stopping.${NC}"
                return 1
            fi
        else
            offset=$(($offset + $CHUNK_SIZE))
        fi
        
        chunk_num=$(($chunk_num + 1))
        
        # Small delay to avoid overloading
        sleep 0.5
    done
    
    # Verify row count
    local copied_rows=$(psql -d $LOCAL_DB -t -c "SELECT COUNT(*) FROM $schema.$table")
    copied_rows=$(echo $copied_rows | tr -d ' ')
    echo -e "${GREEN}✅ Copied $copied_rows rows to $schema.$table${NC}"
    
    if [ "$copied_rows" != "$total_rows" ]; then
        echo -e "${RED}Warning: Row count mismatch! Expected $total_rows, got $copied_rows${NC}"
    fi
}

# Function to copy all large CDM tables
copy_large_cdm_tables() {
    # Test connection first
    echo -e "${YELLOW}Testing connection to production database...${NC}"
    PGPASSWORD=$REMOTE_PASS psql -h $REMOTE_HOST -p $REMOTE_PORT -U $REMOTE_USER -d $REMOTE_DB -c "SELECT 1" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to connect to production database. The credentials may have expired.${NC}"
        echo -e "${YELLOW}Please update REMOTE_USER and REMOTE_PASS in this script with fresh credentials.${NC}"
        exit 1
    fi
    
    # Create local database if it doesn't exist
    echo -e "${GREEN}Creating local database '$LOCAL_DB' if needed...${NC}"
    createdb $LOCAL_DB 2>/dev/null || echo "Database already exists, continuing..."
    
    # Create necessary extensions and schema
    echo -e "${GREEN}Creating required extensions and schema...${NC}"
    psql -d $LOCAL_DB -c "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";"
    psql -d $LOCAL_DB -c "CREATE SCHEMA IF NOT EXISTS cdm;"
    psql -d $LOCAL_DB -c "CREATE OR REPLACE FUNCTION cdm.uuid_generate_v4() RETURNS uuid AS 'SELECT public.uuid_generate_v4()' LANGUAGE SQL;"
    
    # Copy large tables
    copy_large_table "cdm" "fulfillment" "id"
    copy_large_table "cdm" "fulfillment_package" "id"
    copy_large_table "cdm" "fulfillment_package_line_item" "id"
}

# Main menu
case "$1" in
    copy)
        copy_large_cdm_tables
        ;;
    *)
        echo "Usage: $0 copy"
        echo ""
        echo "This script copies large tables that timeout with regular pg_dump"
        echo "Currently configured tables:"
        echo "  - cdm.fulfillment (8.4M rows)"
        echo "  - cdm.fulfillment_package"
        echo "  - cdm.fulfillment_package_line_item"
        echo ""
        echo "Configuration:"
        echo "  Chunk size: $CHUNK_SIZE rows"
        echo "  Database: $REMOTE_USER@$REMOTE_HOST:$REMOTE_PORT/$REMOTE_DB"
        ;;
esac
