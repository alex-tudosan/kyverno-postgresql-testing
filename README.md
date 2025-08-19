# Kyverno n4k + Reports Server: PostgreSQL Testing Framework

## 🎯 Overview

This repository provides a **production-ready, PostgreSQL-based testing framework** for Kyverno n4k (enhanced Kyverno) with Reports Server. It uses AWS RDS PostgreSQL instead of etcd for better scalability, reliability, and performance.

## 🚀 Quick Start

```bash
# 1. Install prerequisites
brew install awscli eksctl kubectl helm jq

# 2. Configure AWS
aws configure
export AWS_REGION=us-west-2

# 3. Run Phase 1 (recommended starting point)
./phase1-setup.sh
./phase1-test-cases.sh
./phase1-monitor.sh
./phase1-cleanup.sh
```

## 📖 Documentation

### **📋 [COMPREHENSIVE_GUIDE.md](COMPREHENSIVE_GUIDE.md)** - **Complete Technical Guide**

This is your **single source of truth** for everything you need to know:
- ✅ **Quick Start** - Phase 1 automated setup
- ✅ **Testing Strategy** - Phased approach (Phase 1, 2, 3)
- ✅ **Manual Setup** - Step-by-step instructions
- ✅ **Monitoring** - Metrics and dashboards
- ✅ **Troubleshooting** - Common issues and solutions
- ✅ **Cost Estimation** - Monthly costs for each phase
- ✅ **Load Testing** - Production-scale testing scripts

### **📖 [SIMPLE_GUIDE.md](SIMPLE_GUIDE.md)** - **Plain Language Guide**

Perfect for beginners or anyone who wants to understand **what, why, and how**:
- 🎯 **What we're doing** - Simple explanations of each step
- 🤔 **Why we're doing it** - Clear reasoning for every action
- ✅ **What should happen** - Expected results for each step
- 🔍 **What to check** - How to verify everything is working
- 🛠️ **Common problems** - Simple solutions to typical issues

## 📊 Testing Phases

| Phase | Purpose | Infrastructure | Estimated Cost/Month |
|-------|---------|----------------|---------------------|
| **Phase 1** | Requirements gathering & validation | EKS (2 nodes) + RDS (db.t3.micro) | ~$121 |
| **Phase 2** | Performance validation | EKS (5 nodes) + RDS (db.t3.small) | ~$179 |
| **Phase 3** | Production-scale testing | EKS (12 nodes) + RDS (db.r5.large) | ~$798 |

## 🏗️ Architecture

```
Kubernetes Cluster (EKS)
├── Kyverno n4k (Policy Engine)
│   └── Generates policy reports
├── Reports Server (Dedicated Service)
│   └── Stores reports in AWS RDS PostgreSQL
└── AWS RDS PostgreSQL
    └── Managed database for report storage
```

## 📁 Repository Structure

```
kyverno-postgresql-testing/
├── 📖 README.md                           # This file
├── 📖 reports-server-saas-requirements.md # Requirements document
├── 📋 COMPREHENSIVE_GUIDE.md              # Complete technical guide
├── 📖 SIMPLE_GUIDE.md                     # Plain language guide
├── 🚀 phase1-setup.sh                     # Automated setup
├── 🧪 phase1-test-cases.sh                # 19 comprehensive tests
├── 📊 phase1-monitor.sh                   # Real-time monitoring
├── 🧹 phase1-cleanup.sh                   # Complete cleanup
├── 📊 kyverno-servicemonitor.yaml         # ServiceMonitor for Kyverno metrics
├── 📊 reports-server-servicemonitor.yaml  # ServiceMonitor for Reports Server metrics
├── 🧪 test-violations-pod.yaml            # Test pod that violates security policies
└── 📈 kyverno-dashboard.json              # Grafana dashboard configuration
```

## 🎯 Key Features

- ✅ **Production-ready architecture** with AWS RDS PostgreSQL
- ✅ **Comprehensive testing** with 19 test cases across 7 categories
- ✅ **Real-time monitoring** with RDS metrics integration
- ✅ **Cost-effective approach** with phased testing strategy
- ✅ **Automated workflows** for setup, testing, and cleanup
- ✅ **Enhanced documentation** for all user types

## 🔗 References

- [Reports Server Documentation](https://kyverno.github.io/reports-server/)
- [Kyverno Documentation](https://kyverno.io/docs/)
- [AWS RDS Monitoring](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_Monitoring.html)

