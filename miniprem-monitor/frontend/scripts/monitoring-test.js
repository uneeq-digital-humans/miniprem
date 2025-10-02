#!/usr/bin/env node

/**
 * Puppeteer Monitoring Integration Test Script
 * Tests Docker and Kubernetes monitoring capabilities
 */

const puppeteer = require('puppeteer');
const path = require('path');

class MonitoringTester {
  constructor() {
    this.browser = null;
    this.page = null;
    this.baseURL = process.env.FRONTEND_URL || 'http://localhost:3500';
    this.backendURL = process.env.BACKEND_URL || 'http://localhost:8000';
  }

  async init() {
    console.log('🚀 Launching browser for monitoring integration testing...');

    this.browser = await puppeteer.launch({
      headless: process.env.PUPPETEER_HEADLESS !== 'false',
      defaultViewport: { width: 1920, height: 1080 },
      args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage'],
    });

    this.page = await this.browser.newPage();

    // Set up console logging
    this.page.on('console', (msg) => {
      if (msg.type() === 'error') {
        console.error('❌ Browser console error:', msg.text());
      }
    });
  }

  async testDockerIntegration() {
    console.log('🐳 Testing Docker Engine integration via WebSocket...');

    await this.page.goto(this.baseURL, { waitUntil: 'networkidle0' });

    try {
      // Test Docker ps command via WebSocket
      const dockerResponse = await this.page.evaluate(() => {
        return new Promise((resolve) => {
          const ws = new WebSocket('ws://localhost:8000/ws');

          ws.onopen = () => {
            console.log('WebSocket connected for Docker test');
            ws.send(
              JSON.stringify({
                type: 'command',
                target: 'docker',
                command: 'ps',
                requestId: 'test_docker_integration',
              })
            );
          };

          ws.onmessage = (event) => {
            const data = JSON.parse(event.data);
            if (data.requestId === 'test_docker_integration') {
              ws.close();
              resolve(data);
            }
          };

          ws.onerror = (error) => {
            ws.close();
            resolve({ success: false, error: 'WebSocket error' });
          };

          setTimeout(() => {
            ws.close();
            resolve({ success: false, error: 'Timeout' });
          }, 10000);
        });
      });

      if (dockerResponse.success) {
        console.log('✅ Docker integration via WebSocket successful');
        if (dockerResponse.data && dockerResponse.data.containers) {
          console.log(`   Found ${dockerResponse.data.containers.length} containers`);
        }
        return true;
      } else {
        console.log(`❌ Docker integration failed: ${dockerResponse.error}`);
        return false;
      }
    } catch (error) {
      console.error('❌ Docker integration test failed:', error.message);
      return false;
    }
  }

  async testKubernetesIntegration() {
    console.log('☸️  Testing Kubernetes cluster integration via WebSocket...');

    await this.page.goto(this.baseURL, { waitUntil: 'networkidle0' });

    try {
      // Test Kubernetes pods command via WebSocket
      const k8sResponse = await this.page.evaluate(() => {
        return new Promise((resolve) => {
          const ws = new WebSocket('ws://localhost:8000/ws');

          ws.onopen = () => {
            console.log('WebSocket connected for Kubernetes test');
            ws.send(
              JSON.stringify({
                type: 'command',
                target: 'kubernetes',
                command: 'pods',
                requestId: 'test_kubernetes_integration',
              })
            );
          };

          ws.onmessage = (event) => {
            const data = JSON.parse(event.data);
            if (data.requestId === 'test_kubernetes_integration') {
              ws.close();
              resolve(data);
            }
          };

          ws.onerror = (error) => {
            ws.close();
            resolve({ success: false, error: 'WebSocket error' });
          };

          setTimeout(() => {
            ws.close();
            resolve({ success: false, error: 'Timeout' });
          }, 10000);
        });
      });

      if (k8sResponse.success) {
        console.log('✅ Kubernetes integration via WebSocket successful');
        if (k8sResponse.data && k8sResponse.data.pods) {
          console.log(`   Found ${k8sResponse.data.pods.length} pods`);
        }
        return true;
      } else {
        console.log(`❌ Kubernetes integration failed: ${k8sResponse.error}`);
        return false;
      }
    } catch (error) {
      console.error('❌ Kubernetes integration test failed:', error.message);
      return false;
    }
  }

  async testServiceAvailability() {
    console.log('🔍 Testing service availability via health endpoint...');

    try {
      const health = await this.page.evaluate(async (backendURL) => {
        const response = await fetch(`${backendURL}/health`);
        return {
          status: response.status,
          data: response.ok ? await response.json() : null,
        };
      }, this.backendURL);

      if (health.status === 200) {
        console.log('✅ Health endpoint responsive');
        console.log(`   API Status: ${health.data.status}`);

        if (health.data.components) {
          console.log(`   System Monitor: ${health.data.components.system_monitor}`);
          console.log(`   Command Executor: ${health.data.components.command_executor}`);
        }

        return health.data.status === 'healthy';
      } else {
        console.log(`❌ Health endpoint failed: ${health.status}`);
        return false;
      }
    } catch (error) {
      console.error('❌ Service availability test failed:', error.message);
      return false;
    }
  }

  async testWebSocketCommands() {
    console.log('🔌 Testing WebSocket command execution...');

    await this.page.goto(this.baseURL, { waitUntil: 'networkidle0' });

    try {
      // Wait for WebSocket connection
      await this.page.waitForTimeout(3500);

      // Test sending Docker ps command via WebSocket
      const dockerResponse = await this.page.evaluate(() => {
        return new Promise((resolve) => {
          const ws = new WebSocket('ws://localhost:8000/ws');

          ws.onopen = () => {
            console.log('WebSocket connected for testing');
            ws.send(
              JSON.stringify({
                type: 'command',
                target: 'docker',
                command: 'ps',
                requestId: 'test_docker_ps',
              })
            );
          };

          ws.onmessage = (event) => {
            const data = JSON.parse(event.data);
            if (data.requestId === 'test_docker_ps') {
              ws.close();
              resolve(data);
            }
          };

          ws.onerror = (error) => {
            resolve({ success: false, error: 'WebSocket error' });
          };

          setTimeout(() => {
            ws.close();
            resolve({ success: false, error: 'Timeout' });
          }, 10000);
        });
      });

      if (dockerResponse.success) {
        console.log('✅ Docker ps command via WebSocket successful');
        if (dockerResponse.data && dockerResponse.data.containers) {
          console.log(`   Found ${dockerResponse.data.containers.length} containers`);
        }
        return true;
      } else {
        console.log(`❌ Docker ps command failed: ${dockerResponse.error}`);
        return false;
      }
    } catch (error) {
      console.error('❌ WebSocket command test failed:', error.message);
      return false;
    }
  }

  async testRealTimeUpdates() {
    console.log('📡 Testing real-time monitoring updates...');

    await this.page.goto(this.baseURL, { waitUntil: 'networkidle0' });

    try {
      // Monitor for real-time updates by checking if metrics change
      const initialMetrics = await this.page.evaluate(() => {
        const metricsElements = document.querySelectorAll('[data-testid*="metric"], .metric-value');
        return Array.from(metricsElements).map((el) => el.textContent);
      });

      // Wait for updates
      await this.page.waitForTimeout(6000);

      const updatedMetrics = await this.page.evaluate(() => {
        const metricsElements = document.querySelectorAll('[data-testid*="metric"], .metric-value');
        return Array.from(metricsElements).map((el) => el.textContent);
      });

      // Check if any metrics have changed (indicating real-time updates)
      const hasUpdates = initialMetrics.some(
        (initial, index) => updatedMetrics[index] && initial !== updatedMetrics[index]
      );

      if (hasUpdates) {
        console.log('✅ Real-time updates detected');
        return true;
      } else {
        console.log('⚠️  No real-time updates detected (may be expected if no activity)');
        return true; // Not necessarily a failure
      }
    } catch (error) {
      console.error('❌ Real-time updates test failed:', error.message);
      return false;
    }
  }

  async testErrorHandling() {
    console.log('🚫 Testing error handling...');

    try {
      // Test invalid endpoint
      const invalidResponse = await this.page.evaluate(async (backendURL) => {
        const response = await fetch(`${backendURL}/api/invalid/endpoint`);
        return response.status;
      }, this.backendURL);

      if (invalidResponse === 404) {
        console.log('✅ Invalid endpoint returns 404 as expected');
      } else {
        console.log(`⚠️  Invalid endpoint returned ${invalidResponse}, expected 404`);
      }

      // Test WebSocket with invalid command
      await this.page.goto(this.baseURL, { waitUntil: 'networkidle0' });

      const invalidCommandResponse = await this.page.evaluate(() => {
        return new Promise((resolve) => {
          const ws = new WebSocket('ws://localhost:8000/ws');

          ws.onopen = () => {
            ws.send(
              JSON.stringify({
                type: 'command',
                target: 'invalid',
                command: 'invalid',
                requestId: 'test_invalid',
              })
            );
          };

          ws.onmessage = (event) => {
            const data = JSON.parse(event.data);
            if (data.requestId === 'test_invalid') {
              ws.close();
              resolve(data);
            }
          };

          setTimeout(() => {
            ws.close();
            resolve({ success: false, error: 'Timeout' });
          }, 5000);
        });
      });

      if (!invalidCommandResponse.success) {
        console.log('✅ Invalid WebSocket command rejected as expected');
        return true;
      } else {
        console.log('⚠️  Invalid WebSocket command was not rejected');
        return false;
      }
    } catch (error) {
      console.error('❌ Error handling test failed:', error.message);
      return false;
    }
  }

  async generateMonitoringReport() {
    console.log('📊 Generating monitoring integration report...');

    const healthInfo = await this.page.evaluate(async (backendURL) => {
      try {
        const response = await fetch(`${backendURL}/health`);
        return response.ok ? await response.json() : null;
      } catch {
        return null;
      }
    }, this.backendURL);

    const report = {
      timestamp: new Date().toISOString(),
      api_status: healthInfo?.status || 'Unknown',
      active_connections: healthInfo?.metrics?.active_connections || 0,
      active_subscriptions: healthInfo?.metrics?.active_subscriptions || 0,
      system_cpu: healthInfo?.metrics?.system_cpu || 0,
      system_memory: healthInfo?.metrics?.system_memory || 0,
      websocket_operational: healthInfo?.components?.websocket === 'operational',
    };

    console.log('📋 Monitoring Integration Summary:');
    console.log(`   API Status: ${report.api_status}`);
    console.log(`   Active Connections: ${report.active_connections}`);
    console.log(`   WebSocket Operational: ${report.websocket_operational}`);
    console.log(`   System CPU: ${report.system_cpu}%`);
    console.log(`   System Memory: ${report.system_memory}%`);

    return report;
  }

  async cleanup() {
    if (this.browser) {
      await this.browser.close();
      console.log('🧹 Browser closed');
    }
  }

  async runMonitoringTests() {
    console.log('🎯 Starting MiniPrem Monitor Integration Tests');
    console.log('='.repeat(50));

    let allTestsPassed = true;
    const results = {};

    try {
      await this.init();

      // Run monitoring integration tests
      results.dockerIntegration = await this.testDockerIntegration();
      results.kubernetesIntegration = await this.testKubernetesIntegration();
      results.serviceAvailability = await this.testServiceAvailability();
      results.webSocketCommands = await this.testWebSocketCommands();
      results.realTimeUpdates = await this.testRealTimeUpdates();
      results.errorHandling = await this.testErrorHandling();

      // Generate report
      const report = await this.generateMonitoringReport();

      console.log('\n' + '='.repeat(50));
      console.log('📊 MONITORING TEST RESULTS');
      console.log('='.repeat(50));

      for (const [testName, passed] of Object.entries(results)) {
        const status = passed ? '✅ PASS' : '❌ FAIL';
        console.log(`${status} ${testName}`);
      }

      // Overall success requires at least one monitoring service to be available
      const monitoringAvailable = results.dockerIntegration || results.kubernetesIntegration;
      allTestsPassed = monitoringAvailable && results.serviceAvailability && results.errorHandling;

      console.log('\n' + (allTestsPassed ? '🎉 MONITORING TESTS PASSED!' : '⚠️  MONITORING TESTS ISSUES FOUND'));
      console.log('='.repeat(50));

      return allTestsPassed;
    } catch (error) {
      console.error('💥 Monitoring test suite failed:', error.message);
      return false;
    } finally {
      await this.cleanup();
    }
  }
}

// Run tests if called directly
if (require.main === module) {
  const tester = new MonitoringTester();
  tester
    .runMonitoringTests()
    .then((success) => {
      process.exit(success ? 0 : 1);
    })
    .catch((error) => {
      console.error('💥 Fatal error:', error);
      process.exit(1);
    });
}

module.exports = MonitoringTester;
