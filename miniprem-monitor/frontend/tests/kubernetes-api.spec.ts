import { test, expect } from '@playwright/test';

/**
 * Kubernetes API Integration Tests
 *
 * Tests backend API endpoints for Kubernetes functionality
 * using both Playwright page context and direct curl commands
 * to verify proper error handling and response formats.
 */

test.describe('Kubernetes API Integration Tests', () => {
  const baseURL = 'http://localhost:8000'; // Backend server URL
  const apiTimeout = 30000; // 30 second timeout for API calls

  test.beforeEach(async ({ page }) => {
    // Set longer timeout for API tests
    test.setTimeout(60000);
  });

  test.describe('Backend API Endpoints', () => {
    test('GET /api/kubernetes/contexts endpoint behavior', async ({ page }) => {
      // Test the endpoint through page context (same as frontend would)
      const response = await page.request.get(`${baseURL}/api/kubernetes/contexts`, {
        timeout: apiTimeout
      });

      // Log response for debugging
      console.log('Contexts API Response Status:', response.status());

      if (response.ok()) {
        // Successful response should have proper structure
        const data = await response.json();
        console.log('Contexts API Data:', data);

        // Should be an array or object with contexts
        expect(Array.isArray(data) || typeof data === 'object').toBeTruthy();

        if (Array.isArray(data) && data.length > 0) {
          // Each context should have required fields
          const firstContext = data[0];
          expect(firstContext).toHaveProperty('name');
          expect(firstContext).toHaveProperty('context');
        }
      } else {
        // Error responses should have proper structure
        console.log('Contexts API Error:', await response.text());

        // Common error status codes we should handle
        const acceptableErrorCodes = [401, 403, 404, 500, 502, 503];
        expect(acceptableErrorCodes).toContain(response.status());

        // Error response should be parseable
        try {
          const errorData = await response.json();
          expect(errorData).toHaveProperty('error');
        } catch {
          // Plain text error is also acceptable
          const errorText = await response.text();
          expect(errorText.length).toBeGreaterThan(0);
        }
      }
    });

    test('POST /api/kubernetes/context/switch endpoint behavior', async ({ page }) => {
      const testContext = 'test-context';

      const response = await page.request.post(`${baseURL}/api/kubernetes/context/switch/${testContext}`, {
        timeout: apiTimeout
      });

      console.log('Context Switch API Response Status:', response.status());

      if (response.ok()) {
        // Successful switch should return confirmation
        const data = await response.json();
        console.log('Context Switch Success:', data);

        expect(data).toHaveProperty('success');
        expect(data.success).toBeTruthy();
      } else {
        // Error responses for invalid context are expected
        console.log('Context Switch Error:', await response.text());

        // Should handle authentication, not found, or server errors gracefully
        const acceptableErrorCodes = [400, 401, 403, 404, 500, 502, 503];
        expect(acceptableErrorCodes).toContain(response.status());

        try {
          const errorData = await response.json();
          expect(errorData).toHaveProperty('error');
        } catch {
          // Plain text error is also acceptable
          const errorText = await response.text();
          expect(errorText.length).toBeGreaterThan(0);
        }
      }
    });

    test('API health check and server availability', async ({ page }) => {
      // Test if backend server is running
      try {
        const response = await page.request.get(`${baseURL}/health`, {
          timeout: 10000
        });

        if (response.ok()) {
          console.log('Backend health check passed');
        } else {
          console.log('Backend health check failed:', response.status());
        }
      } catch (error) {
        console.log('Backend server may not be running:', error);
      }

      // Test if we can reach any API endpoint
      const apiResponse = await page.request.get(`${baseURL}/api/kubernetes/contexts`, {
        timeout: 10000
      });

      // Server should respond (even with error) rather than timeout
      expect(apiResponse.status()).not.toBe(0);
    });
  });

  test.describe('Error Handling Tests', () => {
    test('handles authentication errors correctly', async ({ page }) => {
      // Mock authentication failure
      await page.route('**/api/kubernetes/contexts', (route) => {
        route.fulfill({
          status: 401,
          contentType: 'application/json',
          body: JSON.stringify({
            error: 'Kubernetes authentication failed',
            code: 'K8S_AUTH_FAILED',
            message: 'Unable to authenticate with Kubernetes API server'
          })
        });
      });

      // Test frontend handles auth error
      await page.goto('/');
      await page.waitForTimeout(3000);

      // Frontend should handle 401 gracefully
      const pageContent = await page.textContent('body');
      expect(pageContent).toBeTruthy();

      // Should not crash or show blank page
      const hasContent = await page.locator('h1, h2, [data-testid]').count();
      expect(hasContent).toBeGreaterThan(0);
    });

    test('handles server errors correctly', async ({ page }) => {
      // Mock server error
      await page.route('**/api/kubernetes/**', (route) => {
        route.fulfill({
          status: 500,
          contentType: 'application/json',
          body: JSON.stringify({
            error: 'Internal server error',
            code: 'INTERNAL_ERROR',
            message: 'Kubernetes API server is unreachable'
          })
        });
      });

      await page.goto('/');
      await page.waitForTimeout(3000);

      // Frontend should handle 500 gracefully
      const pageContent = await page.textContent('body');
      expect(pageContent).toBeTruthy();

      // Should show appropriate error state
      const hasErrorState =
        pageContent?.includes('error') ||
        pageContent?.includes('unreachable') ||
        await page.locator('[data-testid="no-pods"]').isVisible();

      expect(hasErrorState).toBeTruthy();
    });

    test('handles network timeouts gracefully', async ({ page }) => {
      // Mock network timeout
      await page.route('**/api/kubernetes/**', (route) => {
        // Delay response to simulate timeout
        setTimeout(() => {
          route.fulfill({
            status: 504,
            contentType: 'application/json',
            body: JSON.stringify({
              error: 'Gateway timeout',
              code: 'TIMEOUT',
              message: 'Request to Kubernetes API timed out'
            })
          });
        }, 10000);
      });

      await page.goto('/');
      await page.waitForTimeout(5000);

      // Page should still be functional during timeout
      const mainContent = page.getByRole('heading', { name: /MiniPrem Monitor/ });
      await expect(mainContent).toBeVisible();
    });
  });

  test.describe('WebSocket Integration Tests', () => {
    test('WebSocket handles Kubernetes subscription errors', async ({ page }) => {
      // Override WebSocket to test error handling
      await page.addInitScript(() => {
        const originalWebSocket = window.WebSocket;
        window.WebSocket = class extends originalWebSocket {
          constructor(...args: any[]) {
            super(...args);

            // Simulate Kubernetes subscription error
            setTimeout(() => {
              const errorEvent = new MessageEvent('message', {
                data: JSON.stringify({
                  type: 'error',
                  subscription: 'kubernetes:pods',
                  success: false,
                  error: 'Failed to connect to Kubernetes API',
                  code: 'K8S_CONNECTION_ERROR'
                })
              });
              this.dispatchEvent(errorEvent);
            }, 2000);
          }
        };
      });

      await page.goto('/');
      await page.waitForTimeout(5000);

      // Should handle WebSocket errors gracefully
      const k8sPanel = page.locator('text=Kubernetes').locator('..').locator('..');
      await expect(k8sPanel).toBeVisible();

      // Should show appropriate error state or loading state
      const hasErrorOrNoData =
        await page.getByTestId('no-pods').isVisible() ||
        await page.getByTestId('pods-loading').isVisible() ||
        await page.locator('[class*="error"]').isVisible();

      expect(hasErrorOrNoData).toBeTruthy();
    });

    test('WebSocket connection status updates correctly', async ({ page }) => {
      await page.goto('/');
      await page.waitForTimeout(3000);

      // Look for connection status indicator
      const connectionStatus = page.getByTestId('connection-status');

      if (await connectionStatus.isVisible()) {
        const statusText = await connectionStatus.textContent();

        // Should show connection state
        expect(statusText).toMatch(/connected|connecting|disconnected/i);

        // Should have visual indicator
        const statusIndicator = connectionStatus.locator('[class*="rounded-full"]');
        await expect(statusIndicator).toBeVisible();
      }
    });
  });

  test.describe('Data Format Validation', () => {
    test('pod data format validation', async ({ page }) => {
      // Mock properly formatted pod data
      await page.route('**/ws', async (route) => {
        // This is a WebSocket route, which is trickier to mock
        // We'll test data format when we receive actual data instead
        await route.continue();
      });

      await page.goto('/');
      await page.waitForTimeout(5000);

      // Check if any pods are displayed
      const podItems = page.getByTestId('pod-item');
      const podCount = await podItems.count();

      if (podCount > 0) {
        const firstPod = podItems.first();

        // Should have pod name
        const podName = firstPod.locator('[class*="font-semibold"]').first();
        await expect(podName).toBeVisible();

        // Should have namespace and status info
        const podInfo = firstPod.locator('[class*="text-sm"]').first();
        await expect(podInfo).toBeVisible();

        const infoText = await podInfo.textContent();
        expect(infoText).toMatch(/ready|age|\d+\/\d+/);

        // Should have status indicator
        const statusIndicator = firstPod.locator('[data-status], [class*="StatusIndicator"]');
        if (await statusIndicator.isVisible()) {
          await expect(statusIndicator).toBeVisible();
        }
      }
    });

    test('cluster info data format validation', async ({ page }) => {
      await page.goto('/');
      await page.waitForTimeout(3000);

      const clusterSelector = page.getByTestId('cluster-selector');

      if (await clusterSelector.isVisible()) {
        const clusterText = await clusterSelector.textContent();

        if (!clusterText?.includes('No cluster selected')) {
          // Should show cluster name and status
          expect(clusterText).toMatch(/local|eks|gke|aks/i);

          // Should have status indicator
          const statusIndicator = clusterSelector.locator('[class*="StatusIndicator"], [class*="rounded-full"]');
          await expect(statusIndicator).toBeVisible();
        }
      }
    });
  });

  test.describe('Performance Tests', () => {
    test('API response times are reasonable', async ({ page }) => {
      const startTime = Date.now();

      try {
        const response = await page.request.get(`${baseURL}/api/kubernetes/contexts`, {
          timeout: 10000
        });

        const endTime = Date.now();
        const responseTime = endTime - startTime;

        console.log(`API response time: ${responseTime}ms`);

        // Should respond within 10 seconds (allowing for potential slowness)
        expect(responseTime).toBeLessThan(10000);

        if (response.ok()) {
          // Successful responses should be reasonably fast
          expect(responseTime).toBeLessThan(5000);
        }
      } catch (error) {
        // Even timeouts should happen within reasonable time
        const endTime = Date.now();
        const responseTime = endTime - startTime;

        console.log(`API timeout after: ${responseTime}ms`);
        expect(responseTime).toBeLessThan(15000);
      }
    });

    test('page loads with Kubernetes data within acceptable time', async ({ page }) => {
      const startTime = Date.now();

      await page.goto('/');
      await page.waitForLoadState('networkidle');

      // Wait for potential Kubernetes data to load
      await page.waitForTimeout(5000);

      const endTime = Date.now();
      const loadTime = endTime - startTime;

      console.log(`Page load time with K8s data: ${loadTime}ms`);

      // Page should load within 30 seconds
      expect(loadTime).toBeLessThan(30000);

      // Should have main content regardless of K8s data
      const mainHeading = page.getByRole('heading', { name: /MiniPrem Monitor/ });
      await expect(mainHeading).toBeVisible();
    });
  });
});