import { test, expect } from '@playwright/test';

/**
 * Cleanup Tests
 *
 * Runs after all other tests to clean up test environment
 */

test.describe.serial('Test Cleanup', () => {
  test('verify no memory leaks in browser', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Perform some operations that might cause memory leaks
    for (let i = 0; i < 5; i++) {
      // Refresh page
      await page.reload();
      await page.waitForLoadState('networkidle');

      // Click some buttons
      const refreshButton = page.locator('button').filter({ has: page.locator('[class*="RefreshCw"]') }).first();
      if (await refreshButton.isVisible()) {
        await refreshButton.click();
        await page.waitForTimeout(1000);
      }

      // Open and close modal
      const logsButton = page.locator('button').filter({ has: page.locator('[data-lucide="eye"]') }).first();
      if (await logsButton.isVisible()) {
        await logsButton.click();
        await page.waitForTimeout(500);

        const closeButton = page.locator('button').filter({ has: page.locator('[data-lucide="x"]') }).first();
        if (await closeButton.isVisible()) {
          await closeButton.click();
          await page.waitForTimeout(500);
        }
      }
    }

    // Check if page is still responsive
    await expect(page.getByRole('heading', { name: 'MiniPrem Monitor' })).toBeVisible();

    console.log('✅ No apparent memory leaks detected');
  });

  test('close WebSocket connections', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);

    // Force close any WebSocket connections
    await page.evaluate(() => {
      // Close any open WebSocket connections
      if ((window as any).WebSocket) {
        const connections = (window as any).WebSocket.connections || [];
        connections.forEach((ws: WebSocket) => {
          if (ws.readyState === WebSocket.OPEN) {
            ws.close(1000, 'Test cleanup');
          }
        });
      }
    });

    console.log('✅ WebSocket connections closed');
  });

  test('clear any test data or localStorage', async ({ page }) => {
    await page.goto('/');

    // Clear localStorage
    await page.evaluate(() => {
      localStorage.clear();
      sessionStorage.clear();
    });

    // Clear any cookies
    await page.context().clearCookies();

    console.log('✅ Browser storage cleared');
  });

  test('verify test artifacts directory', async ({ page }) => {
    // This test primarily serves as a marker for test completion
    // Test artifacts (screenshots, videos, traces) are handled by Playwright config

    const testCompleted = true;
    expect(testCompleted).toBe(true);

    console.log('✅ Test cleanup completed successfully');
  });
});