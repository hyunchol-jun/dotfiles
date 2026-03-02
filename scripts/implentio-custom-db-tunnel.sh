#!/usr/bin/env bash

# Example call
# ../rules/scripts/custom-db-tunnel.sh -l 9001 -d app -h localhost -r Reader

# This script:
# 1. Presents the user with all available database in the cluster (optionally scoped by namespace)
# 2. Presents the user with the available roles for the selected database
# 3. Presents credentials for the selected role
# 4. Opens a tunnel to the selected database

set -eo pipefail

# Use this trap to ensure that database credentials are only
# valid while the tunnel is active
handle_exit() {
  # Remove MCP server configuration
  if command -v claude &> /dev/null; then
    echo "Removing MCP server configuration..." >&2
    claude mcp remove -s user pg-tunnel 2>/dev/null || true
  fi

  if [[ -n $LEASE_ID ]]; then
    echo "Tunnel terminated. Revoking database credentials..." >&2
    vault lease revoke "$LEASE_ID"
  fi
}
trap 'handle_exit' EXIT

####################################################################
# Step 0: Error checking
####################################################################
pf-check-ssh

####################################################################
# Step 1: Variable parsing
####################################################################

# Initialize our own variables:
LOCAL_PORT=""
NAMESPACE=""
DBNAME=""
ROLE=""
HOST=""

# Define the function to display the usage
usage() {
  echo "Usage: db-tunnel [-l <local-port>] [-n <namespace>] [-d <db-name>] [-h <host>] [-r <role>]" >&2
  echo "       db-tunnel [--local-port <local-port>] [--namespace <namespace>] [--db-name <db-name>] [--host <host>] [--role <role>]" >&2
  echo "" >&2
  echo "<local-port>: (Optional) The local port to bind to." >&2
  echo "" >&2
  echo "<namespace>: (Optional) Only show databases in this namespace" >&2
  echo "" >&2
  echo "<db-name>: (Optional) DB name that will be used in output" >&2
  echo "" >&2
  echo "<host>: (Optional) Host that will be used in output" >&2
  echo "" >&2
  echo "<role>: (Optional) DB role [Superuser | Admin | Reader]" >&2
  echo "" >&2
  exit 1
}

# Parse command line arguments
TEMP=$(getopt -o l:n:d:h:r: --long local-port:,namespace:,db-name:,host:,role: -- "$@")

# shellcheck disable=SC2181
if [[ $? != 0 ]]; then
  echo "Failed parsing options." >&2
  exit 1
fi

# Note the quotes around `$TEMP`: they are essential!
eval set -- "$TEMP"

# Extract options and their arguments into variables
while true; do
  case "$1" in
  -l | --local-port)
    LOCAL_PORT="$2"
    shift 2
    ;;
  -n | --namespace)
    NAMESPACE="$2"
    shift 2
    ;;
  -d | --db-name)
    DBNAME="$2"
    shift 2
    ;;
  -h | --host)
    HOST="$2"
    shift 2
    ;;
  -r | --role)
    ROLE="$2"
    shift 2
    ;;
  --)
    shift
    break
    ;;
  *)
    usage
    ;;
  esac
done

####################################################################
# Step 1: Get the Vault Address
####################################################################
KUBE_CONTEXT="$(kubectl config current-context)"
VAULT_ADDR=$(kubectl get sts -n vault -o jsonpath="{.items[?(@.metadata.name=='vault')].metadata.annotations['panfactum\.com\/vault-addr']}")

if [[ -z $VAULT_ADDR ]]; then
  echo "Unable to retrieve Vault address in $KUBE_CONTEXT" >&2
  exit 1
fi

echo "Connecting to Vault in $KUBE_CONTEXT..." >&2
export VAULT_ADDR

####################################################################
# Step 2: Get the Vault token
####################################################################

VAULT_TOKEN=$(pf-get-vault-token)
echo "Retrieved Vault token." >&2

####################################################################
# Step 3: List all the databases for the current kubectx; allow the user to select one
####################################################################

if [[ -n $NAMESPACE ]]; then
  NAMESPACE_FLAG="-n=$NAMESPACE"
  echo "Searching for all databases in $KUBE_CONTEXT in namespace $NAMESPACE..." >&2
else
  NAMESPACE_FLAG="--all-namespaces"
  echo "Searching for all databases in $KUBE_CONTEXT..." >&2
fi

PG_DBS=$(kubectl get clusters.postgresql.cnpg.io "$NAMESPACE_FLAG" -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name --no-headers | awk '{printf "%-15s %-25s %-25s\n", "PostgreSQL", $1, $2}')
DBS="$PG_DBS"
HEADER=$(printf "%-15s %-25s %-25s" "TYPE" "NAMESPACE" "NAME")

if [[ -z $DBS ]]; then
  echo "No databases found." >&2
  exit 1
fi

while IFS= read -r line; do
    # Check if line contains implentio (case-insensitive)
    if [[ $line =~ implentio ]]; then
        SELECTED_DB="$line"
        echo "Found implentio database: $SELECTED_DB"
    fi
done <<< "$DBS"

if [[ -z $SELECTED_DB ]]; then
  echo "Implentio DB not found." >&2
  exit 1
fi

SELECTED_DB_TYPE=$(echo "$SELECTED_DB" | awk '{print $1}')
SELECTED_DB_NAMESPACE=$(echo "$SELECTED_DB" | awk '{print $2}')
SELECTED_DB_NAME=$(echo "$SELECTED_DB" | awk '{print $3}')

####################################################################
# Step 4: Find the database metadata
####################################################################

KUBE_TYPE=""

if [[ $SELECTED_DB_TYPE == "PostgreSQL" ]]; then
  KUBE_TYPE="clusters.postgresql.cnpg.io"
elif [[ $SELECTED_DB_TYPE == "Redis" ]]; then
  KUBE_TYPE="statefulset"
fi

ANNOTATIONS=$(kubectl get "$KUBE_TYPE" -n "$SELECTED_DB_NAMESPACE" -o jsonpath="{.items[?(@.metadata.name=='$SELECTED_DB_NAME')].metadata.annotations}" 2>/dev/null)

if [[ -z $ANNOTATIONS ]]; then
  echo "Unable to retrieve annotations for $KUBE_TYPE $SELECTED_DB_NAME.$SELECTED_DB_NAMESPACE" >&2
  exit 1
fi

SUPERUSER_ROLE=$(echo "$ANNOTATIONS" | jq -r '.["panfactum.com/superuser-role"]')
READER_ROLE=$(echo "$ANNOTATIONS" | jq -r '.["panfactum.com/reader-role"]')
ADMIN_ROLE=$(echo "$ANNOTATIONS" | jq -r '.["panfactum.com/admin-role"]')
SERVICE=$(echo "$ANNOTATIONS" | jq -r '.["panfactum.com/service"]')
SERVICE_PORT=$(echo "$ANNOTATIONS" | jq -r '.["panfactum.com/service-port"]')

####################################################################
# Step 5: Select a database role
####################################################################

SELECTED_ROLE="$ROLE"

####################################################################
# Step 6: Get the database credentials
####################################################################

echo "Retrieving $SELECTED_ROLE credentials for $SELECTED_DB_NAME.$SELECTED_DB_NAMESPACE from Vault at $VAULT_ADDR..." >&2
ACTUAL_ROLE=""

case "$SELECTED_ROLE" in
Superuser)
  ACTUAL_ROLE="$SUPERUSER_ROLE"
  ;;
Reader)
  ACTUAL_ROLE="$READER_ROLE"
  ;;
Admin)
  ACTUAL_ROLE="$ADMIN_ROLE"
  ;;
*)
  exit 1
  ;;
esac

export VAULT_TOKEN
CREDS="$(pf-get-db-creds --role "$ACTUAL_ROLE")"

if [[ -z $CREDS ]]; then
  echo "Unable to retrieve credentials at $VAULT_ADDR for $ACTUAL_ROLE" >&2
  exit 1
fi

USERNAME=$(echo -n "$CREDS" | grep username | awk '{print $2}')
PASSWORD=$(echo -n "$CREDS" | grep password | awk '{print $2}')
DURATION=$(echo -n "$CREDS" | grep lease_duration | awk '{print $2}')
LEASE_ID=$(echo -n "$CREDS" | grep lease_id | awk '{print $2}')

####################################################################
# Step 7: Pick a local port
####################################################################

if [[ ! $LOCAL_PORT =~ ^[0-9]+$ ]] || ((LOCAL_PORT < 1024 || LOCAL_PORT > 65535)); then
  while :; do
    read -rp "Enter a local port for the tunnel between 1024 and 65535: " LOCAL_PORT
    [[ $LOCAL_PORT =~ ^[0-9]+$ ]] || {
      echo "Not a number!" >&2
      continue
    }
    if ((LOCAL_PORT > 1024 && LOCAL_PORT < 65535)); then
      break
    else
      echo "port out of range, try again" >&2
    fi
  done
fi

####################################################################
# Step 8: Pick a local port
####################################################################
DBURL="postgresql://$USERNAME:$PASSWORD@$HOST:$LOCAL_PORT/$DBNAME"
echo "" >&2
echo "Credentials will expire in $DURATION or until tunnel termination:" >&2
echo "" >&2
echo "Username: $USERNAME" >&2
echo "Password: $PASSWORD" >&2
echo "URL: $DBURL" >&2
echo "" >&2
echo $DBURL | pbcopy
echo "DB URL copied to clipboard"
echo "" >&2

echo "Running a tunnel on localhost:$LOCAL_PORT to $SELECTED_DB_TYPE database $SELECTED_DB_NAME.$SELECTED_DB_NAMESPACE via $SERVICE:$SERVICE_PORT!" >&2

###################################################################
# Step 9: Save URL to env file
###################################################################

# The file path
ENV_FILE=~/Implentio/db/.env

# Check if file exists
if [ ! -f "$ENV_FILE" ]; then
    echo "Error: $ENV_FILE does not exist. Failed to save URL to the file."
fi

# Replace the line starting with DB_URL= with new value
# -i for in-place editing
sed -i "s#^DB_UI_IMPLENTIO=.*#DB_UI_IMPLENTIO=$DBURL#" "$ENV_FILE"

echo "Updated DB_UI_IMPLENTIO in $ENV_FILE"

APP_ENV=~/Implentio/implentio-app.git/main/packages/api-v2/.env

if [ ! -f "$APP_ENV" ]; then
    echo "Error: $APP_ENV does not exist. Failed to save URL to the file."
fi

sed -i "s#^CDM_DB_URL=.*#CDM_DB_URL=$DBURL?schema=cdm#" "$APP_ENV"
sed -i "s#^CLIENT_DB_URL=.*#CLIENT_DB_URL=$DBURL?schema=client#" "$APP_ENV"

echo "Updated DB_URL in $APP_ENV"

RECONCILIATION_API_ENV=~/Implentio/reconciliation-engine/projects/api/src/main/resources/application-local.yml

if [ ! -f "$RECONCILIATION_API_ENV" ]; then
    echo "Error: $RECONCILIATION_API_ENV does not exist. Failed to save URL to the file."
fi

sed -i "s#^    username: .*#    username: $USERNAME#" "$RECONCILIATION_API_ENV"
sed -i "s#^    password: .*#    password: $PASSWORD#" "$RECONCILIATION_API_ENV"

echo "Updated db credentials in $RECONCILIATION_API_ENV"

# Start tunnel in the background
pf-tunnel -b "$KUBE_CONTEXT" -r "$SERVICE:$SERVICE_PORT" -l "$LOCAL_PORT" &
TUNNEL_PID=$!

sleep 3

# Configure MCP server if claude CLI is available
if command -v claude &> /dev/null; then
  claude mcp remove -s user pg-tunnel 2>/dev/null || true
  claude mcp add -s user pg-tunnel -- npx -y mcp-server-postgres-multi-schema "postgresql://$USERNAME:$PASSWORD@localhost:$LOCAL_PORT/$DBNAME" public,client,cdm,analytics,reconciliation 2>&1
  echo "MCP server configured" >&2
fi

wait $TUNNEL_PID
