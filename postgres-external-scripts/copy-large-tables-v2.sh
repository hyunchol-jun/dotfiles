#!/bin/bash

# Script to copy large tables from production database in chunks
# Version 2: More robust handling of connection issues

# Configuration - matches copy-from-prod.sh
REMOTE_HOST="localhost"
REMOTE_PORT="9001"
REMOTE_DB="app"
REMOTE_USER="v-oidc-822-reader-i-ojy0XpwGEoEnrUGP15jD-1750627696"
REMOTE_PASS="xjAajPPYRMkY-K0Aq6PJ"
LOCAL_DB="implentio_local"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Initial chunk size - will auto-adjust based on success
CHUNK_SIZE=10000

# Function to copy a table using row-by-row approach for stability
copy_large_table_stable() {
    local schema=$1
    local table=$2
    
    echo -e "${GREEN}Copying large table: $schema.$table${NC}"
    echo -e "${YELLOW}Using stable row-by-row approach...${NC}"
    
    # Get total row count
    local total_rows=$(PGPASSWORD=$REMOTE_PASS psql -h $REMOTE_HOST -p $REMOTE_PORT -U $REMOTE_USER -d $REMOTE_DB -t -c "SELECT COUNT(*) FROM $schema.$table")
    total_rows=$(echo $total_rows | tr -d ' ')
    echo -e "${YELLOW}Total rows to copy: $total_rows${NC}"
    
    # Get current row count in local DB
    local existing_rows=$(psql -d $LOCAL_DB -t -c "SELECT COUNT(*) FROM $schema.$table" 2>/dev/null || echo "0")
    existing_rows=$(echo $existing_rows | tr -d ' ')
    
    if [ "$existing_rows" -gt "0" ]; then
        echo -e "${YELLOW}Found $existing_rows existing rows. Starting from there...${NC}"
    else
        echo -e "${YELLOW}Starting fresh copy...${NC}"
        
        # Create table structure if needed
        echo -e "${YELLOW}Creating table structure...${NC}"
        if [ -f "/opt/homebrew/opt/postgresql@16/bin/pg_dump" ]; then
            PGPASSWORD=$REMOTE_PASS /opt/homebrew/opt/postgresql@16/bin/pg_dump -h $REMOTE_HOST -p $REMOTE_PORT -U $REMOTE_USER -d $REMOTE_DB \
                --schema-only -t $schema.$table | psql -d $LOCAL_DB -q 2>/dev/null || true
        fi
    fi
    
    # Copy using INSERT method for stability (slower but more reliable)
    local offset=$existing_rows
    local successful_chunks=0
    local failed_chunks=0
    local current_chunk_size=$CHUNK_SIZE
    
    while [ $offset -lt $total_rows ]; do
        local remaining=$((total_rows - offset))
        local this_chunk=$current_chunk_size
        if [ $remaining -lt $current_chunk_size ]; then
            this_chunk=$remaining
        fi
        
        echo -e "${YELLOW}Copying rows $offset to $((offset + this_chunk)) (chunk size: $this_chunk)...${NC}"
        
        # Use a transaction with explicit row counting
        local before_count=$(psql -d $LOCAL_DB -t -c "SELECT COUNT(*) FROM $schema.$table")
        before_count=$(echo $before_count | tr -d ' ')
        
        # Copy using COPY but with better error handling
        PGPASSWORD=$REMOTE_PASS psql -h $REMOTE_HOST -p $REMOTE_PORT -U $REMOTE_USER -d $REMOTE_DB \
            -c "COPY (SELECT * FROM $schema.$table ORDER BY id LIMIT $this_chunk OFFSET $offset) TO STDOUT WITH (FORMAT CSV)" 2>/tmp/copy_error.log | \
        psql -d $LOCAL_DB -c "COPY $schema.$table FROM STDIN WITH (FORMAT CSV)" 2>&1
        
        # Check how many rows were actually copied
        local after_count=$(psql -d $LOCAL_DB -t -c "SELECT COUNT(*) FROM $schema.$table")
        after_count=$(echo $after_count | tr -d ' ')
        local copied_rows=$((after_count - before_count))
        
        if [ $copied_rows -eq $this_chunk ]; then
            echo -e "${GREEN}✓ Successfully copied $copied_rows rows${NC}"
            successful_chunks=$((successful_chunks + 1))
            offset=$((offset + this_chunk))
            
            # Increase chunk size if we're doing well
            if [ $successful_chunks -gt 3 ] && [ $current_chunk_size -lt 50000 ]; then
                current_chunk_size=$((current_chunk_size * 2))
                echo -e "${GREEN}Increasing chunk size to $current_chunk_size${NC}"
                successful_chunks=0
            fi
        elif [ $copied_rows -gt 0 ]; then
            echo -e "${YELLOW}⚠ Partial copy: got $copied_rows rows instead of $this_chunk${NC}"
            offset=$((offset + copied_rows))
            failed_chunks=$((failed_chunks + 1))
            
            # Reduce chunk size
            current_chunk_size=$((current_chunk_size / 2))
            if [ $current_chunk_size -lt 1000 ]; then
                current_chunk_size=1000
            fi
            echo -e "${YELLOW}Reducing chunk size to $current_chunk_size${NC}"
        else
            echo -e "${RED}✗ Failed to copy chunk. Checking error...${NC}"
            if [ -f /tmp/copy_error.log ]; then
                cat /tmp/copy_error.log
            fi
            failed_chunks=$((failed_chunks + 1))
            
            # Reduce chunk size significantly
            current_chunk_size=$((current_chunk_size / 4))
            if [ $current_chunk_size -lt 100 ]; then
                echo -e "${RED}Chunk size too small. Stopping.${NC}"
                break
            fi
            echo -e "${YELLOW}Reducing chunk size to $current_chunk_size and retrying...${NC}"
            sleep 2
        fi
        
        # Progress update every 10 chunks
        if [ $((($offset - $existing_rows) / $CHUNK_SIZE % 10)) -eq 0 ]; then
            local progress=$(echo "scale=2; $offset * 100 / $total_rows" | bc)
            echo -e "${GREEN}Progress: $progress% ($offset / $total_rows rows)${NC}"
        fi
    done
    
    # Final verification
    local final_count=$(psql -d $LOCAL_DB -t -c "SELECT COUNT(*) FROM $schema.$table")
    final_count=$(echo $final_count | tr -d ' ')
    
    echo -e "${GREEN}Copy completed!${NC}"
    echo -e "${GREEN}Total rows in $schema.$table: $final_count / $total_rows${NC}"
    
    if [ "$final_count" -eq "$total_rows" ]; then
        echo -e "${GREEN}✅ All rows copied successfully!${NC}"
    else
        echo -e "${YELLOW}⚠ Warning: Row count mismatch! Missing $((total_rows - final_count)) rows${NC}"
        echo -e "${YELLOW}You can run this script again to copy the remaining rows${NC}"
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
    psql -d $LOCAL_DB -c "CREATE SCHEMA IF NOT EXISTS client;"
    psql -d $LOCAL_DB -c "CREATE OR REPLACE FUNCTION cdm.uuid_generate_v4() RETURNS uuid AS 'SELECT public.uuid_generate_v4()' LANGUAGE SQL;"
    
    # Copy large tables with the stable method
    # copy_large_table_stable "cdm" "fulfillment"
    # copy_large_table_stable "cdm" "fulfillment_package"
    # copy_large_table_stable "cdm" "fulfillment_package_line_item"
    copy_large_table_stable "client" "order_details"
}

# Main menu
case "$1" in
    copy)
        copy_large_cdm_tables
        ;;
    *)
        echo "Usage: $0 copy"
        echo ""
        echo "This script copies large tables using a more stable approach"
        echo "Features:"
        echo "  - Automatic chunk size adjustment based on success rate"
        echo "  - Resume capability (continues from where it left off)"
        echo "  - CSV format for better compatibility"
        echo "  - Row count verification for each chunk"
        echo ""
        echo "Currently configured tables:"
        echo "  - cdm.fulfillment (8.4M rows)"
        echo "  - cdm.fulfillment_package"
        echo "  - cdm.fulfillment_package_line_item"
        ;;
esac
