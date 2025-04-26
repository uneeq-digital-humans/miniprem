/**
 * WebSocket connection logging middleware
 */
function logWebSocketConnection(req, socket, head) {
  const container = req.url.split('/').pop();
  console.log(`WebSocket connection attempt for container: ${container}`);
}

/**
 * Error handling middleware for Express
 */
function errorHandler(err, req, res, next) {
  console.error(`Error processing request: ${err.message}`);
  res.status(500).json({
    error: 'Server error',
    message: process.env.NODE_ENV === 'production' ? 'An internal server error occurred' : err.message
  });
}

/**
 * CORS headers middleware
 */
function corsMiddleware(req, res, next) {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  
  if (req.method === 'OPTIONS') {
    return res.sendStatus(200);
  }
  
  next();
}

module.exports = {
  logWebSocketConnection,
  errorHandler,
  corsMiddleware
};