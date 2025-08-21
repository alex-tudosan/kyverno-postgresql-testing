# Phase 1 Setup Issues and Fixes

## Issues Encountered and Solutions Implemented

### 1. **eksctl Region Flag Conflict**
**Issue**: Cannot use `--region` flag when using a config file with eksctl
**Error**: `Error: cannot use --region when --config-file/-f is set`
**Fix**: Removed `--region` flag from eksctl commands when using config file
```bash
# Before (causing error)
eksctl create cluster -f eks-cluster-config-phase1.yaml --region $AWS_REGION --profile $AWS_PROFILE

# After (fixed)
eksctl create cluster -f eks-cluster-config-phase1.yaml --profile $AWS_PROFILE
```

### 2. **Variable Naming Inconsistencies**
**Issue**: Mixed usage of `REGION` vs `AWS_REGION` variables
**Error**: `REGION: unbound variable`
**Fix**: Standardized all variables to use `AWS_REGION` consistently
```bash
# Fixed all occurrences:
- eksctl get cluster --name $CLUSTER_NAME --region $AWS_REGION
- aws rds describe-db-instances --region $AWS_REGION
- aws ec2 describe-subnets --region $AWS_REGION
```

### 3. **Undefined Color Variable**
**Issue**: `CYAN` variable not defined in color codes
**Error**: `CYAN: unbound variable`
**Fix**: Replaced `CYAN` with `BLUE` in progress bar function
```bash
# Before
printf "\r${CYAN}[PROGRESS]${NC} ["

# After
printf "\r${BLUE}[PROGRESS]${NC} ["
```

### 4. **Old Function Names**
**Issue**: Using deprecated `print_status`, `print_error` functions
**Error**: Inconsistent logging output
**Fix**: Updated all functions to use new logging system
```bash
# Before
print_status "message"
print_error "error"
print_success "success"

# After
log_step "STEP" "message"
log_error "error"
log_success "success"
```

### 5. **Subnet Selection Logic**
**Issue**: Wrong subnet selection for RDS subnet group
**Error**: `Some input subnets are invalid`
**Problem**: Selected only public subnets, but RDS needs subnets from different AZs
**Fix**: Created `get_rds_subnets()` function to select correct subnets
```bash
# New function that selects subnets from different AZs
get_rds_subnets() {
    # Get all subnets and select one from each AZ
    local subnets_json=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --region "$region" --profile "$profile" --query 'Subnets[].{SubnetId:SubnetId,AvailabilityZone:AvailabilityZone}' --output json)
    local subnet_ids=$(echo "$subnets_json" | jq -r 'group_by(.AvailabilityZone) | .[0:2] | .[].SubnetId' | tr '\n' ' ')
    echo "$subnet_ids"
}
```

### 6. **Variable Conflicts in Loops**
**Issue**: `status` variable conflict in wait loops
**Error**: `zsh: read-only variable: status`
**Fix**: Used different variable names to avoid conflicts
```bash
# Before
local status=$(aws rds describe-db-instances ...)

# After
local rds_status=$(aws rds describe-db-instances ...)
```

### 7. **Password Mismatch**
**Issue**: Config password doesn't match RDS password
**Error**: `FATAL: password authentication failed for user "reportsuser"`
**Fix**: Added automatic password reset and database connectivity testing
```bash
# New automatic password reset logic
if ! test_database_connectivity "$RDS_ENDPOINT" "$DB_USERNAME" "$DB_PASSWORD" "postgres"; then
    log_warning "Database connectivity failed, resetting password..."
    NEW_PASSWORD=$(openssl rand -hex 16)
    aws rds modify-db-instance --db-instance-identifier $RDS_INSTANCE_ID --master-user-password "$NEW_PASSWORD" --apply-immediately
    DB_PASSWORD="$NEW_PASSWORD"
fi
```

### 8. **Database Creation Logic**
**Issue**: PostgreSQL doesn't support `CREATE DATABASE IF NOT EXISTS`
**Error**: SQL syntax error
**Fix**: Added proper database existence check
```bash
# Before
CREATE DATABASE IF NOT EXISTS reportsdb;

# After
if PGPASSWORD="$password" psql -h "$endpoint" -U "$username" -d postgres -c "SELECT 1 FROM pg_database WHERE datname='$database';" -t | grep -q 1; then
    log_success "Database $database already exists"
    return 0
fi
PGPASSWORD="$password" psql -h "$endpoint" -U "$username" -d postgres -c "CREATE DATABASE $database;"
```

## Enhanced Functions Added

### 1. **Database Connectivity Testing**
```bash
test_database_connectivity() {
    local endpoint=$1
    local username=$2
    local password=$3
    local database=$4
    
    if ! PGPASSWORD="$password" psql -h "$endpoint" -U "$username" -d postgres -c "SELECT 1;" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}
```

### 2. **Dynamic RDS Endpoint Resolution**
```bash
get_rds_endpoint() {
    local instance_id=$1
    local region=$2
    local profile=$3
    
    local endpoint=$(aws rds describe-db-instances --db-instance-identifier "$instance_id" --region "$region" --profile "$profile" --query 'DBInstances[0].Endpoint.Address' --output text 2>/dev/null)
    
    if [[ -z "$endpoint" || "$endpoint" == "None" ]]; then
        return 1
    fi
    echo "$endpoint"
    return 0
}
```

### 3. **RDS Subnet Selection**
```bash
get_rds_subnets() {
    # Gets subnets from different AZs for RDS subnet group
    # Returns space-separated list of subnet IDs
}
```

### 4. **Configuration Validation**
```bash
validate_config() {
    # Validates all required environment variables are set
    # Exits with error if any are missing
}
```

## Prevention Measures

### 1. **Automatic Error Recovery**
- Database connectivity failures trigger automatic password reset
- Subnet selection errors are handled with proper validation
- Variable conflicts are prevented with unique naming

### 2. **Enhanced Logging**
- All steps now have consistent logging with timestamps
- Progress bars show real-time status
- Error messages are clear and actionable

### 3. **Validation Checks**
- Configuration validation before starting
- Database connectivity testing
- Resource existence checks
- Proper error handling with cleanup

### 4. **Robust Retry Logic**
- Exponential backoff for failed commands
- Proper timeout handling
- Graceful degradation

## Testing Recommendations

1. **Run the setup multiple times** to ensure all fixes work consistently
2. **Test cleanup script** to ensure proper resource removal
3. **Verify monitoring integration** works correctly
4. **Test policy enforcement** with sample workloads
5. **Validate database connectivity** under different conditions

## Future Improvements

1. **Add health checks** for all components
2. **Implement rollback functionality** for partial failures
3. **Add configuration validation** for all parameters
4. **Create automated testing** for the setup process
5. **Add performance monitoring** during setup
