# PostgreSQL-Based Reports Server Testing

This folder contains the PostgreSQL-based version of the Kyverno n4k + Reports Server testing setup using AWS RDS instead of etcd.

## Architecture

```
Kubernetes Cluster
├── Kyverno n4k (Policy Engine)
│   └── Generates policy reports
├── Reports Server (Dedicated Service)
│   └── Stores reports in AWS RDS PostgreSQL
└── AWS RDS PostgreSQL
    └── Managed database for report storage
```

## Key Differences from etcd Version

- **Storage**: AWS RDS PostgreSQL instead of etcd
- **Scalability**: Better for production workloads
- **Management**: AWS handles database maintenance
- **Performance**: Optimized for relational data queries
- **Cost**: Additional RDS costs but better scalability

## Testing Phases

- **Phase 1**: Small-scale testing with RDS db.t3.micro
- **Phase 2**: Medium-scale testing with RDS db.t3.small
- **Phase 3**: Production-scale testing with RDS db.r5.large
