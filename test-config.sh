#!/bin/bash

echo "=== TESTING CONFIGURATION LOADING ==="
echo ""

# Test 1: Check if config file exists
echo "1. Checking if setup/config.sh exists:"
if [ -f "setup/config.sh" ]; then
    echo "   ✅ setup/config.sh found"
else
    echo "   ❌ setup/config.sh NOT found"
    exit 1
fi
echo ""

# Test 2: Load configuration
echo "2. Loading configuration from setup/config.sh:"
source setup/config.sh
echo "   ✅ Configuration loaded"
echo ""

# Test 3: Check all required variables
echo "3. Checking required variables:"
echo "   CLUSTER_NAME: ${CLUSTER_NAME:-'NOT SET'}"
echo "   AWS_REGION: ${AWS_REGION:-'NOT SET'}"
echo "   AWS_PROFILE: ${AWS_PROFILE:-'NOT SET'}"
echo "   DB_NAME: ${DB_NAME:-'NOT SET'}"
echo "   DB_USERNAME: ${DB_USERNAME:-'NOT SET'}"
echo "   TIMESTAMP: ${TIMESTAMP:-'NOT SET'}"
echo "   RDS_INSTANCE_ID: ${RDS_INSTANCE_ID:-'NOT SET'}"
echo ""

# Test 4: Validate cluster name
echo "4. Validating cluster name:"
if [ "$CLUSTER_NAME" = "report-server-test" ]; then
    echo "   ✅ CLUSTER_NAME is correct: $CLUSTER_NAME"
else
    echo "   ❌ CLUSTER_NAME is wrong: expected 'report-server-test', got '$CLUSTER_NAME'"
fi
echo ""

# Test 5: Check Terraform configuration
echo "5. Checking Terraform configuration:"
if [ -f "default-terraform-code/terraform-eks/variables.tf" ]; then
    echo "   ✅ Terraform variables.tf found"
    echo "   Terraform cluster name: $(grep 'default.*cluster_name' default-terraform-code/terraform-eks/variables.tf)"
else
    echo "   ❌ Terraform variables.tf NOT found"
fi
echo ""

# Test 6: Check for any wrong cluster names
echo "6. Checking for wrong cluster names in project:"
WRONG_NAMES=$(grep -r "Anuj-test-cluster\|alex-qa-reports-server" . --include="*.tf" --include="*.sh" --include="*.md" --exclude-dir=node_modules --exclude-dir=.git 2>/dev/null || echo "NONE FOUND")
if [ "$WRONG_NAMES" = "NONE FOUND" ]; then
    echo "   ✅ No wrong cluster names found"
else
    echo "   ❌ Wrong cluster names found:"
    echo "$WRONG_NAMES"
fi
echo ""

# Test 7: Summary
echo "=== CONFIGURATION TEST SUMMARY ==="
if [ "$CLUSTER_NAME" = "report-server-test" ] && [ -n "$AWS_REGION" ] && [ -n "$AWS_PROFILE" ]; then
    echo "✅ ALL TESTS PASSED - Configuration is working correctly!"
    echo "✅ Ready to run phase1-setup.sh"
    echo ""
    echo "Next steps:"
    echo "1. Run: aws sso login --profile devtest-sso"
    echo "2. Run: ./setup/phase1/phase1-setup.sh"
else
    echo "❌ SOME TESTS FAILED - Configuration needs fixing"
    echo "❌ Please check the errors above"
fi
echo "================================================"



