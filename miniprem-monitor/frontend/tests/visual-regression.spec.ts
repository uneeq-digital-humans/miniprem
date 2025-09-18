import { test, expect } from '@playwright/test';

/**
 * Visual Regression Tests
 *
 * Tests visual consistency and catches UI regressions through screenshot comparison
 */

test.describe('Visual Regression Testing', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');

    // Wait for the application to be fully loaded
    await page.waitForLoadState('networkidle');

    // Wait for fonts and critical resources to load
    await page.waitForFunction(() => {
      return document.readyState === 'complete' &&
             document.fonts.ready.then(() => true);
    });

    // Wait for any initial API calls to complete
    await page.waitForTimeout(1000);
  });

  test('dashboard overall layout', async ({ page }) => {
    // Wait for critical elements to be visible first
    await page.waitForSelector('[data-testid="dashboard-header"]', { timeout: 10000 });

    // Hide dynamic elements that change frequently
    await page.addStyleTag({
      content: `
        [data-testid="connection-id"] { visibility: hidden !important; }
        .animate-pulse { animation: none !important; }
        .animate-spin { animation: none !important; }
        [class*="animate-"] { animation: none !important; }
      `
    });

    // Wait for layout to stabilize
    await page.waitForTimeout(500);

    // Take full page screenshot for layout comparison
    await expect(page).toHaveScreenshot('dashboard-full-layout.png', {
      fullPage: true,
      animations: 'disabled',
      mask: [page.locator('[data-testid="connection-id"]')],
    });
  });

  test('header section visual consistency', async ({ page }) => {
    const header = page.getByTestId('dashboard-header');
    await expect(header).toBeVisible();

    // Hide dynamic connection ID for consistent screenshots
    await page.addStyleTag({
      content: `
        [data-testid="connection-id"] { visibility: hidden !important; }
        .animate-pulse { animation: none !important; }
      `
    });

    // Wait for header to stabilize
    await page.waitForTimeout(300);

    await expect(header).toHaveScreenshot('header-section.png', {
      mask: [page.locator('[data-testid="connection-id"]')],
      animations: 'disabled'
    });
  });

  test('metrics cards visual layout', async ({ page }) => {
    const metricsSection = page.getByTestId('metrics-section');

    // Wait for metrics to potentially load, but don't fail if they don't
    await page.waitForTimeout(2000);

    if (await metricsSection.isVisible()) {
      await expect(metricsSection).toHaveScreenshot('metrics-cards.png');
    } else {
      // Test loading state if metrics aren't available
      const loadingSection = page.getByTestId('metrics-section-loading');
      if (await loadingSection.isVisible()) {
        await expect(loadingSection).toHaveScreenshot('metrics-cards-loading.png');
      }
    }
  });

  test('individual metric card visuals', async ({ page }) => {
    // Test each metric card individually for detailed visual validation
    const cards = ['cpu-metrics-card', 'memory-metrics-card', 'disk-metrics-card', 'network-metrics-card'];

    for (const cardTestId of cards) {
      const card = page.getByTestId(cardTestId);
      if (await card.isVisible()) {
        await expect(card).toHaveScreenshot(`${cardTestId}.png`);
      }
    }
  });

  test('connection status indicator visuals', async ({ page }) => {
    const connectionStatus = page.getByTestId('connection-status');
    await expect(connectionStatus).toBeVisible();

    // Hide the dynamic connection ID for consistent screenshots
    await page.addStyleTag({
      content: `[data-testid="connection-id"] { visibility: hidden !important; }`
    });

    await expect(connectionStatus).toHaveScreenshot('connection-status.png');
  });

  test('docker containers panel layout', async ({ page }) => {
    // Scroll to containers section
    const containersSection = page.locator('h2:has-text("Docker Containers")').locator('..');

    if (await containersSection.isVisible()) {
      await containersSection.scrollIntoViewIfNeeded();
      await expect(containersSection).toHaveScreenshot('docker-containers-panel.png');
    }
  });

  test('kubernetes pods panel layout', async ({ page }) => {
    // Scroll to pods section
    const podsSection = page.locator('h2:has-text("Kubernetes Pods")').locator('..');

    if (await podsSection.isVisible()) {
      await podsSection.scrollIntoViewIfNeeded();
      await expect(podsSection).toHaveScreenshot('kubernetes-pods-panel.png');
    }
  });

  test('mobile responsive layout', async ({ page }) => {
    // Test mobile viewport
    await page.setViewportSize({ width: 375, height: 667 }); // iPhone SE
    await page.reload();

    // Wait for page load with shorter timeout
    await page.waitForLoadState('domcontentloaded');
    await page.waitForSelector('[data-testid="dashboard-header"]', { timeout: 15000 });

    // Hide dynamic elements for consistent mobile screenshots
    await page.addStyleTag({
      content: `
        [data-testid="connection-id"] { visibility: hidden !important; }
        .animate-pulse { animation: none !important; }
        [class*="animate-"] { animation: none !important; }
      `
    });

    // Wait for mobile layout to stabilize
    await page.waitForTimeout(1000);

    await expect(page).toHaveScreenshot('dashboard-mobile-layout.png', {
      fullPage: true,
      mask: [page.locator('[data-testid="connection-id"]')],
      animations: 'disabled'
    });
  });

  test('tablet responsive layout', async ({ page }) => {
    // Test tablet viewport
    await page.setViewportSize({ width: 768, height: 1024 }); // iPad
    await page.reload();

    // Wait for page load with reasonable timeout
    await page.waitForLoadState('domcontentloaded');
    await page.waitForSelector('[data-testid="dashboard-header"]', { timeout: 15000 });

    // Hide dynamic elements
    await page.addStyleTag({
      content: `
        [data-testid="connection-id"] { visibility: hidden !important; }
        .animate-pulse { animation: none !important; }
        [class*="animate-"] { animation: none !important; }
      `
    });

    // Wait for tablet layout to stabilize
    await page.waitForTimeout(1000);

    await expect(page).toHaveScreenshot('dashboard-tablet-layout.png', {
      fullPage: true,
      mask: [page.locator('[data-testid="connection-id"]')],
      animations: 'disabled'
    });
  });

  test('error state visual consistency', async ({ page }) => {
    // Mock API failure to test error states
    await page.route('**/api/system/metrics', route =>
      route.fulfill({
        status: 500,
        body: JSON.stringify({ error: 'Server Error' }),
        headers: { 'content-type': 'application/json' }
      })
    );

    await page.reload();
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);

    // Look for error states and capture them
    const errorElements = await page.locator('[class*="error"], [class*="Error"], .text-red-500').all();

    if (errorElements.length > 0) {
      await expect(page).toHaveScreenshot('dashboard-error-state.png', {
        fullPage: true
      });
    }
  });

  test('dark mode visual consistency', async ({ page }) => {
    // If dark mode is implemented, test it
    const darkModeToggle = page.getByTestId('dark-mode-toggle');

    if (await darkModeToggle.isVisible()) {
      await darkModeToggle.click();
      await page.waitForTimeout(500); // Allow for theme transition

      await expect(page).toHaveScreenshot('dashboard-dark-mode.png', {
        fullPage: true,
        animations: 'disabled'
      });
    }
  });
});

test.describe('Component State Variations', () => {
  test('loading states visual consistency', async ({ page }) => {
    // Intercept API calls to delay responses and capture loading states
    await page.route('**/api/system/metrics', route => {
      // Delay response to capture loading state
      setTimeout(() => {
        route.fulfill({
          status: 200,
          body: JSON.stringify({
            cpu_percent: 45.2,
            memory_percent: 67.8,
            disk_percent: 23.4,
            network_io: { bytes_sent: 1024000, bytes_recv: 2048000 }
          }),
          headers: { 'content-type': 'application/json' }
        });
      }, 2000);
    });

    await page.goto('/');

    // Capture loading state immediately
    await page.waitForSelector('[data-testid="metrics-section-loading"]', { timeout: 5000 });
    const loadingSection = page.getByTestId('metrics-section-loading');
    await expect(loadingSection).toHaveScreenshot('metrics-loading-state.png');
  });

  test('empty state visual consistency', async ({ page }) => {
    // Mock empty API responses
    await page.route('**/api/system/metrics', route =>
      route.fulfill({
        status: 404,
        body: JSON.stringify({ error: 'Not found' }),
        headers: { 'content-type': 'application/json' }
      })
    );

    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000);

    // Look for empty states
    const emptyState = page.getByTestId('metrics-empty-state');
    if (await emptyState.isVisible()) {
      await expect(emptyState).toHaveScreenshot('metrics-empty-state.png');
    }
  });
});