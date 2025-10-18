# MiniPrem Monitor Backend Tests

Comprehensive pytest test suite for MiniPrem Monitor backend APIs.

## Test Files

- **`test_snapshot_api.py`**: Tests for metrics snapshot API endpoints (create, list, retrieve, delete)
- **`test_sns_integration.py`**: Tests for AWS SNS integration and support metrics sending
- **`conftest.py`**: Shared fixtures and test configuration

## Running Tests

### Run All Tests
```bash
cd /Users/tyler/Software_Development/miniprem-2025/miniprem-monitor/backend
pytest tests/
```

### Run Specific Test File
```bash
# Snapshot API tests only
pytest tests/test_snapshot_api.py

# SNS integration tests only
pytest tests/test_sns_integration.py
```

### Run Tests with Verbose Output
```bash
pytest tests/ -v
```

### Run Tests with Coverage Report
```bash
pytest tests/ --cov=app --cov-report=html
```

### Run Specific Test Class or Function
```bash
# Run specific test class
pytest tests/test_snapshot_api.py::TestSnapshotCreation

# Run specific test function
pytest tests/test_snapshot_api.py::TestSnapshotCreation::test_create_snapshot_success
```

### Run Tests in Parallel (faster)
```bash
pytest tests/ -n auto  # Requires pytest-xdist
```

## Test Coverage

### Snapshot API Tests (`test_snapshot_api.py`)

**TestSnapshotCreation**
- ✅ Successful snapshot creation with full metrics
- ✅ Snapshot creation with partial/sparse metrics
- ✅ Missing container_name validation error (422)
- ✅ Missing metrics validation error (422)
- ✅ Empty container name validation error (422)
- ✅ Invalid JSON payload handling (422)
- ✅ Null values in metrics handling
- ✅ Multiple snapshots for same container
- ✅ Unique snapshot ID generation

**TestSnapshotListing**
- ✅ List snapshots for specific container
- ✅ Empty list for non-existent container
- ✅ Custom time window filtering (hours parameter)
- ✅ Snapshot ordering (newest first)
- ✅ Preview data structure validation

**TestSnapshotRetrieval**
- ✅ Retrieve specific snapshot by ID
- ✅ Non-existent snapshot (404 error)
- ✅ Invalid UUID format handling
- ✅ Complete metrics data validation

**TestSnapshotDeletion**
- ✅ Successful snapshot deletion
- ✅ Non-existent snapshot deletion (404 error)
- ✅ Idempotency check (double deletion)
- ✅ Verification of deletion completion

**TestSnapshotEdgeCases**
- ✅ Large metrics payload handling
- ✅ Special characters in container names
- ✅ Concurrent snapshot creation
- ✅ Extreme metric values (0, 100, large numbers)

**TestSnapshotIntegration**
- ✅ Full lifecycle: create → list → retrieve → delete
- ✅ Multi-container isolation

### SNS Integration Tests (`test_sns_integration.py`)

**TestSendMetricsToSupport**
- ✅ Successful metrics send via SNS
- ✅ SNS not configured error (503)
- ✅ Snapshot not found error (404)
- ✅ Invalid email validation (422)
- ✅ Missing required fields validation (422)
- ✅ SNS publish failure handling (500)
- ✅ Valid email format acceptance

**TestAwsSnsSender**
- ✅ Successful AwsSnsSender initialization
- ✅ Missing AWS_SNS_TOPIC_ARN error
- ✅ Default region fallback (us-east-1)
- ✅ Successful SNS publish with correct parameters
- ✅ AWS ClientError handling
- ✅ BotoCoreError handling
- ✅ Generic exception handling
- ✅ Message formatting with complete metrics
- ✅ Message formatting with missing values
- ✅ Configuration validation success
- ✅ Configuration validation - topic not found
- ✅ Configuration validation - access denied

**TestSNSIntegration**
- ✅ End-to-end support workflow
- ✅ Multiple snapshots to support

## Test Dependencies

All dependencies are included in `requirements.txt`:

```txt
pytest==7.4.3
pytest-asyncio==0.23.2
aiosqlite>=0.19.0
boto3>=1.34.0
email-validator>=2.0.0
fastapi==0.108.0
```

Optional dependencies for enhanced testing:

```bash
# Install test coverage tools
pip install pytest-cov

# Install parallel test execution
pip install pytest-xdist

# Install test reporting
pip install pytest-html
```

## Environment Configuration

Tests use mock AWS SNS clients and temporary databases, so no real AWS credentials are required.

However, if you want to test with real AWS SNS (not recommended for unit tests):

```bash
export AWS_SNS_TOPIC_ARN="arn:aws:sns:us-east-1:123456789012:your-topic"
export AWS_SNS_REGION="us-east-1"
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
```

## Test Database

Tests use temporary SQLite databases created in `/tmp/` that are automatically cleaned up after each test. No manual database setup required.

## Continuous Integration

Example GitHub Actions workflow:

```yaml
name: Backend Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.10'
      - name: Install dependencies
        run: |
          cd miniprem-monitor/backend
          pip install -r requirements.txt
      - name: Run tests
        run: |
          cd miniprem-monitor/backend
          pytest tests/ -v --cov=app --cov-report=xml
      - name: Upload coverage
        uses: codecov/codecov-action@v3
```

## Writing New Tests

### Basic Test Structure

```python
def test_my_feature(client: TestClient, sample_metrics: dict):
    """
    Test description following Google-style docstrings.

    Verifies that specific behavior works correctly.
    """
    response = client.post("/api/endpoint", json={"data": "value"})
    assert response.status_code == 200
    assert response.json()["success"] is True
```

### Using Fixtures

```python
@pytest.mark.asyncio
async def test_with_database(snapshot_manager: SnapshotManager, prometheus_metrics: PrometheusMetrics):
    """Test using database fixture."""
    snapshot = await snapshot_manager.create_snapshot(
        "test-id",
        "test-container",
        prometheus_metrics
    )
    assert snapshot.id == "test-id"
```

### Mocking AWS SNS

```python
def test_with_sns_mock(mock_sns_client):
    """Test using mocked SNS client."""
    with patch("boto3.client", return_value=mock_sns_client):
        sender = AwsSnsSender()
        # ... test code
        mock_sns_client.publish.assert_called_once()
```

## Best Practices

1. **Isolation**: Each test should be independent and not rely on other tests
2. **Cleanup**: Use fixtures that automatically clean up resources
3. **Descriptive Names**: Test names should clearly describe what they test
4. **Docstrings**: Include clear docstrings explaining test purpose
5. **Edge Cases**: Test boundary conditions and error scenarios
6. **Mocking**: Mock external services (AWS, databases) for unit tests
7. **Assertions**: Use specific assertions with helpful error messages

## Troubleshooting

### Tests Fail with "No module named 'app'"

Make sure you're in the backend directory:
```bash
cd /Users/tyler/Software_Development/miniprem-2025/miniprem-monitor/backend
```

### Database Locked Errors

Temporary databases should auto-cleanup. If issues persist:
```bash
rm -f /tmp/test_*.db
```

### Async Test Warnings

Make sure `pytest-asyncio` is installed:
```bash
pip install pytest-asyncio==0.23.2
```

### Import Errors

Ensure all dependencies are installed:
```bash
pip install -r requirements.txt
```

## Test Statistics

- **Total Test Files**: 2
- **Total Test Functions**: 50+
- **Test Classes**: 11
- **Expected Coverage**: 90%+ for snapshot_manager.py and aws_sns_sender.py
- **Test Execution Time**: ~5-10 seconds (with mocked AWS calls)
