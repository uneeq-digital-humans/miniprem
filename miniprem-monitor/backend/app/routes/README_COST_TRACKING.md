# Cost Tracking API Documentation

## Overview

Enhanced cost tracking API for Kubernetes clusters with comprehensive cost analysis, optimization recommendations, and budget tracking.

## Endpoint

```
GET /api/kubernetes/costs/enhanced
```

## Supported Cloud Providers

- **AWS EKS**: Elastic Kubernetes Service
- **Azure AKS**: Azure Kubernetes Service
- **GCP GKE**: Google Kubernetes Engine

## Data Source

**Phase 1 (Current)**: Hardcoded pricing tables
- Immediate availability
- No cloud API credentials required
- Based on standard pricing (us-east-1, East US, us-east1)
- Fast and reliable

**Phase 2 (Future)**: Cloud billing API integration
- AWS Cost Explorer API (boto3)
- Azure Cost Management API
- GCP Cloud Billing API
- Requires credentials configuration

## Response Format

```json
{
  "success": true,
  "provider": "eks",
  "cluster_name": "miniprem-eks-cluster",
  "current_period": {
    "start_date": "2025-10-01",
    "end_date": "2025-10-16",
    "total_cost": 5425.50,
    "daily_average": 338.47,
    "projected_monthly": 10154.10
  },
  "cost_breakdown": {
    "compute": {
      "cost": 8960.00,
      "percentage": 88.5
    },
    "networking": {
      "cost": 250.00,
      "percentage": 2.5
    },
    "storage": {
      "cost": 200.00,
      "percentage": 2.0
    },
    "monitoring": {
      "cost": 50.00,
      "percentage": 0.5
    },
    "cluster_management": {
      "cost": 73.00,
      "percentage": 0.7
    }
  },
  "node_pool_costs": [
    {
      "name": "rennygpu",
      "instance_type": "g5.4xlarge",
      "current_nodes": 10,
      "hourly_cost": 16.24,
      "daily_cost": 389.76,
      "monthly_projection": 11858.00,
      "cost_per_node_hourly": 1.624
    }
  ],
  "cost_trends": {
    "last_7_days": [320.5, 340.2, 360.8, 355.1, 365.4, 370.2, 338.5],
    "last_30_days": [...],
    "highest_day": {
      "date": "2025-10-12",
      "cost": 425.50
    },
    "lowest_day": {
      "date": "2025-10-06",
      "cost": 298.75
    },
    "average_daily": 345.80
  },
  "optimization_recommendations": [
    {
      "type": "reserved_instances",
      "potential_savings": 3240.00,
      "savings_percentage": 30,
      "description": "Purchase 1-year reserved instances for production workloads. Save up to 30% on compute costs ($3,240.00/month) with predictable pricing.",
      "priority": "high"
    },
    {
      "type": "auto_scaling",
      "potential_savings": 3070.00,
      "savings_percentage": 30,
      "description": "Implement time-based auto-scaling to shut down non-production resources during off-hours. Save $3,070.00/month by running clusters only during business hours (8am-6pm Mon-Fri).",
      "priority": "high"
    }
  ],
  "budget_status": {
    "monthly_budget": 12000.00,
    "current_spend": 5425.50,
    "projected_spend": 10154.10,
    "remaining": 6574.50,
    "utilization_percentage": 45.2,
    "on_track": true,
    "days_into_month": 16
  },
  "data_source": "hardcoded_pricing",
  "pricing_region": "us-east-1",
  "timestamp": "2025-10-16T14:30:00.000Z"
}
```

## Error Response Format

```json
{
  "success": false,
  "provider": "unknown",
  "cluster_name": "unknown",
  "error": "No current kubectl context: context not set",
  "error_type": "no_kubectl_context",
  "timestamp": "2025-10-16T14:30:00.000Z"
}
```

## Error Types

| Error Type | HTTP Status | Description |
|------------|-------------|-------------|
| `no_kubectl_context` | 503 | No kubectl context configured |
| `provider_detection_failed` | 400 | Unable to detect cloud provider |
| `no_node_pools` | 404 | No node pools found in cluster |
| `kubectl_command_failed` | 502 | kubectl command execution failed |
| `server_error` | 500 | Internal server error |

## Pricing Tables

### AWS EKS (us-east-1)

#### GPU Instances
| Instance Type | Hourly Rate | Monthly (730h) |
|---------------|-------------|----------------|
| g5.xlarge | $1.006 | $734.38 |
| g5.2xlarge | $1.212 | $884.76 |
| g5.4xlarge | $1.624 | $1,185.52 |
| g5.8xlarge | $2.448 | $1,787.04 |
| g5.12xlarge | $4.896 | $3,574.08 |
| p3.2xlarge | $3.06 | $2,233.80 |

#### General Purpose
| Instance Type | Hourly Rate | Monthly (730h) |
|---------------|-------------|----------------|
| t3.medium | $0.0416 | $30.37 |
| t3.large | $0.0832 | $60.74 |
| t3.xlarge | $0.1664 | $121.47 |
| m5.large | $0.096 | $70.08 |
| m5.xlarge | $0.192 | $140.16 |

#### Infrastructure Services
| Service | Cost Type | Rate |
|---------|-----------|------|
| NAT Gateway | Hourly | $0.045 |
| Network Load Balancer | Hourly | $0.0225 |
| EBS gp3 Storage | Per GB/month | $0.08 |
| EKS Cluster Management | Hourly | $0.10 ($73/month) |
| CloudWatch | Estimated/month | $50 |

### Azure AKS (East US)

#### GPU Instances
| Instance Type | Hourly Rate | Monthly (730h) |
|---------------|-------------|----------------|
| Standard_NC4as_T4_v3 | $0.526 | $383.98 |
| Standard_NC8as_T4_v3 | $1.052 | $767.96 |
| Standard_NC16as_T4_v3 | $2.104 | $1,535.92 |
| Standard_NC6s_v3 | $3.06 | $2,233.80 |

#### General Purpose
| Instance Type | Hourly Rate | Monthly (730h) |
|---------------|-------------|----------------|
| Standard_B2s | $0.0416 | $30.37 |
| Standard_B4ms | $0.166 | $121.18 |
| Standard_D2s_v3 | $0.096 | $70.08 |
| Standard_D4s_v3 | $0.192 | $140.16 |

#### Infrastructure Services
| Service | Cost Type | Rate |
|---------|-----------|------|
| NAT Gateway | Hourly | $0.045 |
| Load Balancer Standard | Hourly | $0.025 |
| Managed Disk Premium SSD | Per GB/month | $0.135 |
| Azure Monitor | Estimated/month | $75 |

### GCP GKE (us-east1)

#### GPU Instances
| Instance Type | Hourly Rate | Monthly (730h) |
|---------------|-------------|----------------|
| n1-standard-4 + T4 GPU | $0.70 | $511.00 |
| n1-standard-8 + T4 GPU | $0.73 | $532.90 |
| n1-standard-4 + V100 GPU | $2.83 | $2,065.90 |
| a2-highgpu-1g (A100) | $3.67 | $2,679.10 |

#### General Purpose
| Instance Type | Hourly Rate | Monthly (730h) |
|---------------|-------------|----------------|
| n1-standard-1 | $0.0475 | $34.68 |
| n1-standard-2 | $0.095 | $69.35 |
| n1-standard-4 | $0.19 | $138.70 |
| n1-standard-8 | $0.38 | $277.40 |

#### Infrastructure Services
| Service | Cost Type | Rate |
|---------|-----------|------|
| Cloud NAT | Hourly | $0.045 |
| Load Balancer | Hourly | $0.025 |
| Persistent Disk SSD | Per GB/month | $0.17 |
| GKE Cluster Management | Hourly | $0.10 ($73/month) |
| Cloud Logging | Estimated/month | $60 |

## Optimization Recommendations

### 1. Reserved Instances (30-40% savings)
- **Applies to**: Compute costs > $3,000/month
- **Savings**: 30-40% monthly
- **Commitment**: 1 or 3 years
- **Best for**: Production workloads with predictable usage

### 2. Auto-Scaling (20-40% savings)
- **Applies to**: 24/7 clusters with variable workloads
- **Savings**: 30-40% monthly
- **Implementation**: Time-based scaling (business hours only)
- **Best for**: Dev/test environments

### 3. Spot Instances (50-70% savings)
- **Applies to**: Fault-tolerant workloads
- **Savings**: 50-70% for spot-eligible resources
- **Best for**: Batch jobs, CI/CD, testing

### 4. GPU Time-Slicing (30-50% savings)
- **Applies to**: GPU workloads
- **Savings**: 40% by running 2-4 pods per GPU
- **Best for**: Rendering, inference, ML workloads

### 5. Right-Sizing (10-20% savings)
- **Applies to**: All workloads
- **Savings**: 15% average
- **Method**: Match instance types to actual CPU/memory usage

## Budget Tracking

Configure monthly budget to track spending:

```python
from app.services.cost_calculator import cost_calculator_service

# Set monthly budget (USD)
cost_calculator_service.set_monthly_budget(12000.00)
```

Budget status includes:
- Current month-to-date spend
- Projected end-of-month spend
- Remaining budget
- Utilization percentage
- On-track status (spending vs. budget timeline)

## Testing

### cURL Example

```bash
# Test with EKS cluster
curl -X GET http://localhost:8000/api/kubernetes/costs/enhanced \
  -H "Content-Type: application/json" | jq

# Expected response: 200 OK with cost data
```

### Python Example

```python
import requests
import json

response = requests.get('http://localhost:8000/api/kubernetes/costs/enhanced')
cost_data = response.json()

if cost_data['success']:
    print(f"Cluster: {cost_data['cluster_name']}")
    print(f"Provider: {cost_data['provider']}")
    print(f"Projected Monthly Cost: ${cost_data['current_period']['projected_monthly']:,.2f}")

    # Print optimization recommendations
    print("\nOptimization Recommendations:")
    for rec in cost_data['optimization_recommendations']:
        print(f"  - {rec['type']}: ${rec['potential_savings']:,.2f}/month ({rec['savings_percentage']}%)")
        print(f"    {rec['description']}")
else:
    print(f"Error: {cost_data['error']}")
```

## Implementation Details

### Cost Calculation Flow

1. **Provider Detection**: Detect cloud provider from kubectl context
2. **Node Pool Discovery**: Get node pools and instance types from kubectl
3. **Pricing Lookup**: Match instance types to hardcoded pricing tables
4. **Infrastructure Costs**: Calculate NAT, Load Balancer, Storage, Monitoring
5. **Cost Breakdown**: Categorize costs (compute, networking, storage, monitoring)
6. **Trend Generation**: Simulate historical trends (Phase 1) or fetch from API (Phase 2)
7. **Optimization Analysis**: Generate recommendations based on cost patterns
8. **Budget Tracking**: Compare against monthly budget (if configured)

### Caching Strategy

- **Cost metrics**: 5-minute cache for real-time costs
- **Historical trends**: 1-hour cache (simulated data refreshes less frequently)
- **Cluster changes**: Cache invalidation on scale events

## Future Enhancements (Phase 2)

### Cloud Billing API Integration

#### AWS Cost Explorer
```python
import boto3

ce = boto3.client('ce')
response = ce.get_cost_and_usage(
    TimePeriod={'Start': '2025-10-01', 'End': '2025-10-16'},
    Granularity='DAILY',
    Metrics=['UnblendedCost']
)
```

#### Azure Cost Management
```python
from azure.mgmt.costmanagement import CostManagementClient

cost_client = CostManagementClient(credentials, subscription_id)
query_result = cost_client.query.usage(scope, query_definition)
```

#### GCP Cloud Billing
```python
from google.cloud import billing_v1

client = billing_v1.CloudBillingClient()
response = client.list_services()
```

### Configuration

Add opt-in flag to enable cloud API integration:

```python
# config.py
ENABLE_CLOUD_BILLING_API = False  # Set to True to enable

# AWS credentials (for Cost Explorer)
AWS_ACCESS_KEY_ID = "..."
AWS_SECRET_ACCESS_KEY = "..."

# Azure credentials (for Cost Management)
AZURE_SUBSCRIPTION_ID = "..."
AZURE_TENANT_ID = "..."

# GCP credentials (for Cloud Billing)
GOOGLE_APPLICATION_CREDENTIALS = "/path/to/service-account.json"
```
