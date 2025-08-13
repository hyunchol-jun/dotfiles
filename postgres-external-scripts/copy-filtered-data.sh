#!/bin/bash

# Script to copy filtered data from specific tables
# Usage: ./copy-filtered-data.sh --where "brand_id = 123" schema.table1 schema.table2 ...

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
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
WHERE_CLAUSE=""
TRUNCATE_FIRST="false"
DRY_RUN="false"
TABLES=()

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS] schema.table1 [schema.table2 ...]"
    echo ""
    echo "OPTIONS:"
    echo "  --where \"CONDITION\"     WHERE clause for filtering data"
    echo "  --truncate              Truncate target tables before copying"
    echo "  --dry-run               Show what would be copied without executing"
    echo "  --help                  Show this help message"
    echo ""
    echo "EXAMPLES:"
    echo "  # Copy specific brand data"
    echo "  $0 --where \"brand_id = 123\" cdm.products cdm.orders"
    echo ""
    echo "  # Copy data with complex conditions"
    echo "  $0 --where \"brand_id IN (123, 456) AND created_at > '2024-01-01'\" cdm.products"
    echo ""
    echo "  # Dry run to see what would be copied"
    echo "  $0 --dry-run --where \"brand_id = 123\" cdm.products"
    echo ""
    echo "  # Truncate tables first, then copy filtered data"
    echo "  $0 --truncate --where \"brand_id = 123\" cdm.products cdm.orders"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --where)
            WHERE_CLAUSE="$2"
            shift 2
            ;;
        --truncate)
            TRUNCATE_FIRST="true"
            shift
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --help)
            show_usage
            exit 0
            ;;
        --*)
            echo -e "${RED}Unknown option: $1${NC}"
            show_usage
            exit 1
            ;;
        *)
            TABLES+=("$1")
            shift
            ;;
    esac
done

# Validate arguments
if [ ${#TABLES[@]} -eq 0 ]; then
    echo -e "${RED}Error: No tables specified${NC}"
    show_usage
    exit 1
fi

if [ -z "$WHERE_CLAUSE" ]; then
    echo -e "${RED}Error: WHERE clause is required${NC}"
    echo -e "${YELLOW}Use --where \"condition\" to specify filter criteria${NC}"
    show_usage
    exit 1
fi

echo -e "${BLUE}=== PostgreSQL Filtered Data Copy ===${NC}"
echo -e "${YELLOW}Filter: WHERE $WHERE_CLAUSE${NC}"
echo -e "${YELLOW}Tables: ${TABLES[*]}${NC}"
echo -e "${YELLOW}Truncate first: $TRUNCATE_FIRST${NC}"
echo -e "${YELLOW}Dry run: $DRY_RUN${NC}"
echo ""

# Test connections
echo -e "${YELLOW}Testing connections...${NC}"
PGPASSWORD=$REMOTE_PASS psql -h $REMOTE_HOST -p $REMOTE_PORT -U $REMOTE_USER -d $REMOTE_DB -c "SELECT 1" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to connect to remote database${NC}"
    exit 1
fi

psql -d $LOCAL_DB -c "SELECT 1" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to connect to local database${NC}"
    exit 1
fi

# Create required extensions
psql -d $LOCAL_DB -c "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";" 2>/dev/null
psql -d $LOCAL_DB -c "CREATE EXTENSION IF NOT EXISTS \"pgcrypto\";" 2>/dev/null

echo -e "${GREEN}✓ Connections successful${NC}"
echo ""

# Function to get filtered row count
get_filtered_count() {
    local schema_table=$1
    local where_clause=$2
    
    local count=$(PGPASSWORD=$REMOTE_PASS psql -h $REMOTE_HOST -p $REMOTE_PORT -U $REMOTE_USER -d $REMOTE_DB -t -c "
        SELECT COUNT(*) FROM $schema_table WHERE $where_clause
    " 2>/dev/null || echo "ERROR")
    
    if [ "$count" = "ERROR" ]; then
        echo "ERROR"
    else
        echo $count | tr -d ' '
    fi
}

# Function to get table columns
get_table_columns() {
    local schema_table=$1
    local schema=$(echo $schema_table | cut -d'.' -f1)
    local table=$(echo $schema_table | cut -d'.' -f2)
    
    PGPASSWORD=$REMOTE_PASS psql -h $REMOTE_HOST -p $REMOTE_PORT -U $REMOTE_USER -d $REMOTE_DB -t -c "
        SELECT column_name 
        FROM information_schema.columns 
        WHERE table_schema = '$schema' AND table_name = '$table'
        ORDER BY ordinal_position
    " | tr '\n' ',' | sed 's/,$//' | tr -d ' '
}

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

# Function to create table structure from remote
create_table_structure() {
    local schema_table=$1
    local schema=$(echo $schema_table | cut -d'.' -f1)
    local table=$(echo $schema_table | cut -d'.' -f2)
    
    echo -e "  ${YELLOW}Creating table structure for $schema_table...${NC}"
    
    # Create schema if it doesn't exist
    psql -d $LOCAL_DB -c "CREATE SCHEMA IF NOT EXISTS $schema;" > /dev/null 2>&1
    
    # Create the fulfillment_package_type enum if it doesn't exist
    echo -e "  ${YELLOW}Creating required enum types...${NC}"
    psql -d $LOCAL_DB -c "
        DO \$\$ 
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'fulfillment_package_type' AND typnamespace = (SELECT oid FROM pg_namespace WHERE nspname = '$schema')) THEN
                CREATE TYPE $schema.fulfillment_package_type AS ENUM ('PARCEL', 'PALLET');
            END IF;
        END
        \$\$;
    " > /dev/null 2>&1
    
    # Check for PostgreSQL 16 pg_dump
    local PG_DUMP=""
    if [ -f "/opt/homebrew/opt/postgresql@16/bin/pg_dump" ]; then
        PG_DUMP="/opt/homebrew/opt/postgresql@16/bin/pg_dump"
    elif [ -f "/usr/local/opt/postgresql@16/bin/pg_dump" ]; then
        PG_DUMP="/usr/local/opt/postgresql@16/bin/pg_dump"
    else
        echo -e "  ${RED}Error: PostgreSQL 16 pg_dump not found${NC}"
        return 1
    fi
    
    # Create temporary file for the dump
    local temp_file=$(mktemp)
    local temp_log=$(mktemp)
    
    # Dump table structure only
    echo -e "  ${YELLOW}Dumping table structure from remote...${NC}"
    PGPASSWORD=$REMOTE_PASS $PG_DUMP \
        -h $REMOTE_HOST \
        -p $REMOTE_PORT \
        -U $REMOTE_USER \
        -d $REMOTE_DB \
        -t $schema_table \
        --schema-only \
        --no-owner \
        --no-privileges \
        --no-tablespaces \
        -f "$temp_file" 2>"$temp_log"
    
    if [ $? -ne 0 ]; then
        echo -e "  ${RED}✗ Failed to dump table structure${NC}"
        echo -e "  ${YELLOW}Error output:${NC}"
        cat "$temp_log"
        rm -f "$temp_file" "$temp_log"
        return 1
    fi
    
    # Check if dump file has content
    if [ ! -s "$temp_file" ]; then
        echo -e "  ${RED}✗ Dump file is empty${NC}"
        rm -f "$temp_file" "$temp_log"
        return 1
    fi
    
    echo -e "  ${YELLOW}Processing and applying SQL...${NC}"
    
    # Clean and apply the dump, but be more aggressive about filtering problematic statements
    # Remove foreign key constraints to avoid dependency issues
    local processed_sql=$(mktemp)
    sed -E \
        -e "s/CREATE SCHEMA $schema;/CREATE SCHEMA IF NOT EXISTS $schema;/g" \
        -e 's/cdm\.uuid_generate_v4\(\)/public.uuid_generate_v4()/g' \
        -e '/^SET /d' \
        -e '/^SELECT pg_catalog\.set_config/d' \
        -e '/^--/d' \
        -e '/^ALTER TABLE.*OWNER TO/d' \
        -e '/^REVOKE/d' \
        -e '/^GRANT/d' \
        -e '/ADD CONSTRAINT.*FOREIGN KEY/d' \
        "$temp_file" > "$processed_sql"
    
    # Show any CREATE TYPE statements
    echo -e "  ${YELLOW}CREATE TYPE statements:${NC}"
    grep -A 5 "CREATE TYPE" "$processed_sql" || echo "None found"
    echo -e "  ${YELLOW}---${NC}"
    
    # Show the CREATE TABLE statement for debugging
    echo -e "  ${YELLOW}CREATE TABLE statement:${NC}"
    grep -A 20 "CREATE TABLE" "$processed_sql" | head -15
    echo -e "  ${YELLOW}---${NC}"
    
    # Execute with verbose error reporting
    psql -d $LOCAL_DB -v ON_ERROR_STOP=1 -f "$processed_sql" > "$temp_log" 2>&1
    
    local result=$?
    
    if [ $result -ne 0 ]; then
        echo -e "  ${RED}✗ SQL execution failed${NC}"
        echo -e "  ${YELLOW}Full error output:${NC}"
        cat "$temp_log"
        echo -e "  ${YELLOW}Full processed SQL:${NC}"
        cat "$processed_sql"
        rm -f "$temp_file" "$temp_log" "$processed_sql"
        return 1
    fi
    
    echo -e "  ${YELLOW}SQL execution output:${NC}"
    cat "$temp_log"
    
    rm -f "$temp_file" "$temp_log" "$processed_sql"
    
    # Verify table was created
    if table_exists_locally "$schema_table"; then
        echo -e "  ${GREEN}✓ Table structure created${NC}"
        return 0
    else
        echo -e "  ${RED}✗ Table not found after creation attempt${NC}"
        echo -e "  ${YELLOW}Expected: $schema_table${NC}"
        return 1
    fi
}

# Analyze what would be copied
echo -e "${BLUE}Analyzing filtered data...${NC}"
echo -e "${YELLOW}Table${NC} | ${YELLOW}Filtered Rows${NC} | ${YELLOW}Status${NC}"
echo "----------------------------------------"

TOTAL_ROWS=0
VALID_TABLES=()

for table in "${TABLES[@]}"; do
    echo -n "$table | "
    
    # Check if table exists locally
    if ! table_exists_locally "$table"; then
        echo -e "${YELLOW}Creating${NC}"
        echo -e "${YELLOW}⚠ Table $table doesn't exist locally. Creating structure...${NC}"
        
        if create_table_structure "$table"; then
            echo -n "$table | "
        else
            echo -e "${RED}Failed to create${NC}"
            continue
        fi
    fi
    
    # Get filtered count
    count=$(get_filtered_count "$table" "$WHERE_CLAUSE")
    if [ "$count" = "ERROR" ]; then
        echo -e "${RED}Query Error${NC}"
        echo -e "${YELLOW}⚠ Error executing WHERE clause on $table. Check column names and syntax.${NC}"
        continue
    fi
    
    echo -n "$count | "
    
    if [ "$count" -eq 0 ]; then
        echo -e "${YELLOW}No data${NC}"
    else
        echo -e "${GREEN}Ready${NC}"
        VALID_TABLES+=("$table")
        TOTAL_ROWS=$((TOTAL_ROWS + count))
    fi
done

echo ""
echo -e "${GREEN}Total rows to copy: $TOTAL_ROWS${NC}"
echo -e "${GREEN}Valid tables: ${#VALID_TABLES[@]}${NC}"

if [ ${#VALID_TABLES[@]} -eq 0 ]; then
    echo -e "${RED}No valid tables to copy${NC}"
    exit 1
fi

# Exit if dry run
if [ "$DRY_RUN" = "true" ]; then
    echo -e "${BLUE}Dry run completed. No data was copied.${NC}"
    exit 0
fi

# Confirm before proceeding
echo ""
echo -e "${YELLOW}This will copy $TOTAL_ROWS rows from ${#VALID_TABLES[@]} tables.${NC}"
if [ "$TRUNCATE_FIRST" = "true" ]; then
    echo -e "${YELLOW}⚠ Target tables will be truncated first.${NC}"
fi
echo -n "Continue? (y/N): "
read -r response </dev/tty
if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Function to copy filtered data from a table
copy_filtered_table() {
    local schema_table=$1
    local where_clause=$2
    
    echo -e "${GREEN}Copying $schema_table with filter...${NC}"
    
    # Truncate if requested
    if [ "$TRUNCATE_FIRST" = "true" ]; then
        echo -e "${YELLOW}  Truncating target table...${NC}"
        psql -d $LOCAL_DB -c "TRUNCATE TABLE $schema_table CASCADE;" 2>/dev/null
    fi
    
    # Get columns to ensure proper order
    columns=$(get_table_columns "$schema_table")
    if [ -z "$columns" ]; then
        echo -e "${RED}  ✗ Failed to get column information${NC}"
        return 1
    fi
    
    # Copy data using COPY command for efficiency
    echo -e "${YELLOW}  Executing filtered copy...${NC}"
    
    PGPASSWORD=$REMOTE_PASS psql -h $REMOTE_HOST -p $REMOTE_PORT -U $REMOTE_USER -d $REMOTE_DB -c "
        COPY (
            SELECT * 
            FROM $schema_table 
            WHERE $where_clause
        ) TO STDOUT WITH (FORMAT CSV)
    " | psql -d $LOCAL_DB -c "COPY $schema_table FROM STDIN WITH (FORMAT CSV)"
    
    if [ $? -eq 0 ]; then
        # Get actual copied count
        local copied_count=$(psql -d $LOCAL_DB -t -c "SELECT COUNT(*) FROM $schema_table" 2>/dev/null | tr -d ' ')
        echo -e "${GREEN}  ✓ Successfully copied to $schema_table (local count: $copied_count)${NC}"
        return 0
    else
        echo -e "${RED}  ✗ Failed to copy $schema_table${NC}"
        return 1
    fi
}

# Copy data for each valid table
echo ""
echo -e "${BLUE}Starting filtered data copy...${NC}"

SUCCESS_COUNT=0
for table in "${VALID_TABLES[@]}"; do
    if copy_filtered_table "$table" "$WHERE_CLAUSE"; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    fi
    echo ""
done

echo -e "${GREEN}✅ Filtered copy completed!${NC}"
echo -e "${GREEN}Successfully copied: $SUCCESS_COUNT/${#VALID_TABLES[@]} tables${NC}"

# Show summary
echo ""
echo -e "${BLUE}Summary of copied data:${NC}"
for table in "${VALID_TABLES[@]}"; do
    count=$(psql -d $LOCAL_DB -t -c "SELECT COUNT(*) FROM $table" 2>/dev/null | tr -d ' ')
    echo -e "  $table: $count rows"
done
