"""
AWS Region Management Service

This module provides comprehensive AWS region management and discovery capabilities
for the MiniPrem Monitor backend, including region validation, EKS cluster discovery,
and region-specific operations.
"""

import asyncio
import subprocess
import json
import logging
from typing import Dict, List, Any, Optional, Tuple
from datetime import datetime
from ..models.schemas import AwsRegion, RegionStatus, ClusterInfo, KubernetesContext

logger = logging.getLogger(__name__)


class AwsRegionManager:
    """
    Comprehensive AWS region management and discovery service.

    Provides region validation, EKS cluster discovery, and region-specific
    Kubernetes context management with proper error handling and caching.
    """

    # Complete list of AWS regions as of 2025
    AWS_REGIONS = [
        # US regions
        {'name': 'us-east-1', 'display_name': 'US East (N. Virginia)'},
        {'name': 'us-east-2', 'display_name': 'US East (Ohio)'},
        {'name': 'us-west-1', 'display_name': 'US West (N. California)'},
        {'name': 'us-west-2', 'display_name': 'US West (Oregon)'},

        # Europe regions
        {'name': 'eu-west-1', 'display_name': 'Europe (Ireland)'},
        {'name': 'eu-west-2', 'display_name': 'Europe (London)'},
        {'name': 'eu-west-3', 'display_name': 'Europe (Paris)'},
        {'name': 'eu-central-1', 'display_name': 'Europe (Frankfurt)'},
        {'name': 'eu-central-2', 'display_name': 'Europe (Zurich)'},
        {'name': 'eu-north-1', 'display_name': 'Europe (Stockholm)'},
        {'name': 'eu-south-1', 'display_name': 'Europe (Milan)'},
        {'name': 'eu-south-2', 'display_name': 'Europe (Spain)'},

        # Asia Pacific regions
        {'name': 'ap-northeast-1', 'display_name': 'Asia Pacific (Tokyo)'},
        {'name': 'ap-northeast-2', 'display_name': 'Asia Pacific (Seoul)'},
        {'name': 'ap-northeast-3', 'display_name': 'Asia Pacific (Osaka)'},
        {'name': 'ap-southeast-1', 'display_name': 'Asia Pacific (Singapore)'},
        {'name': 'ap-southeast-2', 'display_name': 'Asia Pacific (Sydney)'},
        {'name': 'ap-southeast-3', 'display_name': 'Asia Pacific (Jakarta)'},
        {'name': 'ap-southeast-4', 'display_name': 'Asia Pacific (Melbourne)'},
        {'name': 'ap-south-1', 'display_name': 'Asia Pacific (Mumbai)'},
        {'name': 'ap-south-2', 'display_name': 'Asia Pacific (Hyderabad)'},

        # Other regions
        {'name': 'ca-central-1', 'display_name': 'Canada (Central)'},
        {'name': 'ca-west-1', 'display_name': 'Canada (Calgary)'},
        {'name': 'sa-east-1', 'display_name': 'South America (São Paulo)'},
        {'name': 'af-south-1', 'display_name': 'Africa (Cape Town)'},
        {'name': 'me-south-1', 'display_name': 'Middle East (Bahrain)'},
        {'name': 'me-central-1', 'display_name': 'Middle East (UAE)'},
        {'name': 'il-central-1', 'display_name': 'Israel (Tel Aviv)'},

        # AWS GovCloud regions
        {'name': 'us-gov-east-1', 'display_name': 'AWS GovCloud (US-East)'},
        {'name': 'us-gov-west-1', 'display_name': 'AWS GovCloud (US-West)'},

        # China regions (for completeness, may require special credentials)
        {'name': 'cn-north-1', 'display_name': 'China (Beijing)'},
        {'name': 'cn-northwest-1', 'display_name': 'China (Ningxia)'},
    ]

    def __init__(self):
        """Initialize the AWS region manager."""
        self._region_cache: Dict[str, Any] = {}
        self._cache_timestamp: Optional[datetime] = None
        self._cache_ttl_seconds = 300  # 5 minutes
        self._aws_profile: Optional[str] = None

    async def get_available_regions(self, validate_access: bool = False) -> List[AwsRegion]:
        """
        Get list of available AWS regions.

        Args:
            validate_access: If True, validate actual access to each region

        Returns:
            List of AwsRegion objects with availability status

        Raises:
            Exception: If AWS CLI is not available or configured
        """
        try:
            regions = []

            for region_data in self.AWS_REGIONS:
                region = AwsRegion(
                    name=region_data['name'],
                    display_name=region_data['display_name'],
                    available=True  # Default to available
                )

                if validate_access:
                    # Validate actual access to the region
                    region.available = await self._validate_region_access(region.name)

                regions.append(region)

            logger.info(f"Retrieved {len(regions)} AWS regions")
            return regions

        except Exception as e:
            logger.error(f"Error getting available regions: {str(e)}")
            raise

    async def get_region_status(self, region: str) -> RegionStatus:
        """
        Get detailed status information for a specific region.

        Args:
            region: AWS region name (e.g., 'us-east-1')

        Returns:
            RegionStatus object with detailed region information

        Raises:
            Exception: If region validation fails
        """
        try:
            # Validate region name
            if not self._is_valid_region(region):
                raise ValueError(f"Invalid AWS region: {region}")

            # Check if region is accessible
            available = await self._validate_region_access(region)

            # Get EKS cluster count for the region
            cluster_count = 0
            error_message = None

            if available:
                try:
                    cluster_count = await self._get_eks_cluster_count(region)
                except Exception as e:
                    logger.warning(f"Failed to get cluster count for {region}: {str(e)}")
                    error_message = str(e)

            return RegionStatus(
                region=region,
                available=available,
                cluster_count=cluster_count,
                last_checked=datetime.utcnow(),
                error=error_message
            )

        except Exception as e:
            logger.error(f"Error getting region status for {region}: {str(e)}")
            raise

    async def get_kubernetes_contexts_by_region(self, region: str) -> Tuple[List[KubernetesContext], List[ClusterInfo]]:
        """
        Get Kubernetes contexts and cluster information for a specific region.

        Args:
            region: AWS region name

        Returns:
            Tuple of (contexts, clusters) lists

        Raises:
            Exception: If region is invalid or context discovery fails
        """
        try:
            # Validate region
            if not self._is_valid_region(region):
                raise ValueError(f"Invalid AWS region: {region}")

            # Get kubectl contexts that match the region
            contexts = await self._get_contexts_for_region(region)

            # Get EKS cluster information for the region
            clusters = await self._get_eks_clusters_for_region(region)

            logger.info(f"Found {len(contexts)} contexts and {len(clusters)} clusters for region {region}")
            return contexts, clusters

        except Exception as e:
            logger.error(f"Error getting Kubernetes contexts for region {region}: {str(e)}")
            raise

    async def discover_region_from_context(self, context_name: str) -> Optional[str]:
        """
        Discover AWS region from a Kubernetes context name.

        Args:
            context_name: Name of the Kubernetes context

        Returns:
            AWS region name if discovered, None otherwise
        """
        try:
            # Try to extract region from common EKS context naming patterns
            # Pattern: arn:aws:eks:region:account:cluster/cluster-name
            # Pattern: region.cluster-name
            # Pattern: cluster-name-region

            for region_data in self.AWS_REGIONS:
                region = region_data['name']
                if region in context_name:
                    logger.debug(f"Discovered region {region} from context {context_name}")
                    return region

            # Try to get region from kubectl context cluster info
            region = await self._get_region_from_kubectl_context(context_name)
            if region:
                logger.info(f"Discovered region {region} from kubectl context {context_name}")
                return region

            logger.warning(f"Could not discover region from context {context_name}")
            return None

        except Exception as e:
            logger.error(f"Error discovering region from context {context_name}: {str(e)}")
            return None

    def set_aws_profile(self, profile: str) -> None:
        """
        Set AWS profile for operations.

        Args:
            profile: AWS profile name
        """
        self._aws_profile = profile
        logger.info(f"AWS profile set to: {profile}")

    def get_aws_profile(self) -> Optional[str]:
        """
        Get current AWS profile.

        Returns:
            Current AWS profile name or None
        """
        return self._aws_profile

    def _is_valid_region(self, region: str) -> bool:
        """
        Validate if a region name is valid AWS region.

        Args:
            region: Region name to validate

        Returns:
            True if valid, False otherwise
        """
        return any(r['name'] == region for r in self.AWS_REGIONS)

    async def _validate_region_access(self, region: str) -> bool:
        """
        Validate access to an AWS region.

        Args:
            region: AWS region name

        Returns:
            True if region is accessible, False otherwise
        """
        try:
            # Build AWS CLI command
            cmd = ['aws', 'sts', 'get-caller-identity', '--region', region, '--output', 'json']

            if self._aws_profile:
                cmd.extend(['--profile', self._aws_profile])

            # Execute with timeout
            result = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            stdout, stderr = await asyncio.wait_for(
                result.communicate(),
                timeout=10.0
            )

            if result.returncode == 0:
                return True
            else:
                logger.debug(f"Region {region} not accessible: {stderr.decode()}")
                return False

        except asyncio.TimeoutError:
            logger.warning(f"Timeout validating access to region {region}")
            return False
        except Exception as e:
            logger.debug(f"Error validating region {region}: {str(e)}")
            return False

    async def _get_eks_cluster_count(self, region: str) -> int:
        """
        Get count of EKS clusters in a region.

        Args:
            region: AWS region name

        Returns:
            Number of EKS clusters in the region
        """
        try:
            cmd = ['aws', 'eks', 'list-clusters', '--region', region, '--output', 'json']

            if self._aws_profile:
                cmd.extend(['--profile', self._aws_profile])

            result = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            stdout, stderr = await asyncio.wait_for(
                result.communicate(),
                timeout=15.0
            )

            if result.returncode == 0:
                data = json.loads(stdout.decode())
                clusters = data.get('clusters', [])
                return len(clusters)
            else:
                logger.debug(f"Failed to get EKS clusters for {region}: {stderr.decode()}")
                return 0

        except Exception as e:
            logger.debug(f"Error getting EKS cluster count for {region}: {str(e)}")
            return 0

    async def _get_contexts_for_region(self, region: str) -> List[KubernetesContext]:
        """
        Get kubectl contexts that belong to a specific region.

        Args:
            region: AWS region name

        Returns:
            List of KubernetesContext objects for the region
        """
        try:
            # Get all kubectl contexts
            cmd = ['kubectl', 'config', 'get-contexts', '-o', 'name']

            result = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            stdout, stderr = await result.communicate()

            if result.returncode != 0:
                logger.warning(f"Failed to get kubectl contexts: {stderr.decode()}")
                return []

            context_names = stdout.decode().strip().split('\n')
            contexts = []

            for context_name in context_names:
                if not context_name.strip():
                    continue

                # Check if this context belongs to the specified region
                context_region = await self.discover_region_from_context(context_name)

                if context_region == region:
                    # Get detailed context information
                    context_info = await self._get_context_details(context_name)
                    if context_info:
                        context_info.region = region
                        contexts.append(context_info)

            return contexts

        except Exception as e:
            logger.error(f"Error getting contexts for region {region}: {str(e)}")
            return []

    async def _get_eks_clusters_for_region(self, region: str) -> List[ClusterInfo]:
        """
        Get EKS cluster information for a specific region.

        Args:
            region: AWS region name

        Returns:
            List of ClusterInfo objects
        """
        try:
            # List EKS clusters in the region
            cmd = ['aws', 'eks', 'list-clusters', '--region', region, '--output', 'json']

            if self._aws_profile:
                cmd.extend(['--profile', self._aws_profile])

            result = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            stdout, stderr = await asyncio.wait_for(
                result.communicate(),
                timeout=15.0
            )

            if result.returncode != 0:
                logger.debug(f"Failed to list EKS clusters in {region}: {stderr.decode()}")
                return []

            data = json.loads(stdout.decode())
            cluster_names = data.get('clusters', [])
            clusters = []

            # Get detailed information for each cluster
            for cluster_name in cluster_names:
                cluster_info = await self._get_eks_cluster_details(cluster_name, region)
                if cluster_info:
                    clusters.append(cluster_info)

            return clusters

        except Exception as e:
            logger.error(f"Error getting EKS clusters for region {region}: {str(e)}")
            return []

    async def _get_context_details(self, context_name: str) -> Optional[KubernetesContext]:
        """
        Get detailed information for a kubectl context.

        Args:
            context_name: Name of the kubectl context

        Returns:
            KubernetesContext object or None if failed
        """
        try:
            # Get context details
            cmd = ['kubectl', 'config', 'view', '-o', 'json']

            result = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            stdout, stderr = await result.communicate()

            if result.returncode != 0:
                logger.debug(f"Failed to get context details: {stderr.decode()}")
                return None

            config_data = json.loads(stdout.decode())
            contexts = config_data.get('contexts', [])
            current_context = config_data.get('current-context')

            for context in contexts:
                if context.get('name') == context_name:
                    context_info = context.get('context', {})

                    return KubernetesContext(
                        name=context_name,
                        cluster=context_info.get('cluster', 'unknown'),
                        user=context_info.get('user', 'unknown'),
                        namespace=context_info.get('namespace', 'default'),
                        current=(context_name == current_context)
                    )

            return None

        except Exception as e:
            logger.debug(f"Error getting context details for {context_name}: {str(e)}")
            return None

    async def _get_eks_cluster_details(self, cluster_name: str, region: str) -> Optional[ClusterInfo]:
        """
        Get detailed information for an EKS cluster.

        Args:
            cluster_name: Name of the EKS cluster
            region: AWS region name

        Returns:
            ClusterInfo object or None if failed
        """
        try:
            cmd = ['aws', 'eks', 'describe-cluster', '--name', cluster_name, '--region', region, '--output', 'json']

            if self._aws_profile:
                cmd.extend(['--profile', self._aws_profile])

            result = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            stdout, stderr = await asyncio.wait_for(
                result.communicate(),
                timeout=10.0
            )

            if result.returncode != 0:
                logger.debug(f"Failed to describe EKS cluster {cluster_name}: {stderr.decode()}")
                return ClusterInfo(
                    name=cluster_name,
                    region=region,
                    status="error",
                    available=False
                )

            data = json.loads(stdout.decode())
            cluster = data.get('cluster', {})

            # Parse cluster status
            status_map = {
                'ACTIVE': 'running',
                'CREATING': 'pending',
                'DELETING': 'pending',
                'FAILED': 'error',
                'UPDATING': 'pending'
            }

            cluster_status = cluster.get('status', 'UNKNOWN')
            mapped_status = status_map.get(cluster_status, 'unknown')

            # Parse creation time
            created_at = None
            if 'createdAt' in cluster:
                try:
                    created_at = datetime.fromtimestamp(cluster['createdAt'])
                except (ValueError, TypeError):
                    pass

            return ClusterInfo(
                name=cluster_name,
                region=region,
                status=mapped_status,
                available=(mapped_status == 'running'),
                endpoint=cluster.get('endpoint'),
                version={'server': cluster.get('version', 'unknown')},
                created_at=created_at,
                last_activity=datetime.utcnow()
            )

        except Exception as e:
            logger.debug(f"Error getting EKS cluster details for {cluster_name}: {str(e)}")
            return ClusterInfo(
                name=cluster_name,
                region=region,
                status="error",
                available=False
            )

    async def _get_region_from_kubectl_context(self, context_name: str) -> Optional[str]:
        """
        Try to extract region information from kubectl context cluster info.

        Args:
            context_name: Name of the kubectl context

        Returns:
            AWS region name if found, None otherwise
        """
        try:
            # Switch to the context temporarily to get cluster info
            original_context = None

            # Get current context
            result = await asyncio.create_subprocess_exec(
                'kubectl', 'config', 'current-context',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, _ = await result.communicate()

            if result.returncode == 0:
                original_context = stdout.decode().strip()

            # Switch to target context
            result = await asyncio.create_subprocess_exec(
                'kubectl', 'config', 'use-context', context_name,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            if result.returncode != 0:
                return None

            # Get cluster info
            result = await asyncio.create_subprocess_exec(
                'kubectl', 'cluster-info', '--output=json',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, _ = await result.communicate()

            # Restore original context
            if original_context:
                await asyncio.create_subprocess_exec(
                    'kubectl', 'config', 'use-context', original_context,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE
                )

            if result.returncode == 0:
                try:
                    cluster_info = json.loads(stdout.decode())

                    # Look for region in cluster info
                    for service, info in cluster_info.items():
                        if isinstance(info, str) and 'amazonaws.com' in info:
                            # Extract region from AWS endpoint
                            # e.g., https://A1B2C3D4E5F6.gr7.us-west-2.eks.amazonaws.com
                            for region_data in self.AWS_REGIONS:
                                region = region_data['name']
                                if region in info:
                                    return region

                except json.JSONDecodeError:
                    pass

            return None

        except Exception as e:
            logger.debug(f"Error extracting region from kubectl context {context_name}: {str(e)}")
            return None