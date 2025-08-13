#!/bin/bash

# Script to copy specific tables from production database
# Usage: ./copy-specific-tables.sh schema.table1 schema.table2 ...

# Configuration - matches other scripts
REMOTE_HOST="localhost"
REMOTE_PORT="9001"
REMOTE_DB="app"
REMOTE_USER="v-oidc-822-superuse-JyBspcEli8wemub6dT5U-1752813523"
REMOTE_PASS="ugWxGdv4GduU8Adnis-f"
LOCAL_DB="implentio_local"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check if table exists locally
table_exists_locally() {
    local schema_table=$1
    local schema=$(echo $schema_table | cut -d'.' -f1)
    local table=$(echo $schema_table | cut -d'.' -f2)
    
    local exists=$(psql -d $LOCAL_DB -t -c "
        SELECT COUNT(*) FROM information_schema.tables 
        WHERE table_schema = '$schema' AND table_name = '$table'
    " 2>/dev/null || echo "0")
    exists=$(echo $exists | tr -d ' ')
    [ "$exists" -gt "0" ]
}

# Function to get table row count
get_table_count() {
    local schema_table=$1
    local is_remote=$2
    
    if [ "$is_remote" = "true" ]; then
        local count=$(PGPASSWORD=$REMOTE_PASS psql -h $REMOTE_HOST -p $REMOTE_PORT -U $REMOTE_USER -d $REMOTE_DB -t -c "SELECT COUNT(*) FROM $schema_table" 2>/dev/null || echo "0")
    else
        local count=$(psql -d $LOCAL_DB -t -c "SELECT COUNT(*) FROM $schema_table" 2>/dev/null || echo "0")
    fi
    echo $count | tr -d ' '
}

# Function to copy a single table
copy_table() {
    local schema_table=$1
    local schema=$(echo $schema_table | cut -d'.' -f1)
    local table=$(echo $schema_table | cut -d'.' -f2)
    
    echo -e "${GREEN}Copying table: $schema_table${NC}"
    
    # Get remote count
    local remote_count=$(get_table_count "$schema_table" "true")
    if [ "$remote_count" = "0" ]; then
        echo -e "${YELLOW}⚠ Table $schema_table is empty or doesn't exist remotely${NC}"
        return
    fi
    
    # Create schema if needed
    psql -d $LOCAL_DB -c "CREATE SCHEMA IF NOT EXISTS $schema;" 2>/dev/null
    
    # Get local count
    local local_count=0
    if table_exists_locally "$schema_table"; then
        local_count=$(get_table_count "$schema_table" "false")
    fi
    
    echo -e "${YELLOW}Remote rows: $remote_count, Local rows: $local_count${NC}"
    
    if [ "$local_count" -eq "$remote_count" ]; then
        echo -e "${GREEN}✓ Table already up to date${NC}"
        return
    fi
    
    # Determine if table is large (>1M rows) and use appropriate method
    if [ "$remote_count" -gt 1000000 ]; then
        echo -e "${YELLOW}Large table detected. Using chunked copy...${NC}"
        copy_table_chunked "$schema" "$table"
    else
        echo -e "${YELLOW}Copying table with pg_dump...${NC}"
        copy_table_direct "$schema" "$table"
    fi
}

# Function to copy table directly with pg_dump
copy_table_direct() {
    local schema=$1
    local table=$2
    
    # Clear existing data
    psql -d $LOCAL_DB -c "DROP TABLE IF EXISTS $schema.$table CASCADE;" 2>/dev/null
    
    # Copy table structure and data
    if [ -f "/opt/homebrew/opt/postgresql@16/bin/pg_dump" ]; then
        PGPASSWORD=$REMOTE_PASS /opt/homebrew/opt/postgresql@16/bin/pg_dump \
            -h $REMOTE_HOST -p $REMOTE_PORT -U $REMOTE_USER -d $REMOTE_DB \
            -t $schema.$table --no-owner --no-acl | \
            sed -E 's/CREATE SCHEMA (cdm|client);/CREATE SCHEMA IF NOT EXISTS \1;/g' | \
            psql -d $LOCAL_DB -q
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Successfully copied $schema.$table${NC}"
        else
            echo -e "${RED}✗ Failed to copy $schema.$table${NC}"
        fi
    else
        echo -e "${RED}Error: PostgreSQL 16 required${NC}"
        exit 1
    fi
}

# Function to copy large table in chunks
copy_table_chunked() {
    local schema=$1
    local table=$2
    local chunk_size=50000
    
    echo -e "${YELLOW}Copying $schema.$table in chunks of $chunk_size rows...${NC}"
    
    # Get total rows
    local total_rows=$(PGPASSWORD=$REMOTE_PASS psql -h $REMOTE_HOST -p $REMOTE_PORT -U $REMOTE_USER -d $REMOTE_DB -t -c "SELECT COUNT(*) FROM $schema.$table")
    total_rows=$(echo $total_rows | tr -d ' ')
    
    # Create table structure
    psql -d $LOCAL_DB -c "DROP TABLE IF EXISTS $schema.$table CASCADE;" 2>/dev/null
    PGPASSWORD=$REMOTE_PASS /opt/homebrew/opt/postgresql@16/bin/pg_dump \
        -h $REMOTE_HOST -p $REMOTE_PORT -U $REMOTE_USER -d $REMOTE_DB \
        --schema-only -t $schema.$table | \
        sed -E 's/CREATE SCHEMA (cdm|client);/CREATE SCHEMA IF NOT EXISTS \1;/g' | \
        psql -d $LOCAL_DB -q 2>/dev/null
    
    # Copy data in chunks
    local offset=0
    local chunk_num=1
    local total_chunks=$(((total_rows + chunk_size - 1) / chunk_size))
    
    while [ $offset -lt $total_rows ]; do
        echo -e "${YELLOW}Copying chunk $chunk_num/$total_chunks (rows $offset to $((offset + chunk_size)))...${NC}"
        
        PGPASSWORD=$REMOTE_PASS psql -h $REMOTE_HOST -p $REMOTE_PORT -U $REMOTE_USER -d $REMOTE_DB -c "
            COPY (SELECT * FROM $schema.$table ORDER BY id LIMIT $chunk_size OFFSET $offset) 
            TO STDOUT WITH (FORMAT CSV)" | \
        psql -d $LOCAL_DB -c "COPY $schema.$table FROM STDIN WITH (FORMAT CSV)"
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Chunk $chunk_num completed${NC}"
        else
            echo -e "${RED}✗ Chunk $chunk_num failed${NC}"
        fi
        
        offset=$((offset + chunk_size))
        chunk_num=$((chunk_num + 1))
    done
}

# Function to list available tables
list_tables() {
    echo -e "${GREEN}Available tables in production:${NC}"
    echo -e "${YELLOW}CDM Schema:${NC}"
    PGPASSWORD=$REMOTE_PASS psql -h $REMOTE_HOST -p $REMOTE_PORT -U $REMOTE_USER -d $REMOTE_DB -t -c "
        SELECT 'cdm.' || table_name || ' (' || (
            SELECT COUNT(*) FROM information_schema.tables t2 
            WHERE t2.table_schema = 'cdm' AND t2.table_name = t.table_name
        ) || ' rows)'
        FROM information_schema.tables t
        WHERE table_schema = 'cdm' AND table_type = 'BASE TABLE'
        ORDER BY table_name
    " | head -20
    
    echo -e "${YELLOW}Client Schema:${NC}"
    PGPASSWORD=$REMOTE_PASS psql -h $REMOTE_HOST -p $REMOTE_PORT -U $REMOTE_USER -d $REMOTE_DB -t -c "
        SELECT 'client.' || table_name
        FROM information_schema.tables 
        WHERE table_schema = 'client' AND table_type = 'BASE TABLE'
        ORDER BY table_name
    " | head -20
}

# Function to check local table status
check_local_status() {
    echo -e "${GREEN}Local table status:${NC}"
    echo -e "${YELLOW}Schema | Table | Rows${NC}"
    echo "--------------------------------"
    
    for schema in cdm client; do
        psql -d $LOCAL_DB -t -c "
            SELECT '$schema' || ' | ' || table_name || ' | ' || COALESCE((
                SELECT COUNT(*) FROM information_schema.tables t2 
                WHERE t2.table_schema = '$schema' AND t2.table_name = t.table_name
            ), 0)
            FROM information_schema.tables t
            WHERE table_schema = '$schema' AND table_type = 'BASE TABLE'
            ORDER BY table_name
        " 2>/dev/null | grep -v "^$"
    done
}

# Main execution
case "$1" in
    list)
        list_tables
        ;;
    status)
        check_local_status
        ;;
    copy)
        if [ $# -lt 2 ]; then
            echo "Usage: $0 copy schema.table1 [schema.table2 ...]"
            echo "Example: $0 copy cdm.orders client.customers"
            exit 1
        fi
        
        shift # Remove 'copy' argument
        
        # Test connection first
        echo -e "${YELLOW}Testing connection...${NC}"
        PGPASSWORD=$REMOTE_PASS psql -h $REMOTE_HOST -p $REMOTE_PORT -U $REMOTE_USER -d $REMOTE_DB -c "SELECT 1" > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo -e "${RED}Failed to connect to production database${NC}"
            exit 1
        fi
        
        # Create UUID function if needed
        psql -d $LOCAL_DB -c "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";" 2>/dev/null
        psql -d $LOCAL_DB -c "CREATE OR REPLACE FUNCTION cdm.uuid_generate_v4() RETURNS uuid AS 'SELECT public.uuid_generate_v4()' LANGUAGE SQL;" 2>/dev/null
        
        # Copy each specified table
        for table in "$@"; do
            copy_table "$table"
            echo ""
        done
        
        echo -e "${GREEN}✅ Copy operation completed${NC}"
        ;;
    *)
        echo "Usage: $0 {list|status|copy}"
        echo ""
        echo "Commands:"
        echo "  list                    - List available tables in production"
        echo "  status                  - Show local table status"
        echo "  copy schema.table1 ... - Copy specific tables"
        echo ""
        echo "Examples:"
        echo "  $0 list"
        echo "  $0 status"
        echo "  $0 copy cdm.orders cdm.customers"
        echo "  $0 copy client.invoices"
        ;;
esac
