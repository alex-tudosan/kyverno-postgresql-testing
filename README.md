# Kyverno n4k + Reports Server (PostgreSQL) Testing Suite

A comprehensive testing framework for Kyverno n4k with Reports Server using **AWS RDS PostgreSQL** for production-ready policy management and reporting.

## 🚀 Quick Start

### Prerequisites
```bash
# Install required tools
brew install awscli eksctl kubectl helm jq

# Configure AWS SSO
aws sso login --profile devtest-sso
```

### Phase 1 Testing (Recommended First Step)
```bash
# Create test environment (15-20 minutes)
./phase1-setup.sh

# Run comprehensive tests (optional)
./phase1-test-cases.sh

# Monitor system health (optional)
./phase1-monitor.sh

# Clean up resources when done
./phase1-cleanup.sh
```

## 📖 Documentation

- **[COMPREHENSIVE_GUIDE.md](COMPREHENSIVE_GUIDE.md)** - Complete technical guide with troubleshooting
- **[EXECUTION_GUIDE.md](EXECUTION_GUIDE.md)** - Step-by-step execution commands for all phases

## 🆕 Latest Improvements

### **Enhanced Script Robustness**
- **🕒 Smart Timeouts** - Progress bars and configurable timeouts for all operations
- **🔄 Auto-Retry Logic** - Exponential backoff for transient failures
- **🏷️ Timestamped Resources** - Automatic conflict prevention with unique names
- **🧹 Better Cleanup** - Force deletion and comprehensive resource verification
- **📊 Real-time Progress** - Visual progress bars and timestamped logging
- **🛡️ Error Prevention** - Pre-flight checks and graceful failure handling

### **Key Features**
- **PostgreSQL-based Reports Server** - Production-ready external database
- **Phased testing approach** - Scale from small to production workloads
- **Comprehensive monitoring** - Prometheus + Grafana integration
- **Automated testing** - 19 test cases covering all scenarios
- **Cost optimization** - Resource cleanup and cost tracking
- **Secure secrets management** - Kubernetes secrets for sensitive data
- **Latest Reports Server version** - Using v0.2.3 from Nirmata fork

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   EKS Cluster   │    │   AWS RDS       │    │   Monitoring    │
│                 │    │   PostgreSQL    │    │                 │
│ ┌─────────────┐ │    │                 │    │ ┌─────────────┐ │
│ │   Kyverno   │ │◄──►│   Database      │    │ │ Prometheus  │ │
│ │   n4k       │ │    │   (External)    │    │ │ + Grafana   │ │
│ └─────────────┘ │    └─────────────────┘    │ └─────────────┘ │
│ ┌─────────────┐ │                           └─────────────────┘
│ │   Reports   │ │
│ │   Server    │ │
│ └─────────────┘ │
└─────────────────┘
```

## 📁 File Structure

```
├── README.md                           # This file
├── COMPREHENSIVE_GUIDE.md              # Complete technical guide
├── EXECUTION_GUIDE.md                  # Step-by-step execution guide
├── phase1-setup.sh                     # Phase 1 automation (enhanced)
├── phase1-test-cases.sh                # 19 comprehensive tests
├── phase1-monitor.sh                   # Real-time monitoring
├── phase1-cleanup.sh                   # Resource cleanup (enhanced)
├── create-secrets.sh                   # Secrets management
├── baseline-policies.yaml              # Test security policies
├── kyverno-servicemonitor.yaml         # Prometheus monitoring
├── reports-server-servicemonitor.yaml  # Reports Server monitoring
└── kyverno-dashboard.json              # Grafana dashboard
```

## 🧪 Testing Phases

| Phase | Purpose | Resources | Cost/Month |
|-------|---------|-----------|------------|
| **Phase 1** | Requirements & validation | 2 nodes + db.t3.micro | ~$150 |
| **Phase 2** | Performance validation | 5 nodes + db.t3.small | ~$460 |
| **Phase 3** | Production-scale testing | 12 nodes + db.r5.large | ~$2,800 |

## 🔧 Troubleshooting

**Common Issues:**
- **Database connection problems** - Check Helm parameters and pod environment variables
- **Resource conflicts** - Scripts now use timestamps to prevent conflicts
- **Cleanup failures** - Enhanced cleanup with force deletion and better error handling
- **Timeout issues** - Improved timeout handling with progress indicators

**For detailed troubleshooting:** See [COMPREHENSIVE_GUIDE.md](COMPREHENSIVE_GUIDE.md#troubleshooting)

## 💰 Cost Management

- **Automatic cleanup** prevents ongoing charges
- **Cost tracking** shows monthly savings
- **Resource optimization** for each testing phase
- **Clear cost breakdown** for all components

## 🚨 Important Notes

- **AWS SSO required** - Use `devtest-sso` profile
- **Region: us-west-1** - All resources created in N. California
- **Manual cleanup** - If automated cleanup fails, see comprehensive guide
- **Latest version** - Always use Reports Server v0.2.3 from Nirmata fork

## 🤝 Contributing

1. Test with the latest improvements
2. Report issues with detailed logs
3. Suggest enhancements for robustness
4. Update documentation as needed

---

**Ready to test?** Start with [Phase 1](COMPREHENSIVE_GUIDE.md#quick-start-phase-1) for a complete validation of your setup!

