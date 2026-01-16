#!/bin/bash

# Common functions and setup for integration tests

set -u

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Paths
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI_TOOL="$REPO_ROOT/scripts/aws-lambda-layer-cli"
TEST_ROOT="$REPO_ROOT/test"

# Load .env if exists
if [ -f "$REPO_ROOT/.env" ]; then
    # echo "Loading .env..."
    set -a
    source "$REPO_ROOT/.env"
    set +a
fi

AWS_REGION=${AWS_REGION:-us-east-1}
# unique ID for this test run
RUN_ID="test-$(date +%s)-$RANDOM"
TEST_DIR="$TEST_ROOT/temp_work/$RUN_ID"
ROLE_NAME="aws-lambda-layer-cli-test-role-$RUN_ID"

# Global cleanup stack
CLEANUP_STACK=()

setup_common() {
    echo -e "${BLUE}[Setup]${NC} Preparing test environment for $RUN_ID..."
    mkdir -p "$TEST_DIR"
    
    # Check CLI tool
    if [ ! -f "$CLI_TOOL" ]; then
        echo -e "${RED}Error: CLI tool not found at $CLI_TOOL${NC}"
        exit 1
    fi
    chmod +x "$CLI_TOOL"

    # Verify AWS Connection
    if [ -n "${AWS_PROFILE:-}" ]; then
        echo -e "${BLUE}[AWS]${NC} Using profile: $AWS_PROFILE"
    elif [ -n "${AWS_ACCESS_KEY_ID:-}" ]; then
         echo -e "${BLUE}[AWS]${NC} Using explicit Access Key ID"
    fi
    
    # Register cleanup trap
    trap cleanup_common EXIT
}

cleanup_common() {
    echo -e "\n${BLUE}[Cleanup]${NC} Cleaning up resources..."
    
    # Reverse iterate cleanup stack
    for (( idx=${#CLEANUP_STACK[@]}-1 ; idx>=0 ; idx-- )) ; do
        echo "Executing: ${CLEANUP_STACK[idx]}"
        eval "${CLEANUP_STACK[idx]}" 2>/dev/null || true
    done
    
    rm -rf "$TEST_DIR"
    echo -e "${GREEN}Cleanup complete.${NC}"
}

add_cleanup() {
    CLEANUP_STACK+=("$1")
}

ensure_test_role() {
    # If ARN provided explicitly, use it
    if [ -n "${AWS_LAMBDA_ROLE_ARN:-}" ]; then
        TEST_ROLE_ARN="$AWS_LAMBDA_ROLE_ARN"
        return 0
    fi

    # If we already created/resolved it in this session (e.g. earlier test function)
    if [ -n "${TEST_ROLE_ARN:-}" ]; then
        return 0
    fi
    
    # Otherwise, attempt to create a temporary role
    echo -e "${YELLOW}Creating temporary IAM Role $ROLE_NAME...${NC}" >&2
    
    cat > "$TEST_DIR/trust-policy.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

    # Capture stderr to suppress noise if it fails
    local created_arn
    if ! created_arn=$(aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document "file://$TEST_DIR/trust-policy.json" --query "Role.Arn" --output text 2>/dev/null); then
         echo -e "${RED}Error: Failed to create IAM role and AWS_LAMBDA_ROLE_ARN is not set.${NC}" >&2
         echo -e "${YELLOW}To run tests without a pre-configured role, your AWS credentials need the following strict policy:${NC}" >&2
         cat <<POLICY >&2
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "iam:CreateRole",
                "iam:DeleteRole",
                "iam:AttachRolePolicy",
                "iam:DetachRolePolicy",
                "iam:PassRole"
            ],
            "Resource": "arn:aws:iam::*:role/aws-lambda-layer-cli-test-*"
        }
    ]
}
POLICY
         echo -e "${YELLOW}Alternatively, set AWS_LAMBDA_ROLE_ARN in .env to an existing role.${NC}" >&2
         return 1
    fi

    TEST_ROLE_ARN="$created_arn"

    # Record cleanup
    add_cleanup "aws iam delete-role --role-name $ROLE_NAME"
    
    # Attach basic execution policy
    aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    add_cleanup "aws iam detach-role-policy --role-name $ROLE_NAME --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    
    # Wait for propagation (IAM roles take time to be assumable by Lambda)
    echo -e "${YELLOW}Waiting 10s for role propagation...${NC}" >&2
    sleep 10
}

check_zip_content() {
    local zip_file=$1
    local search=$2
    
    if unzip -l "$zip_file" | grep -q "$search"; then
        return 0
    else
        echo -e "${RED}Content '$search' not found in $zip_file${NC}" >&2
        return 1
    fi
}

strip_ansi() {
    sed 's/\x1b\[[0-9;]*m//g'
}

should_run_aws_tests() {
    if [ -n "${AWS_ACCESS_KEY_ID:-}" ] || [ -f "$HOME/.aws/credentials" ]; then
        return 0
    else
        echo -e "\n${YELLOW}Skipping AWS integration tests (No credentials found)${NC}"
        return 1
    fi
}
