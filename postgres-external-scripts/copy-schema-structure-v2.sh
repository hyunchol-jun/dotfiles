#!/bin/bash

# Script to copy PostgreSQL schema structure in phases
# Usage: ./copy-schema-structure-v2.sh [schema_name]

# Configuration - matches other scripts
REMOTE_HOST="localhost"
REMOTE_PORT="9001"
REMOTE_DB="app"
REMOTE_USER="v-oidc-822-reader-i-7mjvuE8S0K9IgUsSz27O-1752631871"
REMOTE_PASS="XT5I3t538N-1EWMsGeza"
LOCAL_DB="implentio_local"

# Default schema
DEFAULT_SCHEMA="cdm"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get schema from argument or use default
SCHEMA="${1:-$DEFAULT_SCHEMA}"

echo -e "${BLUE}=== PostgreSQL Schema Structure Copy (v2) ===${NC}"
echo -e "${YELLOW}Source: $REMOTE_HOST:$REMOTE_PORT/$REMOTE_DB (schema: $SCHEMA)${NC}"
echo -e "${YELLOW}Target: localhost/$LOCAL_DB${NC}"
echo -e "${YELLOW}Strategy: Phased approach (tables → indexes → constraints)${NC}"
echo ""

# Check for PostgreSQL 16 pg_dump
if [ -f "/opt/homebrew/opt/postgresql@16/bin/pg_dump" ]; then
    PG_DUMP="/opt/homebrew/opt/postgresql@16/bin/pg_dump"
elif [ -f "/usr/local/opt/postgresql@16/bin/pg_dump" ]; then
    PG_DUMP="/usr/local/opt/postgresql@16/bin/pg_dump"
else
    echo -e "${RED}Error: PostgreSQL 16 pg_dump not found${NC}"
    exit 1
fi

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
echo -e "${GREEN}✓ Connections successful${NC}"
echo ""

# Create temporary directory
TEMP_DIR=$(mktemp -d)
echo -e "${YELLOW}Using temporary directory: $TEMP_DIR${NC}"

# Cleanup function
cleanup() {
    echo -e "${YELLOW}Cleaning up temporary files...${NC}"
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Function to get table count from remote
get_remote_table_count() {
    PGPASSWORD=$REMOTE_PASS psql -h $REMOTE_HOST -p $REMOTE_PORT -U $REMOTE_USER -d $REMOTE_DB -t -c "
        SELECT COUNT(*) FROM information_schema.tables 
        WHERE table_schema = '$SCHEMA' AND table_type = 'BASE TABLE'
    " | tr -d ' '
}

# Get expected table count
EXPECTED_TABLES=$(get_remote_table_count)
echo -e "${GREEN}Expected tables to copy: $EXPECTED_TABLES${NC}"
echo ""

# Confirm before proceeding
echo -e "${YELLOW}This will replace the '$SCHEMA' schema in the local database.${NC}"
echo -n "Continue? (y/N): "
read -r response </dev/tty
if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi
echo ""

# PHASE 1: Tables and basic structure only
echo -e "${BLUE}=== PHASE 1: Creating table structures ===${NC}"

# Prepare local schema
echo -e "${YELLOW}Preparing local schema...${NC}"
psql -d $LOCAL_DB <<EOF > /dev/null 2>&1
DROP SCHEMA IF EXISTS $SCHEMA CASCADE;
CREATE SCHEMA $SCHEMA;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
EOF
echo -e "${GREEN}✓ Schema prepared${NC}"

# Dump full schema first
echo -e "${YELLOW}Extracting schema...${NC}"
PGPASSWORD=$REMOTE_PASS $PG_DUMP \
    -h $REMOTE_HOST \
    -p $REMOTE_PORT \
    -U $REMOTE_USER \
    -d $REMOTE_DB \
    --schema=$SCHEMA \
    --schema-only \
    --no-owner \
    --no-privileges \
    --no-tablespaces \
    -f "$TEMP_DIR/full_schema.sql" 2>/dev/null

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to dump schema${NC}"
    exit 1
fi

# Extract just CREATE TABLE statements with their full definitions
echo -e "${YELLOW}Processing table definitions...${NC}"
awk '
    /^CREATE TABLE/ { 
        printing = 1; 
        table_def = $0; 
        next 
    } 
    printing && /^\);/ { 
        table_def = table_def "\n" $0; 
        print table_def; 
        printing = 0; 
        table_def = "" 
    }
    printing { 
        table_def = table_def "\n" $0 
    }
' "$TEMP_DIR/full_schema.sql" | \
sed -E 's/cdm\.uuid_generate_v4\(\)/public.uuid_generate_v4()/g' > "$TEMP_DIR/tables_clean.sql"

# Apply table structures
echo -e "${YELLOW}Creating tables...${NC}"
psql -d $LOCAL_DB -f "$TEMP_DIR/tables_clean.sql" > "$TEMP_DIR/tables.log" 2>&1

TABLE_ERRORS=$(grep -c "ERROR:" "$TEMP_DIR/tables.log" || echo 0)
if [ "$TABLE_ERRORS" -gt 0 ]; then
    echo -e "${RED}Found $TABLE_ERRORS errors creating tables:${NC}"
    grep "ERROR:" "$TEMP_DIR/tables.log" | head -5
    echo ""
fi

# Verify table creation
LOCAL_TABLES=$(psql -d $LOCAL_DB -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '$SCHEMA' AND table_type = 'BASE TABLE'" | tr -d ' ')
echo -e "${GREEN}✓ Phase 1 complete: $LOCAL_TABLES/$EXPECTED_TABLES tables created${NC}"
echo ""

if [ "$LOCAL_TABLES" -eq 0 ]; then
    echo -e "${RED}No tables were created. Check the logs.${NC}"
    echo "View table creation log? (y/N): "
    read -r response </dev/tty
    if [[ "$response" =~ ^[Yy]$ ]]; then
        less "$TEMP_DIR/tables.log"
    fi
    exit 1
fi

# PHASE 2: Indexes (optional, with error tolerance)
echo -e "${BLUE}=== PHASE 2: Creating indexes ===${NC}"

# Extract indexes separately
echo -e "${YELLOW}Extracting index definitions...${NC}"
PGPASSWORD=$REMOTE_PASS $PG_DUMP \
    -h $REMOTE_HOST \
    -p $REMOTE_PORT \
    -U $REMOTE_USER \
    -d $REMOTE_DB \
    --schema=$SCHEMA \
    --schema-only \
    --no-owner \
    --no-privileges \
    -f "$TEMP_DIR/full_schema.sql" 2>/dev/null

# Extract just CREATE INDEX statements and clean them
grep "CREATE.*INDEX" "$TEMP_DIR/full_schema.sql" | \
    sed -E \
        -e 's/ NULLS FIRST//g' \
        -e 's/ NULLS LAST//g' \
        -e 's/USING btree //g' \
    > "$TEMP_DIR/indexes.sql"

if [ -s "$TEMP_DIR/indexes.sql" ]; then
    echo -e "${YELLOW}Creating indexes (errors are non-fatal)...${NC}"
    psql -d $LOCAL_DB -f "$TEMP_DIR/indexes.sql" > "$TEMP_DIR/indexes.log" 2>&1
    
    INDEX_ERRORS=$(grep -c "ERROR:" "$TEMP_DIR/indexes.log" || echo 0)
    INDEX_SUCCESS=$(grep -c "CREATE INDEX" "$TEMP_DIR/indexes.log" || echo 0)
    
    echo -e "${GREEN}✓ Phase 2 complete: $INDEX_SUCCESS indexes created, $INDEX_ERRORS errors (ignored)${NC}"
else
    echo -e "${YELLOW}No indexes found to create${NC}"
fi
echo ""

# PHASE 3: Constraints (optional, with error tolerance)
echo -e "${BLUE}=== PHASE 3: Adding constraints ===${NC}"

# Extract constraints
grep "ALTER TABLE.*ADD CONSTRAINT" "$TEMP_DIR/full_schema.sql" > "$TEMP_DIR/constraints.sql"

if [ -s "$TEMP_DIR/constraints.sql" ]; then
    echo -e "${YELLOW}Adding constraints (errors are non-fatal)...${NC}"
    psql -d $LOCAL_DB -f "$TEMP_DIR/constraints.sql" > "$TEMP_DIR/constraints.log" 2>&1
    
    CONSTRAINT_ERRORS=$(grep -c "ERROR:" "$TEMP_DIR/constraints.log" || echo 0)
    CONSTRAINT_SUCCESS=$(grep -c "ADD CONSTRAINT" "$TEMP_DIR/constraints.log" || echo 0)
    
    echo -e "${GREEN}✓ Phase 3 complete: $CONSTRAINT_SUCCESS constraints added, $CONSTRAINT_ERRORS errors (ignored)${NC}"
else
    echo -e "${YELLOW}No constraints found to create${NC}"
fi
echo ""

# Final verification
echo -e "${BLUE}=== FINAL RESULTS ===${NC}"
FINAL_TABLES=$(psql -d $LOCAL_DB -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '$SCHEMA' AND table_type = 'BASE TABLE'" | tr -d ' ')
FINAL_INDEXES=$(psql -d $LOCAL_DB -t -c "SELECT COUNT(*) FROM pg_indexes WHERE schemaname = '$SCHEMA'" | tr -d ' ')

echo -e "${GREEN}✅ Schema copy completed!${NC}"
echo -e "  • Tables: $FINAL_TABLES/$EXPECTED_TABLES"
echo -e "  • Indexes: $FINAL_INDEXES"

if [ "$FINAL_TABLES" -eq "$EXPECTED_TABLES" ]; then
    echo -e "${GREEN}🎉 All tables successfully created!${NC}"
else
    echo -e "${YELLOW}⚠ Some tables may be missing. Check logs for details.${NC}"
fi

# Show sample tables
echo ""
echo -e "${BLUE}Sample of created tables:${NC}"
psql -d $LOCAL_DB -c "
    SELECT table_name 
    FROM information_schema.tables 
    WHERE table_schema = '$SCHEMA' 
    AND table_type = 'BASE TABLE'
    ORDER BY table_name
    LIMIT 10
"

echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "  • Use ${BLUE}./copy-specific-tables.sh${NC} to copy data"
echo -e "  • Use ${BLUE}./copy-filtered-data.sh${NC} to copy filtered subsets"