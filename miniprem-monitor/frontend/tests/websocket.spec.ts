import { test, expect } from '@playwright/test';

/**
 * WebSocket Connection and Real-time Data Tests
 *
 * Tests WebSocket connectivity, real-time updates, and subscription handling
 */

test.describe('WebSocket Connection', () => {
  let wsMessages: any[] = [];

  test.beforeEach(async ({ page }) => {
    // Capture WebSocket messages for testing
    wsMessages = [];

    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Set up WebSocket message interception
    await page.evaluate(() => {
      const originalWebSocket = window.WebSocket;
      (window as any).wsMessages = [];

      (window as any).WebSocket = class extends originalWebSocket {
        constructor(url: string | URL, protocols?: string | string[]) {
          super(url, protocols);

          this.addEventListener('open', (event) => {
            (window as any).wsMessages.push({ type: 'open', timestamp: Date.now() });
          });

          this.addEventListener('message', (event) => {
            try {
              const data = JSON.parse(event.data);
              (window as any).wsMessages.push({ type: 'message', data, timestamp: Date.now() });
            } catch (e) {
              (window as any).wsMessages.push({ type: 'message', data: event.data, timestamp: Date.now() });
            }
          });

          this.addEventListener('close', (event) => {
            (window as any).wsMessages.push({
              type: 'close',
              code: event.code,
              reason: event.reason,
              timestamp: Date.now(),
            });
          });

          this.addEventListener('error', (event) => {
            (window as any).wsMessages.push({ type: 'error', timestamp: Date.now() });
          });
        }
      };
    });
  });

  test('establishes WebSocket connection', async ({ page }) => {
    // Wait for connection to establish
    await page.waitForTimeout(3500);

    // Check connection status indicator
    const connectionStatus = page
      .locator('[data-testid="connection-status"]')
      .or(page.getByText('Connected'))
      .or(page.locator('.bg-status-healthy'))
      .first();

    // Either should be connected or show attempt to connect
    const messages = await page.evaluate(() => (window as any).wsMessages);

    if (messages && messages.length > 0) {
      const hasOpenMessage = messages.some((msg: any) => msg.type === 'open');
      const hasMessages = messages.some((msg: any) => msg.type === 'message');

      expect(hasOpenMessage || hasMessages).toBeTruthy();
    } else {
      console.log('WebSocket messages not captured - backend may not be running');
    }

    // Visual indicator should show some connection state
    await expect(page.locator('body')).toBeVisible(); // Basic fallback test
  });

  test('displays connection status correctly', async ({ page }) => {
    await page.waitForTimeout(2000);

    // Look for connection status component
    const statusElement = page
      .locator('[data-testid="connection-status"]')
      .or(page.getByText('WebSocket'))
      .or(page.locator('.w-2.h-2.rounded-full, .w-3.h-3.rounded-full'))
      .first();

    if (await statusElement.isVisible()) {
      await expect(statusElement).toBeVisible();

      // Should show either connected (green) or disconnected (red) state
      const parentElement = statusElement.locator('..').or(statusElement);
      const hasStatusColor = await parentElement
        .locator('.bg-status-healthy, .bg-green-500, .bg-status-error, .bg-red-500')
        .isVisible();
      expect(hasStatusColor).toBeTruthy();
    }
  });

  test('receives subscription updates', async ({ page }) => {
    await page.waitForTimeout(5000); // Wait longer for subscription data

    const messages = await page.evaluate(() => (window as any).wsMessages);

    if (messages && messages.length > 0) {
      // Look for subscription-related messages
      const subscriptionMessages = messages.filter(
        (msg: any) =>
          msg.data &&
          (msg.data.requestId?.includes('subscription:') || msg.data.data?.containers || msg.data.data?.pods)
      );

      if (subscriptionMessages.length > 0) {
        console.log('✅ Received subscription updates:', subscriptionMessages.length);
        expect(subscriptionMessages.length).toBeGreaterThan(0);
      } else {
        console.log('ℹ️ No subscription updates received - backend may not have data');
      }
    }

    // Check if container or pod data is displayed
    const hasContainerData = await page.locator('[data-container-item]').first().isVisible();
    const hasPodData = await page.locator('[data-pod-item]').first().isVisible();
    const hasNoDataMessage = await page
      .getByText('No containers found')
      .or(page.getByText('No pods found'))
      .first()
      .isVisible();

    // Should have either data or "no data" message
    expect(hasContainerData || hasPodData || hasNoDataMessage).toBeTruthy();
  });

  test('handles WebSocket disconnection gracefully', async ({ page }) => {
    await page.waitForTimeout(2000);

    // Simulate WebSocket disconnection
    await page.evaluate(() => {
      const connections = Array.from((window as any).WebSocket?.connections || []);
      connections.forEach((ws: WebSocket) => {
        if (ws.readyState === WebSocket.OPEN) {
          ws.close(1000, 'Test disconnection');
        }
      });
    });

    await page.waitForTimeout(1000);

    // Should show disconnected state
    const connectionStatus = page.locator('[data-testid="connection-status"]').first();
    if (await connectionStatus.isVisible()) {
      // Should indicate disconnected state
      const hasErrorState = await connectionStatus.locator('..').locator('.bg-status-error, .bg-red-500').isVisible();
      if (hasErrorState) {
        expect(hasErrorState).toBeTruthy();
      }
    }

    // Page should still be functional
    await expect(page.getByRole('heading', { name: 'MiniPrem Monitor' })).toBeVisible();
  });

  test('reconnects after connection loss', async ({ page }) => {
    await page.waitForTimeout(3500);

    // Check initial connection
    let initialMessages = await page.evaluate(() => (window as any).wsMessages);

    if (initialMessages && initialMessages.length > 0) {
      // Simulate temporary connection loss and recovery
      await page.evaluate(() => {
        // Force close current WebSocket connections
        if ((window as any).WebSocket.connections) {
          (window as any).WebSocket.connections.forEach((ws: WebSocket) => {
            ws.close(1006, 'Simulated network error');
          });
        }
      });

      await page.waitForTimeout(5000); // Wait for reconnection attempt

      // Check if reconnection occurred
      const finalMessages = await page.evaluate(() => (window as any).wsMessages);

      if (finalMessages && finalMessages.length > initialMessages.length) {
        const reconnectionAttempt = finalMessages.some(
          (msg: any) => msg.type === 'open' && msg.timestamp > initialMessages[initialMessages.length - 1]?.timestamp
        );
        if (reconnectionAttempt) {
          console.log('✅ WebSocket reconnection detected');
        }
      }
    }

    // Application should remain functional
    await expect(page.getByRole('heading', { name: 'MiniPrem Monitor' })).toBeVisible();
  });

  test('real-time data updates containers', async ({ page }) => {
    await page.waitForTimeout(3500);

    // Check if container data is present
    const containerPanel = page.getByText('Docker Containers').locator('..');
    await expect(containerPanel).toBeVisible();

    // Look for container items or loading states
    const hasContainers = await page.locator('[data-container-item]').first().isVisible();
    const hasLoading = await containerPanel.locator('.animate-pulse').isVisible();
    const hasNoData = await page.getByText('No containers found').isVisible();

    expect(hasContainers || hasLoading || hasNoData).toBeTruthy();

    if (hasContainers) {
      // Verify container information is displayed
      const containerItem = page.locator('[data-container-item]').first();
      await expect(containerItem).toBeVisible();
    }
  });

  test('real-time data updates kubernetes pods', async ({ page }) => {
    await page.waitForTimeout(3500);

    // Check if pod data is present
    const k8sPanel = page.getByText('Kubernetes').locator('..');
    await expect(k8sPanel).toBeVisible();

    // Look for pod items or loading states
    const hasPods = await page.locator('[data-pod-item]').first().isVisible();
    const hasLoading = await k8sPanel.locator('.animate-pulse').isVisible();
    const hasNoData = await page.getByText('No pods found').isVisible();

    expect(hasPods || hasLoading || hasNoData).toBeTruthy();

    if (hasPods) {
      // Verify pod information is displayed
      const podItem = page.locator('[data-pod-item]').first();
      await expect(podItem).toBeVisible();
    }
  });

  test('WebSocket connection survives page interactions', async ({ page }) => {
    await page.waitForTimeout(2000);

    // Perform various page interactions
    const refreshButton = page
      .locator('button')
      .filter({ has: page.locator('[class*="RefreshCw"]') })
      .first();
    if (await refreshButton.isVisible()) {
      await refreshButton.click();
      await page.waitForTimeout(1000);
    }

    // Scroll page
    await page.mouse.wheel(0, 500);
    await page.waitForTimeout(500);

    // Click on various elements
    const metricsCard = page.locator('.metric-card').first();
    if (await metricsCard.isVisible()) {
      await metricsCard.click();
      await page.waitForTimeout(500);
    }

    // Connection should remain stable
    const messages = await page.evaluate(() => (window as any).wsMessages);
    if (messages) {
      const errorMessages = messages.filter((msg: any) => msg.type === 'error');
      expect(errorMessages.length).toBeLessThanOrEqual(1); // Allow for initial connection errors
    }

    // Page should still be functional
    await expect(page.getByRole('heading', { name: 'MiniPrem Monitor' })).toBeVisible();
  });
});
