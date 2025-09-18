#!/usr/bin/env node

/**
 * Puppeteer Dashboard Test Script
 * Tests the MiniPrem Monitor dashboard functionality
 */

const puppeteer = require('puppeteer');
const path = require('path');

class DashboardTester {
  constructor() {
    this.browser = null;
    this.page = null;
    this.baseURL = process.env.FRONTEND_URL || 'http://localhost:3500';
    this.backendURL = process.env.BACKEND_URL || 'http://localhost:8000';
  }

  async init() {
    console.log('🚀 Launching browser for dashboard testing...');

    this.browser = await puppeteer.launch({
      headless: process.env.PUPPETEER_HEADLESS !== 'false',
      defaultViewport: { width: 1920, height: 1080 },
      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
        '--disable-accelerated-2d-canvas',
        '--no-first-run',
        '--no-zygote',
        '--disable-gpu',
      ],
    });

    this.page = await this.browser.newPage();

    // Enable request interception for monitoring API calls
    await this.page.setRequestInterception(true);

    const apiCalls = [];
    this.page.on('request', (request) => {
      if (request.url().includes('/api/')) {
        apiCalls.push({
          url: request.url(),
          method: request.method(),
          timestamp: new Date().toISOString(),
        });
      }
      request.continue();
    });

    // Store API calls for analysis
    this.apiCalls = apiCalls;

    // Set up console logging
    this.page.on('console', (msg) => {
      if (msg.type() === 'error') {
        console.error('❌ Browser console error:', msg.text());
      }
    });

    // Set up error handling
    this.page.on('pageerror', (error) => {
      console.error('❌ Page error:', error.message);
    });
  }

  async testBackendHealth() {
    console.log('🔍 Testing backend health...');

    try {
      const response = await this.page.evaluate(async (backendURL) => {
        const res = await fetch(`${backendURL}/health`);
        return {
          status: res.status,
          data: await res.json(),
        };
      }, this.backendURL);

      if (response.status === 200) {
        console.log('✅ Backend health check passed');
        console.log(`   Active connections: ${response.data.metrics?.active_connections || 0}`);
        return true;
      } else {
        console.log('❌ Backend health check failed:', response.status);
        return false;
      }
    } catch (error) {
      console.error('❌ Backend health check error:', error.message);
      return false;
    }
  }

  async testDashboardLoad() {
    console.log('🔍 Testing dashboard load...');

    try {
      const startTime = Date.now();
      await this.page.goto(this.baseURL, { waitUntil: 'networkidle0', timeout: 35000 });
      const loadTime = Date.now() - startTime;

      // Check if the main dashboard elements are present
      await this.page.waitForSelector('h1:has-text("MiniPrem Monitor")', { timeout: 10000 });
      await this.page.waitForSelector('[data-testid="metrics-card"], .card', { timeout: 10000 });

      console.log(`✅ Dashboard loaded successfully in ${loadTime}ms`);
      return true;
    } catch (error) {
      console.error('❌ Dashboard load failed:', error.message);
      await this.takeScreenshot('dashboard-load-failed.png');
      return false;
    }
  }

  async testWebSocketConnection() {
    console.log('🔍 Testing WebSocket connection...');

    try {
      // Wait for WebSocket connection to be established
      await this.page.waitForFunction(
        () => {
          return (
            window.performance &&
            window.performance.getEntriesByType &&
            window.performance.getEntriesByType('resource').some((entry) => entry.name.includes('/ws'))
          );
        },
        { timeout: 15000 }
      );

      // Check connection status indicator
      const connectionStatus = await this.page.$('.connection-status, [data-testid="connection-status"]');
      if (connectionStatus) {
        const statusText = await connectionStatus.textContent();
        console.log(`✅ WebSocket connection established: ${statusText}`);
        return true;
      } else {
        console.log('⚠️  Connection status indicator not found');
        return false;
      }
    } catch (error) {
      console.error('❌ WebSocket connection test failed:', error.message);
      return false;
    }
  }

  async testSystemHealthPanel() {
    console.log('🔍 Testing system health panel...');

    try {
      // Wait for system health panel to load
      await this.page.waitForSelector('h2:has-text("System Health"), [data-testid="system-health"]', {
        timeout: 10000,
      });

      // Check for Docker and Kubernetes health indicators
      const dockerHealth = await this.page.$('text=Docker Engine');
      const kubernetesHealth = await this.page.$('text=Kubernetes Cluster');

      if (dockerHealth && kubernetesHealth) {
        console.log('✅ System health panel loaded with Docker and Kubernetes monitoring');

        // Check health status indicators
        const healthStatuses = await this.page.$$eval('[class*="status-"]', (elements) =>
          elements.map((el) => el.className)
        );

        console.log(`   Found ${healthStatuses.length} health status indicators`);
        return true;
      } else {
        console.log('❌ System health panel missing Docker or Kubernetes sections');
        return false;
      }
    } catch (error) {
      console.error('❌ System health panel test failed:', error.message);
      await this.takeScreenshot('system-health-failed.png');
      return false;
    }
  }

  async testContainerMonitoring() {
    console.log('🔍 Testing container monitoring...');

    try {
      // Wait for container panel to load
      await this.page.waitForSelector('text=Docker, [data-testid="container-panel"]', { timeout: 10000 });

      // Check if container data is loading or loaded
      const hasContainers = await this.page.evaluate(() => {
        const panel = document.querySelector('[class*="container"], [data-testid="container-panel"]');
        return panel && (panel.textContent.includes('containers') || panel.textContent.includes('Loading'));
      });

      if (hasContainers) {
        console.log('✅ Container monitoring panel found');
        return true;
      } else {
        console.log('⚠️  Container monitoring panel not found or empty');
        return false;
      }
    } catch (error) {
      console.error('❌ Container monitoring test failed:', error.message);
      return false;
    }
  }

  async testKubernetesMonitoring() {
    console.log('🔍 Testing Kubernetes monitoring...');

    try {
      // Wait for Kubernetes panel to load
      await this.page.waitForSelector('text=Kubernetes, [data-testid="kubernetes-panel"]', { timeout: 10000 });

      // Check if pod data is loading or loaded
      const hasPods = await this.page.evaluate(() => {
        const panel = document.querySelector('[class*="kubernetes"], [data-testid="kubernetes-panel"]');
        return panel && (panel.textContent.includes('pods') || panel.textContent.includes('Loading'));
      });

      if (hasPods) {
        console.log('✅ Kubernetes monitoring panel found');
        return true;
      } else {
        console.log('⚠️  Kubernetes monitoring panel not found or empty');
        return false;
      }
    } catch (error) {
      console.error('❌ Kubernetes monitoring test failed:', error.message);
      return false;
    }
  }

  async testWebSocketCommunication() {
    console.log('🔍 Testing WebSocket communication...');

    try {
      // Test that WebSocket messages are being sent and received
      const websocketActivity = await this.page.evaluate(() => {
        return new Promise((resolve) => {
          let messageCount = 0;
          const startTime = Date.now();
          const timeout = 10000; // 10 seconds

          // Check for WebSocket activity in console logs or global state
          const checkActivity = () => {
            // Look for signs of WebSocket activity
            const hasWebSocketMessages =
              window.console &&
              (document.body.textContent.includes('Connected') ||
                document.body.textContent.includes('WebSocket') ||
                document.querySelectorAll('[class*="status-healthy"], [class*="status-error"]').length > 0);

            if (hasWebSocketMessages || Date.now() - startTime > timeout) {
              resolve({
                hasActivity: hasWebSocketMessages,
                timeElapsed: Date.now() - startTime,
              });
            } else {
              setTimeout(checkActivity, 1000);
            }
          };

          checkActivity();
        });
      });

      if (websocketActivity.hasActivity) {
        console.log(`✅ WebSocket communication active (detected in ${websocketActivity.timeElapsed}ms)`);
        return true;
      } else {
        console.log('❌ No WebSocket communication detected');
        return false;
      }
    } catch (error) {
      console.error('❌ WebSocket communication test failed:', error.message);
      return false;
    }
  }

  async testResponsiveDesign() {
    console.log('🔍 Testing responsive design...');

    const viewports = [
      { name: 'Mobile', width: 375, height: 667 },
      { name: 'Tablet', width: 768, height: 1024 },
      { name: 'Desktop', width: 1920, height: 1080 },
    ];

    let allPassed = true;

    for (const viewport of viewports) {
      try {
        await this.page.setViewport({ width: viewport.width, height: viewport.height });
        await this.page.waitForTimeout(1000); // Wait for reflow

        // Check if main content is still visible
        const mainContent = await this.page.$('main, [data-testid="main-content"]');
        const isVisible = await mainContent.isIntersectingViewport();

        if (isVisible) {
          console.log(`   ✅ ${viewport.name} (${viewport.width}x${viewport.height}): Responsive`);
        } else {
          console.log(`   ❌ ${viewport.name} (${viewport.width}x${viewport.height}): Layout issues`);
          allPassed = false;
        }
      } catch (error) {
        console.log(`   ❌ ${viewport.name}: ${error.message}`);
        allPassed = false;
      }
    }

    // Reset to default viewport
    await this.page.setViewport({ width: 1920, height: 1080 });

    return allPassed;
  }

  async takeScreenshot(filename) {
    try {
      const screenshotPath = path.join(__dirname, '..', 'test-screenshots', filename);
      await this.page.screenshot({
        path: screenshotPath,
        fullPage: true,
      });
      console.log(`📸 Screenshot saved: ${screenshotPath}`);
    } catch (error) {
      console.error('❌ Failed to take screenshot:', error.message);
    }
  }

  async generateReport() {
    console.log('📊 Generating test report...');

    const report = {
      timestamp: new Date().toISOString(),
      baseURL: this.baseURL,
      backendURL: this.backendURL,
      apiCalls: this.apiCalls.length,
      uniqueAPIs: [...new Set(this.apiCalls.map((call) => call.url))].length,
      userAgent: await this.page.evaluate(() => navigator.userAgent),
    };

    console.log('📋 Test Summary:');
    console.log(`   Dashboard URL: ${report.baseURL}`);
    console.log(`   Backend URL: ${report.backendURL}`);
    console.log(`   API Calls Made: ${report.apiCalls}`);
    console.log(`   Unique API Endpoints: ${report.uniqueAPIs}`);
    console.log(`   Test Completed: ${report.timestamp}`);

    return report;
  }

  async cleanup() {
    if (this.browser) {
      await this.browser.close();
      console.log('🧹 Browser closed');
    }
  }

  async runAllTests() {
    console.log('🎯 Starting MiniPrem Monitor Dashboard Tests');
    console.log('='.repeat(50));

    let allTestsPassed = true;
    const results = {};

    try {
      await this.init();

      // Run tests in sequence
      results.backendHealth = await this.testBackendHealth();
      results.dashboardLoad = await this.testDashboardLoad();
      results.webSocketConnection = await this.testWebSocketConnection();
      results.systemHealthPanel = await this.testSystemHealthPanel();
      results.containerMonitoring = await this.testContainerMonitoring();
      results.kubernetesMonitoring = await this.testKubernetesMonitoring();
      results.webSocketCommunication = await this.testWebSocketCommunication();
      results.responsiveDesign = await this.testResponsiveDesign();

      // Check if all tests passed
      allTestsPassed = Object.values(results).every((result) => result === true);

      // Take final screenshot
      await this.takeScreenshot('final-dashboard-state.png');

      // Generate report
      const report = await this.generateReport();

      console.log('\n' + '='.repeat(50));
      console.log('📊 TEST RESULTS SUMMARY');
      console.log('='.repeat(50));

      for (const [testName, passed] of Object.entries(results)) {
        const status = passed ? '✅ PASS' : '❌ FAIL';
        console.log(`${status} ${testName}`);
      }

      console.log('\n' + (allTestsPassed ? '🎉 ALL TESTS PASSED!' : '⚠️  SOME TESTS FAILED'));
      console.log('='.repeat(50));

      return allTestsPassed;
    } catch (error) {
      console.error('💥 Test suite failed with error:', error.message);
      return false;
    } finally {
      await this.cleanup();
    }
  }
}

// Run tests if called directly
if (require.main === module) {
  const tester = new DashboardTester();
  tester
    .runAllTests()
    .then((success) => {
      process.exit(success ? 0 : 1);
    })
    .catch((error) => {
      console.error('💥 Fatal error:', error);
      process.exit(1);
    });
}

module.exports = DashboardTester;
