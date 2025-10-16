"""
Cost Tracking Models

Pydantic models for cloud cost tracking and analysis across EKS, AKS, and GKE clusters.
Supports hardcoded pricing and optional cloud billing API integration.
"""

from typing import Dict, List, Optional, Literal
from datetime import date
from pydantic import BaseModel, Field


class CostBreakdownItem(BaseModel):
    """Individual cost category breakdown."""
    cost: float = Field(..., description="Cost in USD")
    percentage: float = Field(..., description="Percentage of total cost")


class NodePoolCost(BaseModel):
    """Cost details for a single node pool."""
    name: str = Field(..., description="Node pool name")
    instance_type: str = Field(..., description="VM/instance type (e.g., g5.4xlarge)")
    current_nodes: int = Field(..., description="Current number of nodes")
    hourly_cost: float = Field(..., description="Total hourly cost for all nodes")
    daily_cost: float = Field(..., description="Total daily cost projection")
    monthly_projection: float = Field(..., description="30-day cost projection")
    cost_per_node_hourly: float = Field(..., description="Cost per node per hour")


class OptimizationRecommendation(BaseModel):
    """Cost optimization recommendation."""
    type: Literal[
        "reserved_instances",
        "auto_scaling",
        "spot_instances",
        "right_sizing",
        "scheduled_scaling",
        "gpu_time_slicing"
    ] = Field(..., description="Recommendation type")
    potential_savings: float = Field(..., description="Potential monthly savings in USD")
    savings_percentage: float = Field(..., description="Savings as percentage of current cost")
    description: str = Field(..., description="Detailed recommendation description")
    priority: Literal["high", "medium", "low"] = Field(
        default="medium",
        description="Recommendation priority"
    )


class BudgetStatus(BaseModel):
    """Budget tracking and utilization."""
    monthly_budget: Optional[float] = Field(None, description="Monthly budget limit in USD")
    current_spend: float = Field(..., description="Current month-to-date spend")
    projected_spend: float = Field(..., description="Projected end-of-month spend")
    remaining: Optional[float] = Field(None, description="Remaining budget")
    utilization_percentage: float = Field(..., description="Budget utilization percentage")
    on_track: bool = Field(..., description="Whether spending is on track with budget")
    days_into_month: int = Field(..., description="Days elapsed in current month")


class CostTrendDay(BaseModel):
    """Daily cost data point."""
    date: str = Field(..., description="Date in YYYY-MM-DD format")
    cost: float = Field(..., description="Total cost for the day")


class CostTrends(BaseModel):
    """Historical cost trend data."""
    last_7_days: List[float] = Field(..., description="Daily costs for last 7 days")
    last_30_days: List[float] = Field(..., description="Daily costs for last 30 days")
    highest_day: CostTrendDay = Field(..., description="Highest cost day")
    lowest_day: CostTrendDay = Field(..., description="Lowest cost day")
    average_daily: float = Field(..., description="Average daily cost")


class CurrentPeriod(BaseModel):
    """Current billing period summary."""
    start_date: str = Field(..., description="Period start date (YYYY-MM-DD)")
    end_date: str = Field(..., description="Period end date (YYYY-MM-DD)")
    total_cost: float = Field(..., description="Total cost for period to date")
    daily_average: float = Field(..., description="Average daily cost")
    projected_monthly: float = Field(..., description="Projected monthly total")


class EnhancedCostResponse(BaseModel):
    """Enhanced cost tracking response with comprehensive analysis."""
    success: bool = Field(..., description="Request success status")
    provider: Literal["eks", "aks", "gke", "unknown"] = Field(
        ...,
        description="Cloud provider type"
    )
    cluster_name: str = Field(..., description="Kubernetes cluster name")
    current_period: CurrentPeriod = Field(..., description="Current billing period details")
    cost_breakdown: Dict[str, CostBreakdownItem] = Field(
        ...,
        description="Cost breakdown by category (compute, networking, storage, monitoring)"
    )
    node_pool_costs: List[NodePoolCost] = Field(..., description="Per node pool cost details")
    cost_trends: CostTrends = Field(..., description="Historical cost trends")
    optimization_recommendations: List[OptimizationRecommendation] = Field(
        ...,
        description="Cost optimization recommendations"
    )
    budget_status: Optional[BudgetStatus] = Field(
        None,
        description="Budget tracking status (if configured)"
    )
    data_source: Literal["hardcoded_pricing", "aws_cost_explorer", "azure_cost_mgmt", "gcp_billing"] = Field(
        ...,
        description="Source of cost data"
    )
    pricing_region: str = Field(..., description="Pricing region used for calculations")
    timestamp: str = Field(..., description="Response timestamp (ISO 8601)")
    error: Optional[str] = Field(None, description="Error message if success=False")
    error_type: Optional[str] = Field(None, description="Error type classification")


class InstancePricing(BaseModel):
    """Instance type pricing information."""
    instance_type: str = Field(..., description="Instance type identifier")
    hourly_rate: float = Field(..., description="Hourly rate in USD")
    monthly_rate: float = Field(..., description="Monthly rate (730 hours)")
    region: str = Field(..., description="Pricing region")
    provider: str = Field(..., description="Cloud provider")
    category: Literal["compute", "gpu", "memory_optimized", "storage_optimized"] = Field(
        ...,
        description="Instance category"
    )
    vcpus: Optional[int] = Field(None, description="Number of vCPUs")
    memory_gb: Optional[float] = Field(None, description="Memory in GB")
    gpu_count: Optional[int] = Field(None, description="Number of GPUs")
    gpu_type: Optional[str] = Field(None, description="GPU type")


class InfrastructureCost(BaseModel):
    """Infrastructure service cost (NAT, Load Balancer, Storage, etc.)."""
    service_name: str = Field(..., description="Service name")
    cost_type: Literal["hourly", "monthly", "per_gb", "per_request"] = Field(
        ...,
        description="Cost calculation type"
    )
    rate: float = Field(..., description="Cost rate in USD")
    estimated_usage: float = Field(..., description="Estimated usage quantity")
    estimated_cost: float = Field(..., description="Estimated cost in USD")
