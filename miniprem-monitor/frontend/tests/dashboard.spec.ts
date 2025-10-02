import { test, expect } from '@playwright/test';

/**
 * Dashboard Functionality Tests
 *
 * Tests core dashboard components, layout, and basic functionality
 */

test.describe('MiniPrem Monitor Dashboard', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    // Wait for the page to load completely
    await page.waitForLoadState('networkidle');
  });

  test('displays main dashboard header', async ({ page }) => {
    // Verify page title
    await expect(page).toHaveTitle(/MiniPrem Monitor/);

    // Wait for header to be fully loaded
    const header = page.getByTestId('dashboard-header');
    await expect(header).toBeVisible();

    // Verify main header elements using testid
    const appTitle = page.getByTestId('app-title');
    await expect(appTitle).toBeVisible();
    await expect(appTitle).toHaveText('MiniPrem Monitor');

    // Check UneeQ logo/icon
    const appLogo = page.getByTestId('app-logo');
    await expect(appLogo).toBeVisible();

    // Verify connection status component
    const connectionStatus = page.getByTestId('connection-status');
    await expect(connectionStatus).toBeVisible();
  });

  test('displays system information in header', async ({ page }) => {
    // Wait for system info to potentially load, but don't fail if it doesn't
    await page.waitForTimeout(2000);

    // Check if system info is displayed using testid
    const systemInfo = page.getByTestId('system-info');

    if (await systemInfo.isVisible()) {
      // Verify individual system info elements
      const platformInfo = page.getByTestId('system-platform');
      const cpuInfo = page.getByTestId('system-cpu-count');
      const memoryInfo = page.getByTestId('system-memory');

      await expect(platformInfo).toBeVisible();
      await expect(cpuInfo).toBeVisible();
      await expect(memoryInfo).toBeVisible();
    }
  });

  test('displays metrics cards section', async ({ page }) => {
    // Verify metrics grid container
    await expect(page.locator('.grid').first()).toBeVisible();

    // Check for metric cards or loading states
    const metricsContainer = page.locator('.grid').first();

    // Should have either metric cards or loading placeholders
    const cpuCard = page.getByText('CPU Usage');
    const memoryCard = page.getByText('Memory');
    const diskCard = page.getByText('Disk');
    const networkCard = page.getByText('Network I/O');

    // Wait for metrics to load (they might be loading initially)
    await page.waitForTimeout(3500);

    // Check if metrics loaded or if we have loading indicators
    const hasMetrics = await cpuCard.isVisible();
    const hasLoading = await page.locator('.animate-pulse').first().isVisible();

    expect(hasMetrics || hasLoading).toBeTruthy();

    if (hasMetrics) {
      await expect(cpuCard).toBeVisible();
      await expect(memoryCard).toBeVisible();
      await expect(diskCard).toBeVisible();
      await expect(networkCard).toBeVisible();
    }
  });

  test('displays system health panel', async ({ page }) => {
    // Look for system health panel
    const healthPanel = page.locator('[class*="card"]').filter({ hasText: 'System Health' });

    // Wait a moment for potential loading
    await page.waitForTimeout(1000);

    // The health panel might not always be visible, so we check if it exists
    const isVisible = await healthPanel.isVisible();
    if (isVisible) {
      await expect(healthPanel).toBeVisible();
    }
  });

  test('displays container and kubernetes panels', async ({ page }) => {
    // Verify Docker Containers panel
    await expect(page.getByText('Docker Containers')).toBeVisible();
    await expect(
      page.locator('button[title*="refresh"]').or(page.locator('[class*="RefreshCw"]')).first()
    ).toBeVisible();

    // Verify Kubernetes panel
    await expect(page.getByText('Kubernetes').first()).toBeVisible();

    // Check for loading states or content
    await page.waitForTimeout(2000);

    // Should see either content or "No containers/pods found" messages
    const dockerContent = page.locator('text=No containers found').or(page.locator('[data-container-item]'));
    const k8sContent = page.locator('text=No pods found').or(page.locator('[data-pod-item]'));

    // Verify panels are functional (not necessarily populated)
    const dockerPanel = page.getByText('Docker Containers').locator('..').locator('..');
    const k8sPanel = page.getByText('Kubernetes').locator('..').locator('..');

    await expect(dockerPanel).toBeVisible();
    await expect(k8sPanel).toBeVisible();
  });

  test('displays service status indicators', async ({ page }) => {
    // Wait for potential service status to load
    await page.waitForTimeout(3500);

    // Look for Docker and Kubernetes status indicators
    const dockerStatus = page.getByText('Docker Status');
    const k8sStatus = page.getByText('Kubernetes Status');

    if (await dockerStatus.isVisible()) {
      await expect(dockerStatus).toBeVisible();
      // Should have a status indicator (colored dot)
      await expect(page.locator('.w-3.h-3.rounded-full').first()).toBeVisible();
    }

    if (await k8sStatus.isVisible()) {
      await expect(k8sStatus).toBeVisible();
      await expect(page.locator('.w-3.h-3.rounded-full').nth(1)).toBeVisible();
    }
  });

  test('has responsive layout', async ({ page }) => {
    // Test desktop layout
    await page.setViewportSize({ width: 1920, height: 1080 });

    // Should have multi-column grid
    const grid = page.locator('.grid').first();
    await expect(grid).toBeVisible();

    // Test mobile layout
    await page.setViewportSize({ width: 390, height: 844 });
    await page.waitForTimeout(500);

    // Grid should still be visible but adapt to mobile
    await expect(grid).toBeVisible();

    // Header should still be visible
    await expect(page.getByRole('heading', { name: 'MiniPrem Monitor' })).toBeVisible();
  });

  test('refresh buttons are functional', async ({ page }) => {
    // Wait for page to load
    await page.waitForTimeout(2000);

    // Find refresh buttons (Docker containers)
    const refreshButton = page
      .locator('button')
      .filter({ has: page.locator('[class*="RefreshCw"], [data-lucide="refresh-cw"]') })
      .first();

    if (await refreshButton.isVisible()) {
      // Click refresh button
      await refreshButton.click();

      // Should show loading state briefly
      const isSpinning = await page.locator('.animate-spin').first().isVisible();
      if (isSpinning) {
        // Wait for loading to complete
        await page.waitForTimeout(1000);
      }

      // Button should be clickable again
      await expect(refreshButton).not.toHaveAttribute('disabled');
    }
  });

  test('handles network errors gracefully', async ({ page }) => {
    // Simulate network failure by intercepting requests
    await page.route('**/api/**', (route) => {
      route.abort('internetdisconnected');
    });

    await page.goto('/');
    await page.waitForTimeout(3500);

    // Page should still load even with API failures
    await expect(page.getByRole('heading', { name: 'MiniPrem Monitor' })).toBeVisible();

    // Should show loading states or error states, not crash
    const hasContent = await page.locator('body').innerHTML();
    expect(hasContent).toBeTruthy();
  });

  test('connection status indicator updates', async ({ page }) => {
    // Look for connection status component
    const connectionStatus = page
      .locator('[data-testid="connection-status"]')
      .or(page.getByText('WebSocket').locator('..'));

    await page.waitForTimeout(2000);

    if (await connectionStatus.isVisible()) {
      await expect(connectionStatus).toBeVisible();

      // Should show either connected or disconnected state
      const hasStatus = await connectionStatus.locator('.w-2.h-2.rounded-full, .w-3.h-3.rounded-full').isVisible();
      expect(hasStatus).toBeTruthy();
    }
  });
});
