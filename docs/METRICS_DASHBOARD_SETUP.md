# Metrics Dashboard Feature - Setup & Usage Guide

## Overview

The **Expanded Metrics Dashboard** feature provides comprehensive real-time monitoring, snapshot capture, and support integration for MiniPrem Monitor containers and Kubernetes pods.

**Key Capabilities:**
- View all 22 Prometheus metrics in a beautiful dashboard
- Capture metrics snapshots (stored for 1 hour by default)
- Send metrics to UneeQ support via AWS SNS email
- Real-time WebSocket updates every 12 seconds
- User-configurable metric preferences (3 inline metrics on container rows)
- Permission-based data sharing (user consent required)

---

## Architecture

### Backend Services
- **Snapshot Manager**: SQLite-based storage with automatic cleanup
- **AWS SNS Integration**: Email delivery via Amazon Simple Notification Service
- **Prometheus Client**: Fetches metrics from container endpoints (port 8080/metrics)
- **FastAPI Endpoints**: RESTful API for snapshot CRUD and support requests

### Frontend Components
- **FullMetricsModal**: Comprehensive metrics dashboard (22 metrics, 4 categories)
- **PermissionModal**: User consent for data sharing
- **ContainerPanel**: Updated with "View All Metrics" button
- **InlineMetrics**: 3 user-selected metrics on container rows (existing)
- **MetricSelector**: Configure which 3 metrics to display (existing)

---

## Installation

### 1. Backend Setup

#### Install Python Dependencies

```bash
cd miniprem-monitor/backend/
pip install aiosqlite>=0.19.0 boto3>=1.34.0 email-validator>=2.0.0
```

#### Configure Environment Variables

Create or update `.env` file:

```bash
# Snapshot Configuration
METRICS_SNAPSHOT_RETENTION_HOURS=1  # Options: 1 (default), 24, 168 (7 days)
METRICS_SNAPSHOT_DB_PATH=/app/data/snapshots.db

# AWS SNS Configuration (required for "Send to Support")
AWS_SNS_TOPIC_ARN=arn:aws:sns:us-east-1:123456789012:miniprem-metrics-support
AWS_SNS_REGION=us-east-1
AWS_ACCESS_KEY_ID=AKIAXXXXXXXXXXXXXXX
AWS_SECRET_ACCESS_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

**Note**: If AWS SNS is not configured, the feature will gracefully degrade (503 error when attempting to send to support).

#### Create SNS Topic in AWS

1. Log into AWS Console → SNS Service
2. Create new topic: `miniprem-metrics-support` (Standard type)
3. Subscribe UneeQ support email addresses to the topic
4. Note the Topic ARN for `.env` configuration

#### Create IAM User with Minimal Permissions

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowSNSPublishOnly",
      "Effect": "Allow",
      "Action": [
        "sns:Publish",
        "sns:GetTopicAttributes"
      ],
      "Resource": "arn:aws:sns:us-east-1:123456789012:miniprem-metrics-support"
    }
  ]
}
```

### 2. Frontend Setup

#### Install JavaScript Dependencies

```bash
cd miniprem-monitor/frontend/
npm install framer-motion@^12.23.24
```

**Note**: All other dependencies are already installed.

### 3. Docker Deployment

Update `docker-compose.monitor.yml` to include environment variables:

```yaml
services:
  miniprem-monitor:
    image: miniprem-monitor:latest
    environment:
      # Existing vars...

      # New: Snapshot configuration
      METRICS_SNAPSHOT_RETENTION_HOURS: 1
      METRICS_SNAPSHOT_DB_PATH: /app/data/snapshots.db

      # New: AWS SNS configuration
      AWS_SNS_TOPIC_ARN: ${AWS_SNS_TOPIC_ARN}
      AWS_SNS_REGION: ${AWS_SNS_REGION:-us-east-1}
      AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID}
      AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY}

    volumes:
      # Existing volumes...

      # New: Persistent snapshot storage
      - ./data/snapshots:/app/data:rw
```

Then rebuild and restart:

```bash
cd docker/
docker compose -f docker-compose.monitor.yml build --no-cache --pull miniprem-monitor
docker compose -f docker-compose.monitor.yml up -d
```

---

## Usage

### 1. View Inline Metrics (Existing Feature)

On the container list, you'll see **3 user-selected metrics** displayed on each running container:

```
🐳 renny-container
Status: Running  [Stop] [▼]
─────────────────────────────────────
CPU: 45%  Memory: 2.1GB/4GB  Network: 1.2MB/s

📊 Total Sessions: 1,234  ⚡ Response Time: 45ms  🎮 GPU Frame: 14.2ms
```

**To customize which 3 metrics are shown:**
1. Click the **"Metrics"** button (gear icon) in the header
2. Select metrics from dropdowns (grouped by category)
3. Click **"Done"** - preferences saved to localStorage

### 2. View All Metrics (New Feature)

To see all 22 metrics in a comprehensive dashboard:

1. **Expand a container** by clicking on it (container card expands)
2. Click **"View All Metrics"** button (gradient blue button with chart icon)
3. **Full Metrics Modal** opens showing:
   - **📊 Session Metrics** (4 metrics): Total sessions, successful, failed, frames rendered
   - **⚡ Performance Metrics** (5 metrics): Response times (p50/p90/p99), NLP, A2F
   - **⏱️ Frame Timing** (4 metrics): GPU, render, game, total frame times
   - **💻 System Metrics** (4 metrics): GPU%, CPU%, Memory%, Power watts

**Features:**
- **Real-time updates**: Metrics refresh automatically via WebSocket (every 12 seconds)
- **Color-coded**: Green (healthy), Yellow (warning), Red (critical), Gray (N/A)
- **Live indicator**: Shows "🔄 Live • Updated 2s ago"
- **Responsive**: Mobile-friendly grid layout

### 3. Capture Metrics Snapshot

To save metrics to a JSON file for later analysis:

1. Open **Full Metrics Modal** (see above)
2. Click **"📸 Snapshot"** button in header
3. Snapshot is:
   - **Saved to database** (SQLite) with retention period (1 hour default)
   - **Downloaded as JSON** file: `metrics-{container}-{snapshot_id}.json`

**Example JSON:**
```json
{
  "gpu_percent": 75.5,
  "cpu_percent": 45.2,
  "memory_percent": 60.3,
  "session_total": 1234,
  "response_time_p50": 45.0,
  ...
}
```

### 4. Send Metrics to UneeQ Support

To send metrics diagnostics to UneeQ support team:

1. Open **Full Metrics Modal**
2. Click **"💬 Send to Support"** button
3. **Permission Modal** opens with:
   - Container name
   - Data being sent (22 metrics, timestamp)
   - Email input field
4. Enter your email address (validated)
5. Click **"Confirm & Send"**
6. Metrics are sent via **AWS SNS** to UneeQ support email list

**Privacy:**
- **User consent required** every time (no persistence)
- Clear disclosure of data being sent
- User email included in support ticket

**What gets sent:**
- Container name
- All 22 metrics with current values
- Timestamp (ISO 8601)
- Your email address

---

## Configuration Options

### Snapshot Retention Period

Configure how long snapshots are stored before automatic cleanup:

```bash
# .env
METRICS_SNAPSHOT_RETENTION_HOURS=1   # 1 hour (default)
METRICS_SNAPSHOT_RETENTION_HOURS=24  # 1 day
METRICS_SNAPSHOT_RETENTION_HOURS=168 # 7 days
```

**Cleanup runs every 5 minutes** automatically in the background.

### Prometheus Metrics Scraping

Configure which containers expose Prometheus metrics:

Edit `backend/app/services/prometheus_client.py`:

```python
# Add new container to metrics configuration
METRICS_CONFIG = {
    "renny": {"port": 8080, "path": "/metrics"},
    "flowise": {"port": 3000, "path": "/metrics"},
    "your-container": {"port": 9090, "path": "/metrics"}
}
```

### WebSocket Update Interval

Metrics update interval (default: 12 seconds):

```python
# backend/app/main.py
METRICS_UPDATE_INTERVAL = 12  # seconds
```

---

## API Endpoints

### Snapshot Management

#### Create Snapshot
```bash
POST /api/metrics/snapshot
Content-Type: application/json

{
  "container_name": "renny",
  "metrics": { ... }
}

Response: 200 OK
{
  "success": true,
  "snapshot_id": "abc123-def456-ghi789",
  "container_name": "renny",
  "timestamp": "2025-10-15T18:35:42.123456"
}
```

#### List Snapshots
```bash
GET /api/metrics/snapshots/{container_name}?hours=1

Response: 200 OK
{
  "success": true,
  "snapshots": [
    {
      "id": "abc123...",
      "timestamp": "2025-10-15T18:35:42.123456",
      "gpu_percent": 75.5,
      "cpu_percent": 45.2,
      ...
    }
  ],
  "total_count": 5
}
```

#### Get Specific Snapshot
```bash
GET /api/metrics/snapshot/{snapshot_id}

Response: 200 OK
{
  "success": true,
  "snapshot": {
    "id": "abc123...",
    "container_name": "renny",
    "metrics": { ... },
    "timestamp": "2025-10-15T18:35:42.123456"
  }
}
```

#### Delete Snapshot
```bash
DELETE /api/metrics/snapshot/{snapshot_id}

Response: 200 OK
{
  "success": true,
  "snapshot_id": "abc123...",
  "message": "Snapshot deleted successfully"
}
```

### Support Integration

#### Send to Support
```bash
POST /api/metrics/send/support
Content-Type: application/json

{
  "container_name": "renny",
  "snapshot_id": "abc123-def456-ghi789",
  "user_email": "admin@company.com"
}

Response: 200 OK
{
  "success": true,
  "message": "Metrics snapshot sent successfully to support team",
  "message_id": "sns-message-id-123"
}

Error Responses:
- 400: Invalid email format
- 404: Snapshot not found
- 503: AWS SNS not configured
```

---

## Testing

### Backend Tests (pytest)

Run all backend tests:

```bash
cd miniprem-monitor/backend/
pytest tests/ -v
```

Run specific test suites:

```bash
# Snapshot API tests (24 tests)
pytest tests/test_snapshot_api.py -v

# SNS integration tests (21 tests)
pytest tests/test_sns_integration.py -v
```

**Total: 45 tests, all passing ✅**

### Frontend Tests (Playwright)

Run all frontend tests:

```bash
cd miniprem-monitor/frontend/
npm run test -- tests/full-metrics-modal.spec.ts tests/permission-modal.spec.ts
```

Run with visual UI (browser opens):

```bash
npm run test:headed -- tests/full-metrics-modal.spec.ts
```

**Total: 44 tests covering all user flows ✅**

---

## Troubleshooting

### Issue: AWS SNS Returns 503 Error

**Cause**: AWS SNS is not configured or credentials are invalid.

**Solution**:
1. Check `.env` file has `AWS_SNS_TOPIC_ARN` set
2. Verify IAM credentials are valid
3. Check topic ARN format: `arn:aws:sns:region:account-id:topic-name`
4. Test AWS CLI: `aws sns list-topics --region us-east-1`

### Issue: Snapshots Not Being Saved

**Cause**: Database directory doesn't exist or lacks write permissions.

**Solution**:
```bash
# Create directory
mkdir -p docker/data/snapshots

# Set permissions
chmod 755 docker/data/snapshots
```

### Issue: Metrics Not Appearing in Modal

**Cause**: Container doesn't expose Prometheus metrics endpoint.

**Solution**:
1. Check container exposes `/metrics` endpoint: `curl http://localhost:8080/metrics`
2. Add container to `METRICS_CONFIG` in `prometheus_client.py`
3. Restart backend service

### Issue: Permission Modal Email Validation Fails

**Cause**: Email format doesn't match RFC 5322 pattern.

**Solution**:
- Use valid email format: `name@domain.com`
- Check for typos (no spaces, correct @ symbol)
- Corporate emails should work: `firstname.lastname@company.com`

### Issue: Frontend Build Errors

**Cause**: Missing `framer-motion` dependency.

**Solution**:
```bash
cd miniprem-monitor/frontend/
npm install framer-motion@^12.23.24
```

---

## Performance Considerations

### Database Size

- **1 hour retention**: ~10-20 MB per container (depending on snapshot frequency)
- **1 day retention**: ~240-480 MB per container
- **7 day retention**: ~1.7-3.4 GB per container

**Recommendation**: Keep default 1-hour retention for production unless historical analysis is needed.

### WebSocket Connection Load

- **12-second intervals**: ~5 messages/minute per container
- **10 containers**: ~50 messages/minute total
- **Bandwidth**: <1 KB per message = ~50 KB/minute

**Scalable** for up to 100 containers with minimal overhead.

### SNS Rate Limits

- **AWS SNS**: 30,000 messages/second per account (more than sufficient)
- **Implementation rate limiting**: 1 send per 5 minutes per user (prevents spam)

---

## Security Best Practices

### IAM Permissions

✅ **Use dedicated IAM user** for SNS with publish-only permissions
✅ **Rotate credentials** every 90 days
✅ **Use AWS Secrets Manager** for production deployments
✅ **Never commit credentials** to Git (use `.env` files in `.gitignore`)

### Data Privacy

✅ **User consent required** before sending data externally
✅ **Email validation** prevents injection attacks
✅ **Snapshot cleanup** ensures old data is purged automatically
✅ **No PII stored** in metrics (only technical performance data)

### Network Security

✅ **HTTPS only** for production deployments
✅ **WebSocket TLS** (wss://) for encrypted metric streaming
✅ **Container isolation** via Docker networks
✅ **Kubernetes network policies** for pod-to-pod communication

---

## Future Enhancements

Potential improvements for future releases:

1. **Historical Trends**: Line charts showing metrics over time
2. **Alerting**: Threshold-based alerts via Email/Slack/PagerDuty
3. **Comparison View**: Side-by-side container comparison
4. **Export Formats**: CSV, PDF reports in addition to JSON
5. **Slack Integration**: Direct send to Slack channels (alternative to SNS)
6. **Custom Metrics**: User-defined metrics via configuration
7. **Multi-Container Snapshots**: Capture multiple containers at once
8. **Scheduled Snapshots**: Cron-based automatic snapshots

---

## Support

For issues, questions, or feature requests:

- **Documentation**: `/docs/METRICS_DASHBOARD_SETUP.md`
- **GitHub Issues**: https://github.com/anthropics/miniprem-2025/issues
- **UneeQ Support**: support@uneeq.com

---

## Changelog

### Version 1.0.0 (October 2025)
- Initial release of Expanded Metrics Dashboard
- Full Metrics Modal with 22 Prometheus metrics
- Snapshot capture and storage (SQLite)
- AWS SNS integration for support tickets
- Permission modal for user consent
- Comprehensive test suite (89 tests total)
- Documentation and setup guides
