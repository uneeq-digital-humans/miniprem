"""
Cost Calculator Service

Calculates cloud infrastructure costs using hardcoded pricing tables for EKS, AKS, and GKE.
Provides historical trends, optimization recommendations, and budget tracking.

Phase 1: Hardcoded pricing (immediate)
Phase 2: Cloud billing API integration (optional)
"""

import logging
from typing import Dict, List, Tuple, Optional
from datetime import datetime, timedelta
from collections import defaultdict

from ..models.cost_models import (
    NodePoolCost,
    CostBreakdownItem,
    OptimizationRecommendation,
    BudgetStatus,
    CostTrends,
    CostTrendDay,
    CurrentPeriod,
    InfrastructureCost
)

logger = logging.getLogger(__name__)


# ============================================================================
# PRICING TABLES - Hardcoded Instance Pricing (USD per hour)
# ============================================================================

# AWS EKS Pricing (us-east-1)
AWS_INSTANCE_PRICING = {
    # GPU Instances
    "g5.xlarge": 1.006,
    "g5.2xlarge": 1.212,
    "g5.4xlarge": 1.624,
    "g5.8xlarge": 2.448,
    "g5.12xlarge": 4.896,
    "g5.16xlarge": 4.096,
    "g5.24xlarge": 9.792,
    "g5.48xlarge": 16.288,
    "p3.2xlarge": 3.06,
    "p3.8xlarge": 12.24,
    "p3.16xlarge": 24.48,
    "p4d.24xlarge": 32.77,

    # General Purpose
    "t3.micro": 0.0104,
    "t3.small": 0.0208,
    "t3.medium": 0.0416,
    "t3.large": 0.0832,
    "t3.xlarge": 0.1664,
    "t3.2xlarge": 0.3328,
    "m5.large": 0.096,
    "m5.xlarge": 0.192,
    "m5.2xlarge": 0.384,
    "m5.4xlarge": 0.768,
    "m5.8xlarge": 1.536,

    # Compute Optimized
    "c5.large": 0.085,
    "c5.xlarge": 0.17,
    "c5.2xlarge": 0.34,
    "c5.4xlarge": 0.68,
    "c5.9xlarge": 1.53,
}

# Azure AKS Pricing (East US)
AZURE_INSTANCE_PRICING = {
    # GPU Instances
    "Standard_NC4as_T4_v3": 0.526,
    "Standard_NC8as_T4_v3": 1.052,
    "Standard_NC16as_T4_v3": 2.104,
    "Standard_NC64as_T4_v3": 8.416,
    "Standard_NC6s_v3": 3.06,
    "Standard_NC12s_v3": 6.12,
    "Standard_NC24s_v3": 12.24,

    # General Purpose
    "Standard_B2s": 0.0416,
    "Standard_B4ms": 0.166,
    "Standard_D2s_v3": 0.096,
    "Standard_D4s_v3": 0.192,
    "Standard_D8s_v3": 0.384,
    "Standard_D16s_v3": 0.768,
    "Standard_DS2_v2": 0.107,
    "Standard_DS3_v2": 0.214,
    "Standard_DS4_v2": 0.428,

    # Compute Optimized
    "Standard_F2s_v2": 0.085,
    "Standard_F4s_v2": 0.169,
    "Standard_F8s_v2": 0.338,
    "Standard_F16s_v2": 0.677,
}

# GCP GKE Pricing (us-east1)
GCP_INSTANCE_PRICING = {
    # GPU Instances (machine type + GPU cost)
    "n1-standard-4-tesla-t4": 0.35 + 0.35,  # n1-standard-4 + 1x T4 GPU
    "n1-standard-8-tesla-t4": 0.38 + 0.35,
    "n1-standard-16-tesla-t4": 0.76 + 0.35,
    "n1-standard-4-tesla-v100": 0.35 + 2.48,  # n1-standard-4 + 1x V100 GPU
    "n1-standard-8-tesla-v100": 0.38 + 2.48,
    "a2-highgpu-1g": 3.67,  # A100 40GB
    "a2-highgpu-2g": 7.35,

    # General Purpose
    "n1-standard-1": 0.0475,
    "n1-standard-2": 0.095,
    "n1-standard-4": 0.19,
    "n1-standard-8": 0.38,
    "n1-standard-16": 0.76,
    "n2-standard-2": 0.097,
    "n2-standard-4": 0.194,
    "n2-standard-8": 0.388,

    # Compute Optimized
    "c2-standard-4": 0.2088,
    "c2-standard-8": 0.4176,
    "c2-standard-16": 0.8352,
}

# Infrastructure Service Pricing
AWS_INFRASTRUCTURE_COSTS = {
    "nat_gateway_hourly": 0.045,
    "nat_gateway_per_gb": 0.045,
    "load_balancer_nlb_hourly": 0.0225,
    "load_balancer_alb_hourly": 0.0225,
    "ebs_gp3_per_gb_month": 0.08,
    "ebs_io2_per_gb_month": 0.125,
    "cloudwatch_metrics_per_1000": 0.30,
    "cloudwatch_logs_per_gb": 0.50,
    "eks_cluster_hourly": 0.10,
}

AZURE_INFRASTRUCTURE_COSTS = {
    "nat_gateway_hourly": 0.045,
    "load_balancer_basic": 0.0,  # Free
    "load_balancer_standard_hourly": 0.025,
    "managed_disk_premium_ssd_per_gb": 0.135,
    "managed_disk_standard_ssd_per_gb": 0.075,
    "azure_monitor_logs_per_gb": 2.30,
    "aks_cluster": 0.0,  # Free cluster management
}

GCP_INFRASTRUCTURE_COSTS = {
    "cloud_nat_gateway_hourly": 0.045,
    "cloud_nat_per_gb": 0.045,
    "load_balancer_forwarding_rule": 0.025,
    "persistent_disk_ssd_per_gb": 0.17,
    "persistent_disk_standard_per_gb": 0.04,
    "cloud_logging_per_gb": 0.50,
    "gke_cluster_hourly": 0.10,
}


class CostCalculatorService:
    """
    Calculate cloud infrastructure costs using hardcoded pricing tables.

    Supports AWS EKS, Azure AKS, and GCP GKE with comprehensive cost analysis
    including node pool costs, infrastructure costs, trends, and optimization
    recommendations.
    """

    def __init__(self):
        """Initialize cost calculator service."""
        self._cost_history: Dict[str, List[Tuple[datetime, float]]] = defaultdict(list)
        self._monthly_budget: Optional[float] = None

    def set_monthly_budget(self, budget: float) -> None:
        """
        Set monthly budget for cost tracking.

        Args:
            budget: Monthly budget in USD
        """
        self._monthly_budget = budget
        logger.info(f"Monthly budget set to ${budget:,.2f}")

    def get_instance_pricing(
        self,
        provider: str,
        instance_type: str
    ) -> float:
        """
        Get hourly pricing for an instance type.

        Args:
            provider: Cloud provider ('eks', 'aks', 'gke')
            instance_type: Instance type identifier

        Returns:
            Hourly cost in USD, or 0.0 if not found
        """
        pricing_map = {
            "eks": AWS_INSTANCE_PRICING,
            "aks": AZURE_INSTANCE_PRICING,
            "gke": GCP_INSTANCE_PRICING
        }

        pricing_table = pricing_map.get(provider, {})
        cost = pricing_table.get(instance_type, 0.0)

        if cost == 0.0:
            logger.warning(f"No pricing found for {provider} instance type: {instance_type}")

        return cost

    def calculate_node_pool_costs(
        self,
        provider: str,
        node_pools: List[Dict]
    ) -> Tuple[List[NodePoolCost], float]:
        """
        Calculate costs for all node pools.

        Args:
            provider: Cloud provider type
            node_pools: List of node pool dictionaries with keys:
                - name: str
                - instance_type: str
                - current_nodes: int

        Returns:
            Tuple of (list of NodePoolCost objects, total monthly cost)
        """
        pool_costs = []
        total_monthly = 0.0

        for pool in node_pools:
            name = pool.get('name', 'unknown')
            instance_type = pool.get('instance_type', 'unknown')
            node_count = pool.get('current_nodes', 0)

            # Get hourly cost per node
            cost_per_node_hourly = self.get_instance_pricing(provider, instance_type)

            # Calculate totals
            hourly_cost = cost_per_node_hourly * node_count
            daily_cost = hourly_cost * 24
            monthly_cost = hourly_cost * 730  # Average hours per month

            total_monthly += monthly_cost

            pool_costs.append(NodePoolCost(
                name=name,
                instance_type=instance_type,
                current_nodes=node_count,
                hourly_cost=round(hourly_cost, 2),
                daily_cost=round(daily_cost, 2),
                monthly_projection=round(monthly_cost, 2),
                cost_per_node_hourly=round(cost_per_node_hourly, 4)
            ))

        return pool_costs, total_monthly

    def calculate_infrastructure_costs(
        self,
        provider: str,
        cluster_config: Dict
    ) -> Dict[str, InfrastructureCost]:
        """
        Calculate infrastructure service costs (NAT, LB, storage, monitoring).

        Args:
            provider: Cloud provider type
            cluster_config: Cluster configuration with infrastructure details

        Returns:
            Dictionary of infrastructure costs by service name
        """
        infra_costs = {}

        if provider == "eks":
            # NAT Gateway (typically 1-3 per cluster)
            nat_count = cluster_config.get('nat_gateway_count', 1)
            infra_costs['nat_gateway'] = InfrastructureCost(
                service_name="NAT Gateway",
                cost_type="hourly",
                rate=AWS_INFRASTRUCTURE_COSTS['nat_gateway_hourly'],
                estimated_usage=nat_count * 730,  # hours per month
                estimated_cost=round(AWS_INFRASTRUCTURE_COSTS['nat_gateway_hourly'] * nat_count * 730, 2)
            )

            # Load Balancer
            lb_count = cluster_config.get('load_balancer_count', 1)
            infra_costs['load_balancer'] = InfrastructureCost(
                service_name="Network Load Balancer",
                cost_type="hourly",
                rate=AWS_INFRASTRUCTURE_COSTS['load_balancer_nlb_hourly'],
                estimated_usage=lb_count * 730,
                estimated_cost=round(AWS_INFRASTRUCTURE_COSTS['load_balancer_nlb_hourly'] * lb_count * 730, 2)
            )

            # EBS Storage (estimate 100GB per node)
            total_nodes = cluster_config.get('total_nodes', 10)
            storage_gb = total_nodes * 100
            infra_costs['storage'] = InfrastructureCost(
                service_name="EBS Storage (gp3)",
                cost_type="per_gb",
                rate=AWS_INFRASTRUCTURE_COSTS['ebs_gp3_per_gb_month'],
                estimated_usage=storage_gb,
                estimated_cost=round(storage_gb * AWS_INFRASTRUCTURE_COSTS['ebs_gp3_per_gb_month'], 2)
            )

            # CloudWatch
            infra_costs['monitoring'] = InfrastructureCost(
                service_name="CloudWatch Logs & Metrics",
                cost_type="monthly",
                rate=50.0,  # Estimated
                estimated_usage=1,
                estimated_cost=50.0
            )

            # EKS Cluster Management
            infra_costs['cluster_management'] = InfrastructureCost(
                service_name="EKS Cluster Management",
                cost_type="hourly",
                rate=AWS_INFRASTRUCTURE_COSTS['eks_cluster_hourly'],
                estimated_usage=730,
                estimated_cost=round(AWS_INFRASTRUCTURE_COSTS['eks_cluster_hourly'] * 730, 2)
            )

        elif provider == "aks":
            # Similar calculations for Azure
            # NAT Gateway
            nat_count = cluster_config.get('nat_gateway_count', 1)
            infra_costs['nat_gateway'] = InfrastructureCost(
                service_name="NAT Gateway",
                cost_type="hourly",
                rate=AZURE_INFRASTRUCTURE_COSTS['nat_gateway_hourly'],
                estimated_usage=nat_count * 730,
                estimated_cost=round(AZURE_INFRASTRUCTURE_COSTS['nat_gateway_hourly'] * nat_count * 730, 2)
            )

            # Load Balancer
            infra_costs['load_balancer'] = InfrastructureCost(
                service_name="Load Balancer Standard",
                cost_type="hourly",
                rate=AZURE_INFRASTRUCTURE_COSTS['load_balancer_standard_hourly'],
                estimated_usage=730,
                estimated_cost=round(AZURE_INFRASTRUCTURE_COSTS['load_balancer_standard_hourly'] * 730, 2)
            )

            # Managed Disks
            total_nodes = cluster_config.get('total_nodes', 10)
            storage_gb = total_nodes * 100
            infra_costs['storage'] = InfrastructureCost(
                service_name="Managed Disks (Premium SSD)",
                cost_type="per_gb",
                rate=AZURE_INFRASTRUCTURE_COSTS['managed_disk_premium_ssd_per_gb'],
                estimated_usage=storage_gb,
                estimated_cost=round(storage_gb * AZURE_INFRASTRUCTURE_COSTS['managed_disk_premium_ssd_per_gb'], 2)
            )

            # Azure Monitor
            infra_costs['monitoring'] = InfrastructureCost(
                service_name="Azure Monitor",
                cost_type="monthly",
                rate=75.0,
                estimated_usage=1,
                estimated_cost=75.0
            )

        elif provider == "gke":
            # Similar calculations for GCP
            nat_count = cluster_config.get('nat_gateway_count', 1)
            infra_costs['nat_gateway'] = InfrastructureCost(
                service_name="Cloud NAT",
                cost_type="hourly",
                rate=GCP_INFRASTRUCTURE_COSTS['cloud_nat_gateway_hourly'],
                estimated_usage=nat_count * 730,
                estimated_cost=round(GCP_INFRASTRUCTURE_COSTS['cloud_nat_gateway_hourly'] * nat_count * 730, 2)
            )

            infra_costs['load_balancer'] = InfrastructureCost(
                service_name="Load Balancer",
                cost_type="monthly",
                rate=GCP_INFRASTRUCTURE_COSTS['load_balancer_forwarding_rule'],
                estimated_usage=730,
                estimated_cost=round(GCP_INFRASTRUCTURE_COSTS['load_balancer_forwarding_rule'] * 730, 2)
            )

            total_nodes = cluster_config.get('total_nodes', 10)
            storage_gb = total_nodes * 100
            infra_costs['storage'] = InfrastructureCost(
                service_name="Persistent Disk SSD",
                cost_type="per_gb",
                rate=GCP_INFRASTRUCTURE_COSTS['persistent_disk_ssd_per_gb'],
                estimated_usage=storage_gb,
                estimated_cost=round(storage_gb * GCP_INFRASTRUCTURE_COSTS['persistent_disk_ssd_per_gb'], 2)
            )

            infra_costs['monitoring'] = InfrastructureCost(
                service_name="Cloud Logging & Monitoring",
                cost_type="monthly",
                rate=60.0,
                estimated_usage=1,
                estimated_cost=60.0
            )

            infra_costs['cluster_management'] = InfrastructureCost(
                service_name="GKE Cluster Management",
                cost_type="hourly",
                rate=GCP_INFRASTRUCTURE_COSTS['gke_cluster_hourly'],
                estimated_usage=730,
                estimated_cost=round(GCP_INFRASTRUCTURE_COSTS['gke_cluster_hourly'] * 730, 2)
            )

        return infra_costs

    def calculate_cost_breakdown(
        self,
        compute_cost: float,
        infrastructure_costs: Dict[str, InfrastructureCost]
    ) -> Dict[str, CostBreakdownItem]:
        """
        Calculate cost breakdown by category.

        Args:
            compute_cost: Total compute cost
            infrastructure_costs: Dictionary of infrastructure costs

        Returns:
            Dictionary of cost breakdown by category
        """
        # Sum infrastructure costs by category
        networking_cost = 0.0
        storage_cost = 0.0
        monitoring_cost = 0.0
        cluster_mgmt_cost = 0.0

        for service_name, infra_cost in infrastructure_costs.items():
            if 'nat' in service_name.lower() or 'load' in service_name.lower():
                networking_cost += infra_cost.estimated_cost
            elif 'storage' in service_name.lower() or 'disk' in service_name.lower():
                storage_cost += infra_cost.estimated_cost
            elif 'monitor' in service_name.lower() or 'logging' in service_name.lower():
                monitoring_cost += infra_cost.estimated_cost
            elif 'cluster' in service_name.lower() or 'management' in service_name.lower():
                cluster_mgmt_cost += infra_cost.estimated_cost

        total_cost = compute_cost + networking_cost + storage_cost + monitoring_cost + cluster_mgmt_cost

        breakdown = {
            'compute': CostBreakdownItem(
                cost=round(compute_cost, 2),
                percentage=round((compute_cost / total_cost * 100) if total_cost > 0 else 0, 1)
            ),
            'networking': CostBreakdownItem(
                cost=round(networking_cost, 2),
                percentage=round((networking_cost / total_cost * 100) if total_cost > 0 else 0, 1)
            ),
            'storage': CostBreakdownItem(
                cost=round(storage_cost, 2),
                percentage=round((storage_cost / total_cost * 100) if total_cost > 0 else 0, 1)
            ),
            'monitoring': CostBreakdownItem(
                cost=round(monitoring_cost, 2),
                percentage=round((monitoring_cost / total_cost * 100) if total_cost > 0 else 0, 1)
            )
        }

        if cluster_mgmt_cost > 0:
            breakdown['cluster_management'] = CostBreakdownItem(
                cost=round(cluster_mgmt_cost, 2),
                percentage=round((cluster_mgmt_cost / total_cost * 100) if total_cost > 0 else 0, 1)
            )

        return breakdown

    def generate_cost_trends(
        self,
        cluster_name: str,
        current_daily_cost: float
    ) -> CostTrends:
        """
        Generate cost trend data (simulated for hardcoded pricing).

        Args:
            cluster_name: Cluster identifier
            current_daily_cost: Current daily cost

        Returns:
            CostTrends object with historical data
        """
        # For now, simulate trends based on current cost with minor variations
        # In production with real billing API, this would use actual historical data

        import random

        # Generate last 7 days with ±5% variation
        last_7_days = []
        for i in range(7):
            variation = random.uniform(-0.05, 0.05)
            daily_cost = current_daily_cost * (1 + variation)
            last_7_days.append(round(daily_cost, 2))

        # Generate last 30 days with ±10% variation
        last_30_days = []
        for i in range(30):
            variation = random.uniform(-0.10, 0.10)
            daily_cost = current_daily_cost * (1 + variation)
            last_30_days.append(round(daily_cost, 2))

        # Find highest and lowest
        highest_cost = max(last_30_days)
        lowest_cost = min(last_30_days)
        highest_idx = last_30_days.index(highest_cost)
        lowest_idx = last_30_days.index(lowest_cost)

        today = datetime.utcnow().date()

        return CostTrends(
            last_7_days=last_7_days,
            last_30_days=last_30_days,
            highest_day=CostTrendDay(
                date=(today - timedelta(days=29-highest_idx)).isoformat(),
                cost=highest_cost
            ),
            lowest_day=CostTrendDay(
                date=(today - timedelta(days=29-lowest_idx)).isoformat(),
                cost=lowest_cost
            ),
            average_daily=round(sum(last_30_days) / len(last_30_days), 2)
        )

    def generate_optimization_recommendations(
        self,
        provider: str,
        total_compute_cost: float,
        node_pool_costs: List[NodePoolCost],
        cluster_config: Dict
    ) -> List[OptimizationRecommendation]:
        """
        Generate cost optimization recommendations.

        Args:
            provider: Cloud provider type
            total_compute_cost: Total monthly compute cost
            node_pool_costs: Node pool cost details
            cluster_config: Cluster configuration

        Returns:
            List of optimization recommendations
        """
        recommendations = []

        # Reserved Instances (30-40% savings for 1-year commitment)
        if total_compute_cost > 3000:
            savings_percent = 35
            potential_savings = total_compute_cost * (savings_percent / 100)

            recommendations.append(OptimizationRecommendation(
                type="reserved_instances",
                potential_savings=round(potential_savings, 2),
                savings_percentage=savings_percent,
                description=(
                    f"Purchase 1-year reserved instances for production workloads. "
                    f"Save up to {savings_percent}% on compute costs "
                    f"(${potential_savings:,.2f}/month) with predictable pricing."
                ),
                priority="high"
            ))

        # Auto-scaling (20-40% savings)
        uptime_pattern = cluster_config.get('uptime_pattern', '24/7')
        if uptime_pattern == '24/7' and total_compute_cost > 2000:
            savings_percent = 30
            potential_savings = total_compute_cost * (savings_percent / 100)

            recommendations.append(OptimizationRecommendation(
                type="auto_scaling",
                potential_savings=round(potential_savings, 2),
                savings_percentage=savings_percent,
                description=(
                    "Implement time-based auto-scaling to shut down non-production "
                    f"resources during off-hours. Save ${potential_savings:,.2f}/month "
                    "by running clusters only during business hours (8am-6pm Mon-Fri)."
                ),
                priority="high"
            ))

        # Spot Instances (50-70% savings for fault-tolerant workloads)
        spot_eligible = cluster_config.get('spot_eligible_workloads', False)
        if not spot_eligible and total_compute_cost > 1500:
            savings_percent = 60
            # Estimate 50% of workload can use spot
            potential_savings = (total_compute_cost * 0.5) * (savings_percent / 100)

            recommendations.append(OptimizationRecommendation(
                type="spot_instances",
                potential_savings=round(potential_savings, 2),
                savings_percentage=savings_percent,
                description=(
                    "Use spot instances for stateless and fault-tolerant workloads. "
                    f"Save up to ${potential_savings:,.2f}/month with spot pricing "
                    "for batch jobs, testing, and development environments."
                ),
                priority="medium"
            ))

        # GPU Time-Slicing (for GPU workloads)
        gpu_node_pools = [p for p in node_pool_costs if 'g5.' in p.instance_type or
                          'NC' in p.instance_type or 'tesla' in p.instance_type.lower()]

        if gpu_node_pools:
            total_gpu_cost = sum(p.monthly_projection for p in gpu_node_pools)
            time_slicing_enabled = cluster_config.get('gpu_time_slicing_enabled', False)

            if not time_slicing_enabled and total_gpu_cost > 1000:
                savings_percent = 40
                potential_savings = total_gpu_cost * (savings_percent / 100)

                recommendations.append(OptimizationRecommendation(
                    type="gpu_time_slicing",
                    potential_savings=round(potential_savings, 2),
                    savings_percentage=savings_percent,
                    description=(
                        "Enable GPU time-slicing to run multiple pods per GPU. "
                        f"Save ${potential_savings:,.2f}/month by increasing GPU "
                        "utilization from 2-4 pods per GPU."
                    ),
                    priority="high"
                ))

        # Right-sizing (10-20% savings)
        if total_compute_cost > 2000:
            savings_percent = 15
            potential_savings = total_compute_cost * (savings_percent / 100)

            recommendations.append(OptimizationRecommendation(
                type="right_sizing",
                potential_savings=round(potential_savings, 2),
                savings_percentage=savings_percent,
                description=(
                    "Analyze resource utilization and right-size instances. "
                    f"Save ${potential_savings:,.2f}/month by matching instance "
                    "types to actual CPU/memory requirements."
                ),
                priority="medium"
            ))

        # Sort by potential savings (highest first)
        recommendations.sort(key=lambda x: x.potential_savings, reverse=True)

        return recommendations

    def calculate_budget_status(
        self,
        current_total_cost: float,
        days_into_month: int
    ) -> Optional[BudgetStatus]:
        """
        Calculate budget tracking status.

        Args:
            current_total_cost: Current month-to-date cost
            days_into_month: Days elapsed in current month

        Returns:
            BudgetStatus object if budget is set, None otherwise
        """
        if self._monthly_budget is None:
            return None

        # Project end-of-month cost
        days_in_month = 30  # Simplified
        projected_spend = (current_total_cost / days_into_month) * days_in_month

        remaining = self._monthly_budget - current_total_cost
        utilization_pct = (current_total_cost / self._monthly_budget * 100) if self._monthly_budget > 0 else 0

        # Check if on track (current spend should be <= proportional to days elapsed)
        expected_spend = (self._monthly_budget / days_in_month) * days_into_month
        on_track = current_total_cost <= expected_spend

        return BudgetStatus(
            monthly_budget=self._monthly_budget,
            current_spend=round(current_total_cost, 2),
            projected_spend=round(projected_spend, 2),
            remaining=round(remaining, 2),
            utilization_percentage=round(utilization_pct, 1),
            on_track=on_track,
            days_into_month=days_into_month
        )

    def calculate_current_period(
        self,
        total_monthly_cost: float
    ) -> CurrentPeriod:
        """
        Calculate current billing period details.

        Args:
            total_monthly_cost: Projected monthly cost

        Returns:
            CurrentPeriod object
        """
        today = datetime.utcnow().date()

        # Start of month
        start_date = today.replace(day=1)

        # Days elapsed
        days_elapsed = (today - start_date).days + 1

        # Daily average
        daily_avg = total_monthly_cost / 30  # Simplified

        # Cost to date
        cost_to_date = daily_avg * days_elapsed

        return CurrentPeriod(
            start_date=start_date.isoformat(),
            end_date=today.isoformat(),
            total_cost=round(cost_to_date, 2),
            daily_average=round(daily_avg, 2),
            projected_monthly=round(total_monthly_cost, 2)
        )


# Global service instance
cost_calculator_service = CostCalculatorService()
