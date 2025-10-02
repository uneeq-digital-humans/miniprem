from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import uvicorn
import logging
import uuid
import asyncio
import json
from datetime import datetime
from typing import Dict, Any

from .websocket.connection_manager import ConnectionManager
from .services.system_monitor import SystemMonitor
from .services.kubernetes_monitor import KubernetesMonitor
from .services.docker_manager import DockerManager
from .services.aws_region_manager import AwsRegionManager
from .security.command_executor import CommandExecutor
from .models.schemas import (
    DockerServiceRequest, DockerServiceResponse, ServiceControlRequest,
    RegionListResponse, RegionContextsResponse, RegionStatus
)

# Configure logging with proper WebSocket disconnect handling
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

# Reduce noise from uvicorn websocket disconnect logging
logging.getLogger("uvicorn.protocols.websockets.websockets_impl").setLevel(
    logging.WARNING)
logging.getLogger("uvicorn.protocols.websockets.wsproto_impl").setLevel(
    logging.WARNING)
logging.getLogger("websockets.protocol").setLevel(logging.WARNING)
logging.getLogger("websockets.server").setLevel(logging.WARNING)
logger = logging.getLogger(__name__)


def _log_websocket_disconnect(connection_id: str, disconnect_exception: WebSocketDisconnect, context: str = ""):
    """
    Log WebSocket disconnections at appropriate levels based on disconnect codes.

    Args:
        connection_id: The client connection ID
        disconnect_exception: The WebSocketDisconnect exception
        context: Additional context about when the disconnect occurred
    """
    code = disconnect_exception.code
    reason = disconnect_exception.reason or ""
    context_msg = f" {context}" if context else ""

    # Normal disconnects - log as DEBUG
    if code == 1000:  # Normal closure
        logger.debug(
            f"WebSocket connection {connection_id} closed normally{context_msg} (code {code}): {reason or 'Normal closure'}")
    elif code == 1001:  # Going away (browser/tab closed)
        logger.debug(
            f"WebSocket connection {connection_id} closed (client going away){context_msg} (code {code}): {reason or 'Client going away'}")

    # Service restarts - log as INFO (expected but noteworthy)
    elif code == 1012:  # Service restart
        logger.info(
            f"WebSocket connection {connection_id} closed (service restart){context_msg} (code {code}): {reason or 'Service restart'}")

    # Other expected codes - log as INFO
    elif code in [1002, 1003]:  # Protocol error, unsupported data
        logger.info(
            f"WebSocket connection {connection_id} closed (protocol issue){context_msg} (code {code}): {reason or 'Protocol issue'}")
    elif code in [1005, 1006]:  # No status code, abnormal closure
        logger.info(
            f"WebSocket connection {connection_id} closed (network issue){context_msg} (code {code}): {reason or 'Network issue'}")

    # Unexpected or abnormal disconnects - log as WARNING
    else:
        logger.warning(
            f"WebSocket connection {connection_id} closed abnormally{context_msg} (code {code}): {reason or 'Unknown reason'}")


app = FastAPI(
    title="MiniPrem Monitor API",
    description="Real-time monitoring API for Docker containers and Kubernetes pods",
    version="1.0.0"
)

# CORS middleware for frontend integration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3500",
                   "http://localhost:3001"],  # Next.js dev server
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize managers
connection_manager = ConnectionManager()
system_monitor = SystemMonitor()
kubernetes_monitor = KubernetesMonitor()
docker_manager = DockerManager()
aws_region_manager = AwsRegionManager()
command_executor = CommandExecutor()


@app.get("/")
async def root():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "service": "MiniPrem Monitor API",
        "version": "1.0.0",
        "timestamp": datetime.utcnow().isoformat()
    }


@app.get("/health")
async def health_check():
    """Detailed health check"""
    try:
        # Test system monitoring
        system_metrics = await system_monitor.get_system_metrics()

        return {
            "status": "healthy",
            "components": {
                "api": "operational",
                "websocket": "operational",
                "system_monitor": "operational",
                "command_executor": "operational"
            },
            "metrics": {
                "active_connections": len(connection_manager.active_connections),
                "active_subscriptions": len(connection_manager.subscription_tasks),
                "system_cpu": system_metrics.cpu_percent,
                "system_memory": system_metrics.memory_percent
            },
            "timestamp": datetime.utcnow().isoformat()
        }

    except Exception as e:
        logger.error(f"Health check failed: {str(e)}")
        return JSONResponse(
            status_code=503,
            content={
                "status": "unhealthy",
                "error": "Service components not responding",
                "timestamp": datetime.utcnow().isoformat()
            }
        )


@app.get("/api/kubernetes/contexts")
async def get_kubernetes_contexts():
    """Get available Kubernetes contexts"""
    try:
        contexts = await kubernetes_monitor.get_available_contexts()
        current_context = await kubernetes_monitor.get_current_context()

        return {
            "success": True,
            "contexts": contexts,
            "current_context": current_context,
            "timestamp": datetime.utcnow().isoformat()
        }
    except Exception as e:
        error_msg = str(e)
        logger.error(f"Error getting Kubernetes contexts: {error_msg}")

        # Determine appropriate HTTP status code based on error type
        if "Authentication error" in error_msg:
            status_code = 401
            error_type = "authentication_error"
        elif "Connection error" in error_msg:
            status_code = 502
            error_type = "connection_error"
        else:
            status_code = 500
            error_type = "server_error"

        return JSONResponse(
            status_code=status_code,
            content={
                "success": False,
                "error": error_msg,
                "error_type": error_type,
                "timestamp": datetime.utcnow().isoformat()
            }
        )


@app.post("/api/kubernetes/context/switch/{context_name}")
async def switch_kubernetes_context(context_name: str):
    """Switch to a different Kubernetes context"""
    try:
        success = await kubernetes_monitor.switch_context(context_name)

        if success:
            return {
                "success": True,
                "switched_to": context_name,
                "timestamp": datetime.utcnow().isoformat()
            }
        else:
            raise HTTPException(status_code=400, detail=f"Failed to switch to context: {context_name}")

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error switching Kubernetes context: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Failed to switch context: {str(e)}")


@app.get("/api/kubernetes/cluster/info")
async def get_cluster_info():
    """Get Kubernetes cluster information"""
    try:
        cluster_info = await kubernetes_monitor.get_cluster_info()
        return {
            "cluster_info": cluster_info,
            "timestamp": datetime.utcnow().isoformat()
        }
    except Exception as e:
        logger.error(f"Error getting cluster info: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Failed to get cluster info: {str(e)}")


@app.get("/api/kubernetes/namespaces")
async def get_namespaces():
    """Get Kubernetes namespaces"""
    try:
        namespaces = await kubernetes_monitor.get_namespaces()
        return {
            "namespaces": namespaces,
            "timestamp": datetime.utcnow().isoformat()
        }
    except Exception as e:
        logger.error(f"Error getting namespaces: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Failed to get namespaces: {str(e)}")


# AWS Region Management Endpoints

@app.get("/api/aws/regions")
async def get_available_regions(validate_access: bool = False):
    """
    Get list of all available AWS regions.

    Args:
        validate_access: If True, validate actual access to each region (slower)

    Returns:
        RegionListResponse with all AWS regions and their availability status
    """
    try:
        logger.info(f"Getting AWS regions list (validate_access={validate_access})")

        regions = await aws_region_manager.get_available_regions(validate_access=validate_access)

        response = RegionListResponse(
            success=True,
            regions=regions,
            total_count=len(regions)
        )

        return response.dict()

    except Exception as e:
        error_msg = str(e)
        logger.error(f"Error getting AWS regions: {error_msg}")

        # Return structured error response
        return JSONResponse(
            status_code=500,
            content={
                "success": False,
                "error": error_msg,
                "error_type": "aws_regions_error",
                "timestamp": datetime.utcnow().isoformat()
            }
        )


@app.get("/api/kubernetes/contexts/{region}")
async def get_kubernetes_contexts_by_region(region: str):
    """
    Get Kubernetes contexts and clusters for a specific AWS region.

    Args:
        region: AWS region name (e.g., 'us-east-1')

    Returns:
        RegionContextsResponse with contexts and clusters for the region
    """
    try:
        logger.info(f"Getting Kubernetes contexts for region: {region}")

        # Validate region
        if not region or len(region) < 8:
            raise HTTPException(status_code=400, detail="Invalid region format")

        # Get contexts and clusters for the region
        contexts, clusters = await aws_region_manager.get_kubernetes_contexts_by_region(region)
        current_context = await kubernetes_monitor.get_current_context()

        response = RegionContextsResponse(
            success=True,
            region=region,
            contexts=contexts,
            clusters=clusters,
            current_context=current_context
        )

        return response.dict()

    except HTTPException:
        raise
    except Exception as e:
        error_msg = str(e)
        logger.error(f"Error getting contexts for region {region}: {error_msg}")

        return JSONResponse(
            status_code=500,
            content={
                "success": False,
                "region": region,
                "error": error_msg,
                "error_type": "kubernetes_contexts_error",
                "timestamp": datetime.utcnow().isoformat()
            }
        )


@app.get("/api/aws/regions/{region}/status")
async def get_region_status(region: str):
    """
    Get detailed status information for a specific AWS region.

    Args:
        region: AWS region name

    Returns:
        RegionStatus with detailed region information
    """
    try:
        logger.info(f"Getting status for region: {region}")

        status = await aws_region_manager.get_region_status(region)

        return {
            "success": True,
            "region_status": status.dict(),
            "timestamp": datetime.utcnow().isoformat()
        }

    except Exception as e:
        error_msg = str(e)
        logger.error(f"Error getting region status for {region}: {error_msg}")

        return JSONResponse(
            status_code=500,
            content={
                "success": False,
                "error": error_msg,
                "error_type": "region_status_error",
                "timestamp": datetime.utcnow().isoformat()
            }
        )


# Docker Service Management Endpoints

@app.post("/api/docker/start")
async def start_docker_service(force: bool = False):
    """
    Start Docker engine service.

    Args:
        force: Force start without confirmation

    Returns:
        DockerServiceResponse with operation results
    """
    try:
        logger.info(f"Starting Docker service (force={force})")

        request = DockerServiceRequest(action="start", force=force)
        response = await docker_manager.process_service_request(request)

        status_code = 200 if response.success else 500
        return JSONResponse(status_code=status_code, content=response.dict())

    except Exception as e:
        error_msg = str(e)
        logger.error(f"Error starting Docker service: {error_msg}")

        error_response = DockerServiceResponse(
            success=False,
            action="start",
            status="error",
            error=f"Start operation failed: {error_msg}",
            execution_time=0.0
        )

        return JSONResponse(status_code=500, content=error_response.dict())


@app.post("/api/docker/stop")
async def stop_docker_service(force: bool = False):
    """
    Stop Docker engine service.

    Args:
        force: Force stop without confirmation

    Returns:
        DockerServiceResponse with operation results
    """
    try:
        logger.info(f"Stopping Docker service (force={force})")

        request = DockerServiceRequest(action="stop", force=force)
        response = await docker_manager.process_service_request(request)

        status_code = 200 if response.success else 500
        return JSONResponse(status_code=status_code, content=response.dict())

    except Exception as e:
        error_msg = str(e)
        logger.error(f"Error stopping Docker service: {error_msg}")

        error_response = DockerServiceResponse(
            success=False,
            action="stop",
            status="error",
            error=f"Stop operation failed: {error_msg}",
            execution_time=0.0
        )

        return JSONResponse(status_code=500, content=error_response.dict())


@app.post("/api/docker/restart")
async def restart_docker_service(force: bool = False):
    """
    Restart Docker engine service.

    Args:
        force: Force restart without confirmation

    Returns:
        DockerServiceResponse with operation results
    """
    try:
        logger.info(f"Restarting Docker service (force={force})")

        request = DockerServiceRequest(action="restart", force=force)
        response = await docker_manager.process_service_request(request)

        status_code = 200 if response.success else 500
        return JSONResponse(status_code=status_code, content=response.dict())

    except Exception as e:
        error_msg = str(e)
        logger.error(f"Error restarting Docker service: {error_msg}")

        error_response = DockerServiceResponse(
            success=False,
            action="restart",
            status="error",
            error=f"Restart operation failed: {error_msg}",
            execution_time=0.0
        )

        return JSONResponse(status_code=500, content=error_response.dict())


@app.get("/api/docker/status")
async def get_docker_service_status():
    """
    Get Docker engine service status.

    Returns:
        DockerServiceResponse with detailed status information
    """
    try:
        logger.info("Getting Docker service status")

        status = await docker_manager.get_docker_status()

        response = DockerServiceResponse(
            success=True,
            action="status",
            status="retrieved",
            message="Docker status retrieved successfully",
            engine_status=status,
            execution_time=0.0
        )

        return response.dict()

    except Exception as e:
        error_msg = str(e)
        logger.error(f"Error getting Docker service status: {error_msg}")

        error_response = DockerServiceResponse(
            success=False,
            action="status",
            status="error",
            error=f"Status retrieval failed: {error_msg}",
            execution_time=0.0
        )

        return JSONResponse(status_code=500, content=error_response.dict())


# Kubernetes Cluster Management Endpoints

@app.post("/api/kubernetes/start/{region}")
async def start_kubernetes_cluster(region: str, cluster_name: str):
    """
    Start/connect to a Kubernetes cluster in a specific region.

    Args:
        region: AWS region name
        cluster_name: Name of the cluster to start

    Returns:
        ServiceControlResponse with operation results
    """
    try:
        logger.info(f"Starting Kubernetes cluster {cluster_name} in region {region}")

        # Validate inputs
        if not region or not cluster_name:
            raise HTTPException(status_code=400, detail="Region and cluster name are required")

        response = await kubernetes_monitor.start_cluster(region, cluster_name)

        status_code = 200 if response.success else 500
        return JSONResponse(status_code=status_code, content=response.dict())

    except HTTPException:
        raise
    except Exception as e:
        error_msg = str(e)
        logger.error(f"Error starting cluster {cluster_name}: {error_msg}")

        from .models.schemas import ServiceControlResponse
        error_response = ServiceControlResponse(
            success=False,
            action="start",
            service_type="kubernetes",
            region=region,
            cluster_name=cluster_name,
            status="error",
            error=f"Start operation failed: {error_msg}",
            execution_time=0.0
        )

        return JSONResponse(status_code=500, content=error_response.dict())


@app.post("/api/kubernetes/stop/{region}")
async def stop_kubernetes_cluster(region: str, cluster_name: str):
    """
    Stop/disconnect from a Kubernetes cluster in a specific region.

    Args:
        region: AWS region name
        cluster_name: Name of the cluster to stop

    Returns:
        ServiceControlResponse with operation results
    """
    try:
        logger.info(f"Stopping Kubernetes cluster {cluster_name} in region {region}")

        # Validate inputs
        if not region or not cluster_name:
            raise HTTPException(status_code=400, detail="Region and cluster name are required")

        response = await kubernetes_monitor.stop_cluster(region, cluster_name)

        status_code = 200 if response.success else 500
        return JSONResponse(status_code=status_code, content=response.dict())

    except HTTPException:
        raise
    except Exception as e:
        error_msg = str(e)
        logger.error(f"Error stopping cluster {cluster_name}: {error_msg}")

        from .models.schemas import ServiceControlResponse
        error_response = ServiceControlResponse(
            success=False,
            action="stop",
            service_type="kubernetes",
            region=region,
            cluster_name=cluster_name,
            status="error",
            error=f"Stop operation failed: {error_msg}",
            execution_time=0.0
        )

        return JSONResponse(status_code=500, content=error_response.dict())


@app.get("/api/kubernetes/clusters/{region}")
async def get_kubernetes_clusters_by_region(region: str, cluster_name: str = None):
    """
    Get Kubernetes clusters in a specific region.

    Args:
        region: AWS region name
        cluster_name: Optional specific cluster name to filter

    Returns:
        Dictionary with cluster information for the region
    """
    try:
        logger.info(f"Getting Kubernetes clusters for region: {region}")

        clusters = await kubernetes_monitor.get_cluster_info_by_region(region, cluster_name)

        return {
            "success": True,
            "region": region,
            "clusters": [cluster.dict() for cluster in clusters],
            "cluster_count": len(clusters),
            "timestamp": datetime.utcnow().isoformat()
        }

    except Exception as e:
        error_msg = str(e)
        logger.error(f"Error getting clusters for region {region}: {error_msg}")

        return JSONResponse(
            status_code=500,
            content={
                "success": False,
                "region": region,
                "error": error_msg,
                "error_type": "kubernetes_clusters_error",
                "timestamp": datetime.utcnow().isoformat()
            }
        )


# AWS Profile Management

@app.post("/api/aws/profile/{profile_name}")
async def set_aws_profile(profile_name: str):
    """
    Set AWS profile for all AWS operations.

    Args:
        profile_name: AWS profile name to use

    Returns:
        Dictionary with operation status
    """
    try:
        logger.info(f"Setting AWS profile to: {profile_name}")

        # Set profile for all components
        command_executor.set_aws_profile(profile_name)

        return {
            "success": True,
            "profile": profile_name,
            "message": f"AWS profile set to {profile_name}",
            "timestamp": datetime.utcnow().isoformat()
        }

    except Exception as e:
        error_msg = str(e)
        logger.error(f"Error setting AWS profile: {error_msg}")

        return JSONResponse(
            status_code=500,
            content={
                "success": False,
                "error": error_msg,
                "error_type": "aws_profile_error",
                "timestamp": datetime.utcnow().isoformat()
            }
        )


@app.get("/api/aws/profile")
async def get_current_aws_profile():
    """
    Get current AWS profile.

    Returns:
        Dictionary with current AWS profile information
    """
    try:
        profile = aws_region_manager.get_aws_profile()

        return {
            "success": True,
            "profile": profile,
            "timestamp": datetime.utcnow().isoformat()
        }

    except Exception as e:
        error_msg = str(e)
        logger.error(f"Error getting AWS profile: {error_msg}")

        return JSONResponse(
            status_code=500,
            content={
                "success": False,
                "error": error_msg,
                "error_type": "aws_profile_error",
                "timestamp": datetime.utcnow().isoformat()
            }
        )


async def _send_initial_system_status(websocket: WebSocket, connection_id: str):
    """
    Send initial system status immediately after connection to prevent 'not available' states.
    This addresses the issue where React StrictMode causes rapid reconnections before system
    info can be properly transmitted.
    """
    try:
        logger.info(f"Sending initial system status to {connection_id}")

        # Send Docker availability status
        try:
            docker_result = await command_executor.execute_command('docker', 'health')
            if docker_result['success']:
                docker_response = {
                    "type": "initial_status",
                    "category": "docker_health",
                    "requestId": "initial:docker:health",
                    "success": docker_result['success'],
                    "data": docker_result.get('data'),
                    "timestamp": datetime.utcnow().isoformat()
                }
                await websocket.send_text(json.dumps(docker_response))
                logger.debug(f"Sent Docker health status to {connection_id}")
        except Exception as e:
            logger.warning(
                f"Failed to send initial Docker status to {connection_id}: {str(e)}")

        # Send services availability status
        try:
            services_result = await command_executor.execute_command('services', 'availability')
            if services_result['success']:
                services_response = {
                    "type": "initial_status",
                    "category": "services_availability",
                    "requestId": "initial:services:availability",
                    "success": services_result['success'],
                    "data": services_result.get('data'),
                    "timestamp": datetime.utcnow().isoformat()
                }
                await websocket.send_text(json.dumps(services_response))
                logger.debug(f"Sent services availability to {connection_id}")
        except Exception as e:
            logger.warning(
                f"Failed to send initial services status to {connection_id}: {str(e)}")

        # Send system info
        try:
            system_result = await command_executor.execute_command('system', 'info')
            if system_result['success']:
                system_response = {
                    "type": "initial_status",
                    "category": "system_info",
                    "requestId": "initial:system:info",
                    "success": system_result['success'],
                    "data": system_result.get('data'),
                    "timestamp": datetime.utcnow().isoformat()
                }
                await websocket.send_text(json.dumps(system_response))
                logger.debug(f"Sent system info to {connection_id}")
        except Exception as e:
            logger.warning(
                f"Failed to send initial system info to {connection_id}: {str(e)}")

        # Send Kubernetes health status
        try:
            k8s_result = await command_executor.execute_command('kubernetes', 'health')
            if k8s_result['success']:
                k8s_response = {
                    "type": "initial_status",
                    "category": "kubernetes_health",
                    "requestId": "initial:kubernetes:health",
                    "success": k8s_result['success'],
                    "data": k8s_result.get('data'),
                    "timestamp": datetime.utcnow().isoformat()
                }
                await websocket.send_text(json.dumps(k8s_response))
                logger.debug(
                    f"Sent Kubernetes health status to {connection_id}")
        except Exception as e:
            logger.warning(
                f"Failed to send initial Kubernetes status to {connection_id}: {str(e)}")

        logger.info(f"Initial system status sent to {connection_id}")

    except WebSocketDisconnect:
        logger.debug(
            f"Client {connection_id} disconnected during initial status send")
    except Exception as e:
        logger.error(
            f"Error sending initial system status to {connection_id}: {str(e)}")


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """Main WebSocket endpoint for real-time monitoring"""
    connection_id = str(uuid.uuid4())

    try:
        # Accept connection
        await connection_manager.connect(websocket, connection_id)
        logger.info(f"WebSocket connection established: {connection_id}")

        # Send welcome message
        welcome_message = {
            "type": "connection",
            "connection_id": connection_id,
            "message": "Connected to MiniPrem Monitor",
            "timestamp": datetime.utcnow().isoformat()
        }
        await websocket.send_text(json.dumps(welcome_message))

        # Small delay to handle React StrictMode rapid mount/unmount cycles
        await asyncio.sleep(0.1)

        # Check if connection is still active after delay (React StrictMode handling)
        if connection_id not in connection_manager.active_connections:
            logger.debug(
                f"Connection {connection_id} closed during initialization (React StrictMode)")
            return

        # Immediately send critical system info to prevent "not available" states
        await _send_initial_system_status(websocket, connection_id)

        # Start change detection if this is the first connection
        if len(connection_manager.active_connections) == 1:
            await connection_manager.start_change_detection()

        # Keep connection alive - handle messages asynchronously
        try:
            while True:
                # Use a non-blocking approach with a short timeout
                try:
                    # Check for incoming messages without blocking indefinitely
                    message = await asyncio.wait_for(
                        websocket.receive_text(),
                        timeout=1.0  # Short timeout to allow other async tasks
                    )
                    # Handle the message
                    await connection_manager.handle_message(websocket, connection_id, message)

                except asyncio.TimeoutError:
                    # No message received, continue the loop
                    # This allows subscription tasks to run
                    continue

                except WebSocketDisconnect as e:
                    # Handle different disconnect codes appropriately
                    _log_websocket_disconnect(
                        connection_id, e, "during message loop")
                    break

        except Exception as e:
            # Only log unexpected errors during message handling
            logger.error(
                f"Unexpected error in WebSocket message loop for {connection_id}: {str(e)}")
            # Exception will naturally exit the while loop

    except WebSocketDisconnect as e:
        # Handle disconnection during initial connection or welcome message
        _log_websocket_disconnect(connection_id, e, "during connection setup")
    except ConnectionResetError:
        # Client forcibly closed connection - log as debug since it's normal behavior
        logger.debug(f"WebSocket connection {connection_id} reset by client")
    except Exception as e:
        # Only log truly unexpected errors (not connection-related)
        if not any(keyword in str(e).lower() for keyword in ['connection', 'websocket', 'disconnect', 'closed']):
            logger.error(
                f"Unexpected WebSocket error for {connection_id}: {str(e)}")
        else:
            logger.debug(
                f"WebSocket connection issue for {connection_id}: {str(e)}")
    finally:
        # Always clean up the connection
        connection_manager.disconnect(connection_id)

        # Stop change detection if no more active connections
        if len(connection_manager.active_connections) == 0:
            await connection_manager.stop_change_detection()

        logger.debug(f"WebSocket connection {connection_id} cleanup completed")


# Error handlers
@app.exception_handler(Exception)
async def global_exception_handler(request, exc):
    """Global exception handler"""
    logger.error(f"Unhandled exception: {str(exc)}")
    return JSONResponse(
        status_code=500,
        content={
            "error": "Internal server error",
            "timestamp": datetime.utcnow().isoformat()
        }
    )

if __name__ == "__main__":
    # Run the server
    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
        log_level="info",
        access_log=True
    )
