#!/bin/bash

# Script to safely copy specific schemas from production database
# This is a READ-ONLY operation that won't modify your production data

# Configuration - EDIT THESE VALUES
REMOTE_HOST="localhost"
REMOTE_PORT="9001"
REMOTE_DB="app"
REMOTE_USER="v-oidc-822-reader-i-ojy0XpwGEoEnrUGP15jD-1750627696"
REMOTE_PASS="xjAajPPYRMkY-K0Aq6PJ"
LOCAL_DB="implentio_local"

# Schemas to copy (space-separated list)
# Note: reconciliation schema removed due to permission issues
SCHEMAS_TO_COPY="client"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Production Database Copy Tool${NC}"
echo -e "${YELLOW}This tool performs READ-ONLY operations on your production database${NC}"
echo ""

# Check if PostgreSQL is running locally
if ! brew services list | grep -q "postgresql@14.*started"; then
    echo -e "${RED}Error: Local PostgreSQL is not running${NC}"
    echo "Please start it with: ~/postgres-external-scripts/pg-toggle.sh start"
    exit 1
fi

# Function to list available schemas
list_schemas() {
    echo -e "${GREEN}Fetching available schemas from production...${NC}"
    PGPASSWORD=$REMOTE_PASS psql -h $REMOTE_HOST -p $REMOTE_PORT -U $REMOTE_USER -d $REMOTE_DB -t -c "
        SELECT schema_name 
        FROM information_schema.schemata 
        WHERE schema_name NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
        ORDER BY schema_name;"
}

# Function to copy specific schemas
copy_schemas() {
    # Check if we should start fresh
    if [ "$2" = "--fresh" ]; then
        echo -e "${YELLOW}Starting fresh copy (dropping existing database)...${NC}"
        dropdb $LOCAL_DB 2>/dev/null || true
    fi
    
    # Create local database if it doesn't exist
    echo -e "${GREEN}Creating local database '$LOCAL_DB'...${NC}"
    createdb $LOCAL_DB 2>/dev/null || echo "Database already exists, continuing..."
    
    # Create necessary extensions
    echo -e "${GREEN}Creating required extensions...${NC}"
    psql -d $LOCAL_DB -c "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";"
    
    # Build pg_dump command with multiple schemas
    DUMP_CMD="pg_dump -h $REMOTE_HOST -p $REMOTE_PORT -U $REMOTE_USER -d $REMOTE_DB"
    
    # Add each schema to the dump command
    for schema in $SCHEMAS_TO_COPY; do
        DUMP_CMD="$DUMP_CMD -n $schema"
    done
    
    # Add options for safe copying
    DUMP_CMD="$DUMP_CMD --no-owner --no-acl --no-tablespaces --no-security-labels --no-subscriptions --no-publications"
    
    # Get list of materialized views to exclude
    echo -e "${YELLOW}Identifying materialized views to exclude...${NC}"
    MATVIEWS=$(PGPASSWORD=$REMOTE_PASS psql -h $REMOTE_HOST -p $REMOTE_PORT -U $REMOTE_USER -d $REMOTE_DB -t -c "
        SELECT string_agg(schemaname || '.' || matviewname, ' ')
        FROM pg_matviews 
        WHERE schemaname IN ('cdm', 'client')")
    
    # Exclude each materialized view
    if [ ! -z "$MATVIEWS" ]; then
        for mv in $MATVIEWS; do
            DUMP_CMD="$DUMP_CMD --exclude-table=$mv"
        done
        echo -e "${YELLOW}Excluding $(echo $MATVIEWS | wc -w) materialized views${NC}"
    fi
    
    # Note: Large tables should be copied separately using copy-large-tables.sh
    # Exclude large tables that cause SSL timeouts
    DUMP_CMD="$DUMP_CMD --exclude-table=cdm.fulfillment --exclude-table=cdm.fulfillment_package --exclude-table=cdm.fulfillment_package_line_item"
    DUMP_CMD="$DUMP_CMD --exclude-table=client.order_details"
    
    echo -e "${GREEN}Starting data copy...${NC}"
    echo -e "${YELLOW}Copying schemas: $SCHEMAS_TO_COPY${NC}"
    echo ""
    
    # Execute the dump and restore
    # Use pg_dump from PostgreSQL 16 if available, otherwise fallback to default
    if [ -f "/opt/homebrew/opt/postgresql@16/bin/pg_dump" ]; then
        # Test connection first
        echo -e "${YELLOW}Testing connection to production database...${NC}"
        PGPASSWORD=$REMOTE_PASS psql -h $REMOTE_HOST -p $REMOTE_PORT -U $REMOTE_USER -d $REMOTE_DB -c "SELECT 1" > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo -e "${RED}Failed to connect to production database. The credentials may have expired.${NC}"
            echo -e "${YELLOW}Please update REMOTE_USER and REMOTE_PASS in this script with fresh credentials.${NC}"
            exit 1
        fi
        
        # Perform the dump with connection timeout settings
        # First create UUID function wrapper if cdm schema is included
        if [[ " $SCHEMAS_TO_COPY " =~ " cdm " ]]; then
            echo -e "${YELLOW}Pre-creating cdm schema and UUID function...${NC}"
            psql -d $LOCAL_DB -c "CREATE SCHEMA IF NOT EXISTS cdm;"
            psql -d $LOCAL_DB -c "CREATE OR REPLACE FUNCTION cdm.uuid_generate_v4() RETURNS uuid AS 'SELECT public.uuid_generate_v4()' LANGUAGE SQL;"
        fi
        
        # Now dump everything (schema + data) in one go
        echo -e "${YELLOW}Copying schemas and data...${NC}"
        # Use compression and increase timeouts for large tables
        export PGPASSWORD=$REMOTE_PASS
        export PGCONNECT_TIMEOUT=60
        export PGSSLMODE=require
        /opt/homebrew/opt/postgresql@16/bin/pg_dump ${DUMP_CMD#pg_dump} --compress=0 | \
            sed -E 's/CREATE SCHEMA (cdm|client);/CREATE SCHEMA IF NOT EXISTS \1;/g' | \
            psql -d $LOCAL_DB -v statement_timeout=0
    else
        echo -e "${RED}Error: PostgreSQL 16 client tools are required for this server version${NC}"
        echo -e "${YELLOW}Please install with: brew install postgresql@16${NC}"
        exit 1
    fi
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Data copy completed successfully!${NC}"
    else
        echo -e "${RED}❌ Error during data copy${NC}"
        exit 1
    fi
}

# Function to verify the copy
verify_copy() {
    echo -e "${GREEN}Verifying copied data...${NC}"
    
    for schema in $SCHEMAS_TO_COPY; do
        echo -e "${YELLOW}Schema: $schema${NC}"
        psql -d $LOCAL_DB -c "
            SELECT 
                '$schema' as schema,
                COUNT(*) as table_count 
            FROM information_schema.tables 
            WHERE table_schema = '$schema';"
    done
    
    # Show database size
    echo -e "${GREEN}Local database size:${NC}"
    psql -d $LOCAL_DB -c "
        SELECT pg_database.datname,
               pg_size_pretty(pg_database_size(pg_database.datname)) AS size
        FROM pg_database
        WHERE datname = '$LOCAL_DB';"
}

# Main menu
case "$1" in
    list)
        # Use hardcoded password instead of prompting
        list_schemas
        ;;
    copy)
        # Use hardcoded password instead of prompting
        copy_schemas "$@"
        verify_copy
        ;;
    verify)
        verify_copy
        ;;
    *)
        echo "Usage: $0 {list|copy|verify}"
        echo ""
        echo "Commands:"
        echo "  list         - List available schemas in production database"
        echo "  copy         - Copy configured schemas to local database (resume if exists)"
        echo "  copy --fresh - Drop existing database and start fresh copy"
        echo "  verify       - Verify the local copy"
        echo ""
        echo "Configuration:"
        echo "  Edit this script to set your connection details and schemas to copy"
        echo "  Current settings:"
        echo "    Remote: $REMOTE_USER@$REMOTE_HOST:$REMOTE_PORT/$REMOTE_DB"
        echo "    Local:  $LOCAL_DB"
        echo "    Schemas: $SCHEMAS_TO_COPY"
        ;;
esac
