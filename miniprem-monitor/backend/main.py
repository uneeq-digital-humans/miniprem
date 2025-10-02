"""
FastAPI backend for monitoring Docker containers and Kubernetes pods.

This module provides REST API endpoints and WebSocket connections for real-time
monitoring of containerized applications and Kubernetes resources.
"""

from contextlib import asynccontextmanager
from typing import Dict, Any, List
import asyncio
import logging

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from docker_monitor import DockerMonitor
from kubernetes_monitor import KubernetesMonitor
from websocket_handler import WebSocketManager


# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


# Global instances
docker_monitor = DockerMonitor()
k8s_monitor = KubernetesMonitor()
websocket_manager = WebSocketManager()


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Application lifespan manager for startup and shutdown tasks.

    Args:
        app: FastAPI application instance

    Yields:
        None: Application runs during this yield
    """
    # Startup
    logger.info("Starting MiniPrem Monitor Backend")

    # Start WebSocket background task
    task = asyncio.create_task(websocket_manager.broadcast_updates())

    try:
        yield
    finally:
        # Shutdown
        logger.info("Shutting down MiniPrem Monitor Backend")
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass


# FastAPI application instance
app = FastAPI(
    title="MiniPrem Monitor API",
    description="REST API for monitoring Docker containers and Kubernetes pods",
    version="1.0.0",
    lifespan=lifespan
)

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(Exception)
async def global_exception_handler(request, exc: Exception) -> JSONResponse:
    """
    Global exception handler for unhandled exceptions.

    Args:
        request: FastAPI request object
        exc: Exception that was raised

    Returns:
        JSONResponse: Error response with details
    """
    logger.error(f"Unhandled exception: {str(exc)}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal server error", "error": str(exc)}
    )


# Health check endpoint
@app.get("/health")
async def health_check() -> Dict[str, str]:
    """
    Health check endpoint to verify API availability.

    Returns:
        Dict[str, str]: Status information
    """
    return {"status": "healthy", "service": "miniprem-monitor"}


# Docker endpoints
@app.get("/api/docker/containers")
async def get_docker_containers() -> Dict[str, Any]:
    """
    Get all Docker containers with their status information.

    Returns:
        Dict[str, Any]: Container information and metadata

    Raises:
        HTTPException: If Docker command execution fails
    """
    try:
        containers = await docker_monitor.get_containers()
        return {
            "success": True,
            "data": containers,
            "count": len(containers)
        }
    except Exception as e:
        logger.error(f"Failed to get Docker containers: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/docker/images")
async def get_docker_images() -> Dict[str, Any]:
    """
    Get all Docker images available on the system.

    Returns:
        Dict[str, Any]: Image information and metadata

    Raises:
        HTTPException: If Docker command execution fails
    """
    try:
        images = await docker_monitor.get_images()
        return {
            "success": True,
            "data": images,
            "count": len(images)
        }
    except Exception as e:
        logger.error(f"Failed to get Docker images: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/docker/stats")
async def get_docker_stats() -> Dict[str, Any]:
    """
    Get Docker container resource usage statistics.

    Returns:
        Dict[str, Any]: Resource usage statistics for all containers

    Raises:
        HTTPException: If Docker command execution fails
    """
    try:
        stats = await docker_monitor.get_stats()
        return {
            "success": True,
            "data": stats,
            "count": len(stats)
        }
    except Exception as e:
        logger.error(f"Failed to get Docker stats: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


# Kubernetes endpoints
@app.get("/api/kubernetes/pods")
async def get_kubernetes_pods(namespace: str = None) -> Dict[str, Any]:
    """
    Get all Kubernetes pods across namespaces or in a specific namespace.

    Args:
        namespace: Optional namespace filter

    Returns:
        Dict[str, Any]: Pod information and metadata

    Raises:
        HTTPException: If kubectl command execution fails
    """
    try:
        pods = await k8s_monitor.get_pods(namespace)
        return {
            "success": True,
            "data": pods,
            "count": len(pods)
        }
    except Exception as e:
        logger.error(f"Failed to get Kubernetes pods: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/kubernetes/services")
async def get_kubernetes_services(namespace: str = None) -> Dict[str, Any]:
    """
    Get all Kubernetes services across namespaces or in a specific namespace.

    Args:
        namespace: Optional namespace filter

    Returns:
        Dict[str, Any]: Service information and metadata

    Raises:
        HTTPException: If kubectl command execution fails
    """
    try:
        services = await k8s_monitor.get_services(namespace)
        return {
            "success": True,
            "data": services,
            "count": len(services)
        }
    except Exception as e:
        logger.error(f"Failed to get Kubernetes services: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/kubernetes/nodes")
async def get_kubernetes_nodes() -> Dict[str, Any]:
    """
    Get all Kubernetes nodes with their status information.

    Returns:
        Dict[str, Any]: Node information and metadata

    Raises:
        HTTPException: If kubectl command execution fails
    """
    try:
        nodes = await k8s_monitor.get_nodes()
        return {
            "success": True,
            "data": nodes,
            "count": len(nodes)
        }
    except Exception as e:
        logger.error(f"Failed to get Kubernetes nodes: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


# WebSocket endpoint
@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """
    WebSocket endpoint for real-time monitoring updates.

    Args:
        websocket: WebSocket connection instance

    Raises:
        WebSocketDisconnect: When client disconnects
    """
    await websocket.accept()
    client_id = await websocket_manager.connect(websocket)

    try:
        while True:
            # Keep connection alive by receiving client messages
            try:
                message = await asyncio.wait_for(websocket.receive_text(), timeout=1.0)
                logger.debug(f"Received message from client {client_id}: {message}")
            except asyncio.TimeoutError:
                # No message received, continue the loop
                continue

    except WebSocketDisconnect:
        logger.info(f"Client {client_id} disconnected")
        websocket_manager.disconnect(client_id)
    except Exception as e:
        logger.error(f"WebSocket error for client {client_id}: {str(e)}")
        websocket_manager.disconnect(client_id)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
        log_level="info"
    )