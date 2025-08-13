#!/bin/bash

# Script to copy all table structures from a PostgreSQL schema
# Usage: ./copy-schema-structure.sh [schema_name]

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

echo -e "${BLUE}=== PostgreSQL Schema Structure Copy ===${NC}"
echo -e "${YELLOW}Source: $REMOTE_HOST:$REMOTE_PORT/$REMOTE_DB (schema: $SCHEMA)${NC}"
echo -e "${YELLOW}Target: localhost/$LOCAL_DB${NC}"
echo ""

# Test remote connection
echo -e "${YELLOW}Testing remote connection...${NC}"
PGPASSWORD=$REMOTE_PASS psql -h $REMOTE_HOST -p $REMOTE_PORT -U $REMOTE_USER -d $REMOTE_DB -c "SELECT 1" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to connect to remote database${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Remote connection successful${NC}"

# Test local connection
echo -e "${YELLOW}Testing local connection...${NC}"
psql -d $LOCAL_DB -c "SELECT 1" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to connect to local database${NC}"
    echo -e "${YELLOW}Make sure database '$LOCAL_DB' exists${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Local connection successful${NC}"
echo ""

# Create temporary directory for dump files
TEMP_DIR=$(mktemp -d)
echo -e "${YELLOW}Using temporary directory: $TEMP_DIR${NC}"

# Function to clean up on exit
cleanup() {
    echo -e "${YELLOW}Cleaning up temporary files...${NC}"
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Check for PostgreSQL 16 pg_dump
if [ -f "/opt/homebrew/opt/postgresql@16/bin/pg_dump" ]; then
    PG_DUMP="/opt/homebrew/opt/postgresql@16/bin/pg_dump"
elif [ -f "/usr/local/opt/postgresql@16/bin/pg_dump" ]; then
    PG_DUMP="/usr/local/opt/postgresql@16/bin/pg_dump"
else
    echo -e "${RED}Error: PostgreSQL 16 pg_dump not found${NC}"
    echo -e "${YELLOW}Please ensure PostgreSQL 16 is installed via Homebrew${NC}"
    echo -e "${YELLOW}Run: brew install postgresql@16${NC}"
    exit 1
fi

# Dump schema structure only (no data)
echo -e "${BLUE}Extracting schema structure from remote database...${NC}"
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
    --no-unlogged-table-data \
    -f "$TEMP_DIR/schema_dump_raw.sql"

# Clean up the schema dump
echo -e "${BLUE}Processing schema dump...${NC}"
sed -E \
    -e 's/CREATE SCHEMA [^;]+;/CREATE SCHEMA IF NOT EXISTS '$SCHEMA';/g' \
    -e 's/cdm\.uuid_generate_v4\(\)/public.uuid_generate_v4()/g' \
    -e '/^SET /d' \
    -e '/^SELECT pg_catalog\.set_config/d' \
    -e '/^--/d' \
    -e 's/ NULLS FIRST//g' \
    -e 's/ NULLS LAST//g' \
    -e 's/NULLS FIRST //g' \
    -e 's/NULLS LAST //g' \
    -e '/^ALTER TABLE.*ATTACH PARTITION/d' \
    -e '/^ATTACH PARTITION/d' \
    "$TEMP_DIR/schema_dump_raw.sql" > "$TEMP_DIR/schema_dump.sql"

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to dump schema structure${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Schema structure extracted${NC}"

# Count objects
echo -e "${BLUE}Analyzing schema contents...${NC}"
TABLES=$(grep -c "CREATE TABLE" "$TEMP_DIR/schema_dump.sql" || echo 0)
INDEXES=$(grep -c "CREATE.*INDEX" "$TEMP_DIR/schema_dump.sql" || echo 0)
CONSTRAINTS=$(grep -c "ADD CONSTRAINT" "$TEMP_DIR/schema_dump.sql" || echo 0)
SEQUENCES=$(grep -c "CREATE SEQUENCE" "$TEMP_DIR/schema_dump.sql" || echo 0)

echo -e "${GREEN}Found:${NC}"
echo -e "  • Tables: $TABLES"
echo -e "  • Indexes: $INDEXES"
echo -e "  • Constraints: $CONSTRAINTS"
echo -e "  • Sequences: $SEQUENCES"
echo ""

# Ask for confirmation
echo -e "${YELLOW}This will create/replace the '$SCHEMA' schema in the local database.${NC}"
echo -n "Continue? (y/N): "
read -r response </dev/tty
if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi
echo ""

# Drop and recreate schema locally
echo -e "${BLUE}Preparing local schema...${NC}"
psql -d $LOCAL_DB <<EOF
-- Drop schema cascade (removes all objects)
DROP SCHEMA IF EXISTS $SCHEMA CASCADE;

-- Create schema
CREATE SCHEMA $SCHEMA;

-- Create any required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
EOF

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to prepare local schema${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Local schema prepared${NC}"

# Split the dump into separate files for better dependency handling
echo -e "${BLUE}Processing schema dump for dependency handling...${NC}"

# Extract different object types
grep -n "CREATE TABLE" "$TEMP_DIR/schema_dump.sql" > "$TEMP_DIR/tables.txt"
grep -n "ALTER TABLE.*ADD CONSTRAINT.*FOREIGN KEY" "$TEMP_DIR/schema_dump.sql" > "$TEMP_DIR/foreign_keys.txt"
grep -n "CREATE.*INDEX" "$TEMP_DIR/schema_dump.sql" > "$TEMP_DIR/indexes.txt"

# Apply schema in phases to handle dependencies
echo -e "${BLUE}Phase 1: Creating tables and basic structures...${NC}"
psql -d $LOCAL_DB -f "$TEMP_DIR/schema_dump.sql" > "$TEMP_DIR/import.log" 2>&1

# Show immediate errors
ERRORS=$(grep -c "ERROR:" "$TEMP_DIR/import.log" || echo 0)
if [ "$ERRORS" -gt 0 ]; then
    echo -e "${RED}Found $ERRORS errors during import:${NC}"
    grep "ERROR:" "$TEMP_DIR/import.log" | head -10
    echo ""
    
    # Try alternative approach: apply without foreign keys first
    echo -e "${YELLOW}Trying alternative approach: removing foreign key constraints...${NC}"
    
    # Create version without foreign keys and fix additional issues
    sed -E \
        -e '/ADD CONSTRAINT.*FOREIGN KEY/d' \
        -e 's/CREATE SCHEMA [^;]+;/CREATE SCHEMA IF NOT EXISTS '$SCHEMA';/g' \
        "$TEMP_DIR/schema_dump.sql" > "$TEMP_DIR/schema_no_fk.sql"
    
    # Drop and recreate schema
    psql -d $LOCAL_DB -c "DROP SCHEMA IF EXISTS $SCHEMA CASCADE; CREATE SCHEMA $SCHEMA;"
    
    # Apply without foreign keys
    psql -d $LOCAL_DB -f "$TEMP_DIR/schema_no_fk.sql" > "$TEMP_DIR/import_no_fk.log" 2>&1
    
    FK_ERRORS=$(grep -c "ERROR:" "$TEMP_DIR/import_no_fk.log" || echo 0)
    if [ "$FK_ERRORS" -gt 0 ]; then
        echo -e "${RED}Still have $FK_ERRORS errors:${NC}"
        grep "ERROR:" "$TEMP_DIR/import_no_fk.log" | head -5
    else
        echo -e "${GREEN}✓ Tables created successfully without foreign keys${NC}"
        
        # Now try to add foreign keys
        echo -e "${BLUE}Phase 2: Adding foreign key constraints...${NC}"
        grep "ADD CONSTRAINT.*FOREIGN KEY" "$TEMP_DIR/schema_dump.sql" > "$TEMP_DIR/add_fk.sql"
        if [ -s "$TEMP_DIR/add_fk.sql" ]; then
            sed 's/^/ALTER TABLE /' "$TEMP_DIR/add_fk.sql" | psql -d $LOCAL_DB > "$TEMP_DIR/fk.log" 2>&1
            FK_ADD_ERRORS=$(grep -c "ERROR:" "$TEMP_DIR/fk.log" || echo 0)
            echo -e "${YELLOW}Foreign key constraint results: $FK_ADD_ERRORS errors${NC}"
        fi
    fi
else
    echo -e "${GREEN}✓ Schema structure applied successfully${NC}"
fi

# Verify the import
echo ""
echo -e "${BLUE}Verifying import...${NC}"
LOCAL_TABLES=$(psql -d $LOCAL_DB -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '$SCHEMA' AND table_type = 'BASE TABLE'" | tr -d ' ')
LOCAL_INDEXES=$(psql -d $LOCAL_DB -t -c "SELECT COUNT(*) FROM pg_indexes WHERE schemaname = '$SCHEMA'" | tr -d ' ')

echo -e "${GREEN}Local database now has:${NC}"
echo -e "  • Tables: $LOCAL_TABLES"
echo -e "  • Indexes: $LOCAL_INDEXES"

# Show sample of created tables
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
echo -e "${GREEN}✅ Schema structure copy completed!${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "  • Use ${BLUE}./copy-specific-tables.sh${NC} to copy data for specific tables"
echo -e "  • Or write a migration script to populate initial data"
echo -e "  • Check for any application-specific database objects (views, functions, etc.)"
