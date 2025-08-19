# Simple Guide: Kyverno n4k + Reports Server (PostgreSQL) Testing

## What This Is

This guide explains how to test **Kyverno n4k** (a security tool) with **Reports Server** using **PostgreSQL database** (instead of etcd) in simple terms. Think of it like testing a security guard system that uses a professional filing cabinet (PostgreSQL) instead of a simple storage box (etcd).

## The Big Picture

**What we're testing:**
- **Kyverno** = A security guard that checks if your applications follow safety rules
- **Reports Server** = A filing cabinet that keeps records of what the security guard found
- **PostgreSQL Database** = A professional, organized filing system (better than etcd)
- **AWS RDS** = Amazon's managed database service (they handle the maintenance)

**Why we're using PostgreSQL instead of etcd:**
- **Better for big companies** - Can handle thousands of reports without problems
- **More organized** - Like having a professional filing system instead of a simple box
- **Faster searches** - Can find information quickly using SQL queries
- **More reliable** - Amazon manages the database, so it's always available
- **Better for analytics** - Can run complex reports and analysis

## Phase 1: Small Test (Start Here)

### What We're Doing
We're setting up a small test environment with a professional database to see if everything works before spending more money on bigger tests.

### Why We're Starting Small
- **Cost**: Only about $121 per month (vs $2,800 for full test)
- **Risk**: If something goes wrong, we don't lose much money
- **Learning**: We can figure out what we need before scaling up
- **Validation**: Make sure the database connection works properly

### Step 1: Get Your Tools Ready

**What we're doing:** Installing the software tools we need to work with cloud nodes and databases.

**Why we're doing this:** We need these tools to create and manage our test environment.

**Commands to run:**
```bash
brew install awscli eksctl kubectl helm jq
```

**What should happen:** No errors, tools get installed successfully.

**What to check:** Type `aws --version` and `kubectl version` - both should show version numbers.

### Step 2: Set Up Your Cloud Account

**What we're doing:** Connecting to Amazon's cloud service (AWS) so we can create our test nodes and database.

**Why we're doing this:** We need cloud nodes to run our tests and a professional database to store reports.

**Commands to run:**
```bash
aws configure
export AWS_REGION=us-west-2
```

**What should happen:** 
- You'll be asked for your AWS access key, secret key, and region
- Enter your AWS credentials when prompted
- No error messages

**What to check:** Run `aws sts get-caller-identity` - it should show your AWS account information.

### Step 3: Create Your Test Environment

**What we're doing:** Creating a small group of nodes in the cloud and a professional database to run our security tests.

**Why we're doing this:** We need nodes to run Kyverno, Reports Server, and a database to store all the security reports.

**Commands to run:**
```bash
./postgresql-testing/phase1-setup.sh
```

**What should happen:**
- Script runs for about 15-20 minutes
- You'll see progress messages about creating nodes
- You'll see messages about creating a database
- You'll see messages about installing software
- No error messages

**What to check:** At the end, run `kubectl get nodes` - you should see 2 nodes listed.

### Step 4: Run Your Tests

**What we're doing:** Running 19 different tests to make sure everything works correctly, including database operations.

**Why we're doing this:** We need to verify that all parts of the system are working, especially the database connection.

**Commands to run:**
```bash
./postgresql-testing/phase1-test-cases.sh
```

**What should happen:**
- Script runs for about 5-10 minutes
- You'll see test results like "PASS" or "FAIL"
- Most tests should show "PASS"
- Database tests should show successful connections
- You might see a few "FAIL" tests (that's normal for some tests)

**What to check:** At the end, you should see a summary showing most tests passed, especially database tests.

### Step 5: Look at Your Results

**What we're doing:** Opening a web dashboard to see how your system is performing, including database performance.

**Why we're doing this:** The dashboard shows you real-time information about how well everything is working, including database health.

**Commands to run:**
```bash
# Get the password for the dashboard
kubectl -n monitoring get secret monitoring-grafana -o jsonpath='{.data.admin-password}' | base64 -d ; echo

# Open the dashboard
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
```

**What should happen:**
- You'll get a password (write it down)
- The dashboard will open in your web browser
- You'll see graphs and charts showing system performance
- You'll see database performance metrics

**What to check:** 
- Dashboard loads without errors
- You can see graphs with data
- Database metrics show healthy status
- No error messages in the dashboard

### Step 6: Clean Up When Done

**What we're doing:** Removing the test environment to stop paying for it.

**Why we're doing this:** Cloud nodes and databases cost money, so we want to turn them off when we're done testing.

**Commands to run:**
```bash
./postgresql-testing/phase1-cleanup.sh
```

**What should happen:**
- Script will ask if you want to keep or delete the nodes and database
- Choose "delete" to save money
- Nodes and database will be removed from your cloud account

**What to check:** Run `kubectl get nodes` - should show no nodes (or an error saying no cluster).

## What Each Test Does (All 19 Tests Explained)

### **Category 1: Basic Functionality Tests**

#### Test 1: Basic Installation
**What it does:** Checks if all the software installed correctly.
**Why it matters:** If software didn't install properly, nothing else will work.
**Expected result:** All software components are running.
**What you'll see:** Status messages showing "Running" for all components.

#### Test 2: Namespace Creation
**What it does:** Creates a test workspace to run our applications.
**Why it matters:** We need a clean space to test our security system.
**Expected result:** A new workspace is created successfully.
**What you'll see:** Confirmation that the namespace was created.

#### Test 3: Pod Creation
**What it does:** Creates a simple test application (like a website).
**Why it matters:** We need applications to test our security rules against.
**Expected result:** The test application starts successfully.
**What you'll see:** The application shows as "Running" status.

### **Category 2: Policy Enforcement Tests**

#### Test 4: Policy Enforcement (Blocking)
**What it does:** Creates a test application that breaks security rules and sees if Kyverno catches it.
**Why it matters:** This proves that the security guard is actually working.
**Expected result:** Kyverno should block the bad application and create a report.
**What you'll see:** The bad application gets rejected with an error message.

#### Test 5: Policy Enforcement (Allowing)
**What it does:** Creates a test application that follows security rules.
**Why it matters:** We need to make sure good applications aren't blocked.
**Expected result:** The good application should be allowed to run.
**What you'll see:** The application starts successfully without errors.

#### Test 6: Policy Update
**What it does:** Changes a security rule and sees if the system picks up the change.
**Why it matters:** Rules need to be updated in real-world use.
**Expected result:** The system should apply the new rule immediately.
**What you'll see:** Applications behave differently after the rule change.

### **Category 3: Monitoring Tests**

#### Test 7: Metrics Collection
**What it does:** Checks if the system is collecting performance data.
**Why it matters:** We need data to understand how well the system is working.
**Expected result:** Performance data should be available.
**What you'll see:** Numbers and statistics in the monitoring dashboard.

#### Test 8: Dashboard Access
**What it does:** Verifies that the dashboard is collecting and displaying information.
**Why it matters:** We need to see how the system is performing in real-time.
**Expected result:** Dashboard should show graphs with data.
**What you'll see:** Charts and graphs with real-time data.

#### Test 9: Alert Generation
**What it does:** Tests if the system can send alerts when problems occur.
**Why it matters:** We need to know immediately when something goes wrong.
**Expected result:** Alerts should be generated for security violations.
**What you'll see:** Alert messages or notifications.

### **Category 4: Performance Tests**

#### Test 10: Response Time
**What it does:** Measures how fast the system can process security checks.
**Why it matters:** In real-world use, the system needs to be fast enough.
**Expected result:** Response times should be reasonable (under a few seconds).
**What you'll see:** Timing measurements in the test output.

#### Test 11: Resource Usage
**What it does:** Checks how much computer power the system is using.
**Why it matters:** We need to know if the system is efficient.
**Expected result:** Resource usage should be reasonable.
**What you'll see:** CPU and memory usage statistics.

#### Test 12: Concurrent Operations
**What it does:** Tests how the system handles multiple requests at the same time.
**Why it matters:** Real-world systems need to handle many users.
**Expected result:** System should handle multiple requests without problems.
**What you'll see:** All requests complete successfully.

### **Category 5: PostgreSQL Storage Tests**

#### Test 13: Database Connection
**What it does:** Checks if the Reports Server can connect to the PostgreSQL database.
**Why it matters:** If the database connection doesn't work, reports won't be stored.
**Expected result:** Database connection should be successful.
**What you'll see:** Connection success messages in the logs.

#### Test 14: Data Storage
**What it does:** Tests if security reports are being stored in the PostgreSQL database.
**Why it matters:** We need to make sure reports are saved properly.
**Expected result:** Reports should be stored in the database.
**What you'll see:** Database queries show stored reports.

#### Test 15: Data Retrieval
**What it does:** Tests if we can read back the stored security reports from the database.
**Why it matters:** We need to access historical data for analysis.
**Expected result:** Stored data should be retrievable.
**What you'll see:** Reports can be viewed and searched.

### **Category 6: API Functionality Tests**

#### Test 16: API Endpoints
**What it does:** Tests if the system's programming interface is working.
**Why it matters:** Other applications need to communicate with our system.
**Expected result:** All API endpoints should respond correctly.
**What you'll see:** API calls return proper responses.

#### Test 17: Data Format
**What it does:** Checks if the system provides data in the correct format.
**Why it matters:** Other systems need to understand our data.
**Expected result:** Data should be in standard formats (JSON, etc.).
**What you'll see:** Properly formatted data in responses.

#### Test 18: Authentication
**What it does:** Tests if the system properly controls who can access it.
**Why it matters:** Security systems need to be secure themselves.
**Expected result:** Only authorized users should be able to access the system.
**What you'll see:** Access is granted or denied appropriately.

### **Category 7: Failure Recovery Tests**

#### Test 19: System Recovery
**What it does:** Simulates a system failure and tests if it can recover.
**Why it matters:** Systems need to be resilient to failures.
**Expected result:** System should recover automatically from failures.
**What you'll see:** System continues working after simulated failures.

## Understanding Test Results

### **Test Categories Summary**

| Category | Tests | Purpose | What Success Looks Like |
|----------|-------|---------|-------------------------|
| **Basic Functionality** | 1-3 | Make sure everything is installed and running | All components show "Running" status |
| **Policy Enforcement** | 4-6 | Verify security rules work correctly | Bad apps blocked, good apps allowed |
| **Monitoring** | 7-9 | Ensure we can see what's happening | Dashboard shows data, alerts work |
| **Performance** | 10-12 | Check speed and efficiency | Fast response times, reasonable resource usage |
| **PostgreSQL Storage** | 13-15 | Verify database operations work | Database connects, stores, and retrieves data |
| **API Functionality** | 16-18 | Test programming interface | API calls work, data formats correct |
| **Failure Recovery** | 19 | Ensure system is resilient | System recovers from failures |

### **What Each Test Result Means**

#### **PASS Results**
- ✅ **Test completed successfully** - Everything worked as expected
- ✅ **System is healthy** - This part of the system is working correctly
- ✅ **Ready for next phase** - You can proceed with confidence

#### **FAIL Results**
- ❌ **Something didn't work** - The test found a problem
- ❌ **Investigation needed** - You should look into what went wrong
- ❌ **May need fixing** - The system might need configuration changes

#### **SKIP Results**
- ⏭️ **Test was skipped** - This test wasn't run (maybe not applicable)
- ⏭️ **Normal behavior** - Some tests are optional or conditional
- ⏭️ **No action needed** - This is usually fine

### **Expected Test Outcomes**

#### **Phase 1 (Small Test) - What You Should See**
- **Most tests should PASS** (15-19 out of 19)
- **Database tests must PASS** - These are critical for PostgreSQL setup
- **A few tests might FAIL** - This is normal for some tests
- **Performance tests should be reasonable** - Not too slow
- **All basic functionality should work** - Core features must pass

#### **What's Normal vs. What's a Problem**

**Normal (Don't Worry):**
- 1-3 tests fail (some tests are designed to fail)
- Performance tests show reasonable times
- Basic functionality all passes
- Database connection is stable
- Monitoring shows some data

**Problem (Investigate):**
- More than 5 tests fail
- Database connection fails
- All performance tests are very slow
- Basic functionality fails
- No data in monitoring

### **How to Interpret Your Results**

#### **Excellent Results (15-19 PASS)**
- 🎉 **System is working great!**
- 🚀 **Ready to proceed to Phase 2**
- 💰 **Good investment - system is reliable**

#### **Good Results (10-14 PASS)**
- 👍 **System is mostly working**
- 🔍 **Check the failed tests**
- 🛠️ **May need minor adjustments**

#### **Poor Results (Less than 10 PASS)**
- ⚠️ **System has significant issues**
- 🔧 **Needs troubleshooting**
- 📋 **Don't proceed until fixed**

## Common Problems and Solutions

### Problem: "Database connection failed"
**What it means:** The Reports Server can't connect to the PostgreSQL database.
**Solution:** Check RDS security groups and network connectivity.

### Problem: "RDS instance not available"
**What it means:** The database isn't running or accessible.
**Solution:** Check RDS status in AWS console, verify credentials.

### Problem: "Reports not being stored"
**What it means:** Data isn't being saved to the database.
**Solution:** Check Reports Server logs, verify database permissions.

### Problem: "High database CPU usage"
**What it means:** The database is working too hard.
**Solution:** Consider scaling up the RDS instance size.

### Problem: "Slow query performance"
**What it means:** Database queries are taking too long.
**Solution:** Check for missing indexes, optimize queries.

## What to Do Next

### If Phase 1 Works Well
**Congratulations!** Your PostgreSQL-based system is working correctly. You can now:

1. **Proceed to Phase 2** - Test with more nodes and larger database (~$179/month)
2. **Customize the system** - Modify it for your specific needs
3. **Plan for production** - Use what you learned to plan real-world deployment

### If Phase 1 Has Problems
**Don't worry!** This is why we test small first. You can:

1. **Fix the problems** - Use the troubleshooting section above
2. **Try again** - Run the tests again after fixing issues
3. **Ask for help** - Get support from the community or documentation

## Cost Breakdown

### Phase 1 Costs (What You're Paying For)
- **EKS Control Plane**: ~$73/month (the management computer)
- **2 Small Nodes**: ~$30/month (the nodes running your tests)
- **RDS PostgreSQL (db.t3.micro)**: ~$15/month (the professional database)
- **Storage**: ~$3/month (space to store data)
- **Total**: ~$121/month

### How to Save Money
- **Use Spot instances** - Can save 50-70% (but nodes can be taken away)
- **Turn off when not testing** - Only pay for what you use
- **Use smaller RDS instances** - If your tests don't need much database power
- **Clean up properly** - Make sure to delete everything when done

## Success Checklist

Before you consider Phase 1 complete, make sure you have:

- ✅ **All tools installed** and working
- ✅ **AWS account configured** and accessible
- ✅ **Test environment created** successfully
- ✅ **Database connection working** (no connection errors)
- ✅ **All tests passing** (or most of them)
- ✅ **Dashboard working** and showing data
- ✅ **No major errors** in the system
- ✅ **Performance acceptable** for your needs
- ✅ **Costs reasonable** for your budget

## Next Steps

### Phase 2: Medium Test
- **What**: Test with more nodes and larger database (~800 applications)
- **Cost**: ~$179/month
- **Purpose**: See how the system performs under more load
- **When**: After Phase 1 is working perfectly

### Phase 3: Large Test
- **What**: Test with many nodes and large database (~12,000 applications)
- **Cost**: ~$798/month
- **Purpose**: Validate the system for real-world use
- **When**: After Phase 2 is working well

## Getting Help

If you get stuck:

1. **Check the troubleshooting section** above
2. **Look at the comprehensive guide** (COMPREHENSIVE_GUIDE.md)
3. **Check the logs** - Run `kubectl logs` to see what's happening
4. **Check database logs** - Look at RDS logs in AWS console
5. **Ask the community** - Many people have gone through this before

## Summary

This simple guide walked you through:
1. **Setting up your tools** - Getting ready to work with cloud nodes and databases
2. **Creating a test environment** - Building a small test system with professional database
3. **Running tests** - Making sure everything works correctly, especially database operations
4. **Looking at results** - Understanding how well the system performs
5. **Cleaning up** - Stopping the costs when you're done

The goal is to test your security system with a professional database safely and cheaply before investing in a bigger setup. Take your time, follow the steps carefully, and don't hesitate to ask for help if you need it!

---

**Remember**: Start small, test thoroughly, and scale up only when you're confident everything works. This approach saves money and reduces risk! 🎯
