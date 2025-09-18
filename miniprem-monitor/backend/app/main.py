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
from .security.command_executor import CommandExecutor

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
