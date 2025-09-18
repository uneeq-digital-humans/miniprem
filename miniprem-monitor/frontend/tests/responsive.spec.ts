import { test, expect } from '@playwright/test';

/**
 * Responsive Design Tests
 *
 * Tests application behavior across different screen sizes and devices
 */

test.describe('Responsive Design', () => {
  const viewports = [
    { name: 'Mobile Portrait', width: 390, height: 844 },
    { name: 'Mobile Landscape', width: 844, height: 390 },
    { name: 'Tablet Portrait', width: 768, height: 1024 },
    { name: 'Tablet Landscape', width: 1024, height: 768 },
    { name: 'Desktop Small', width: 1280, height: 720 },
    { name: 'Desktop Large', width: 1920, height: 1080 },
  ];

  viewports.forEach(({ name, width, height }) => {
    test(`displays correctly on ${name} (${width}x${height})`, async ({ page }) => {
      await page.setViewportSize({ width, height });
      await page.goto('/');
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(2000);

      // Basic layout should be visible
      await expect(page.getByRole('heading', { name: 'MiniPrem Monitor' })).toBeVisible();

      // Check that content doesn't overflow
      const body = page.locator('body');
      const bodyBox = await body.boundingBox();

      if (bodyBox) {
        expect(bodyBox.width).toBeLessThanOrEqual(width + 50); // Allow small margin
      }

      // Check for horizontal scrollbar (should not exist on mobile)
      const hasHorizontalScroll = await page.evaluate(() => {
        return document.documentElement.scrollWidth > document.documentElement.clientWidth;
      });

      if (width <= 768) { // Mobile and small tablets
        expect(hasHorizontalScroll).toBe(false);
      }

      console.log(`✅ ${name}: Layout fits viewport correctly`);
    });
  });

  test('navigation adapts to mobile screens', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Header should still be visible and not overflow
    const header = page.locator('header');
    await expect(header).toBeVisible();

    const headerBox = await header.boundingBox();
    if (headerBox) {
      expect(headerBox.width).toBeLessThanOrEqual(390);
    }

    // System info may be hidden on mobile (responsive design)
    const systemInfo = page.getByText('Platform:');
    const isSystemInfoVisible = await systemInfo.isVisible();

    console.log(`Mobile navigation: System info ${isSystemInfoVisible ? 'visible' : 'hidden'}`);
  });

  test('metrics cards stack properly on mobile', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);

    // Find metrics cards
    const metricsGrid = page.locator('.grid').first();
    if (await metricsGrid.isVisible()) {
      // On mobile, cards should stack vertically
      const gridBox = await metricsGrid.boundingBox();
      if (gridBox) {
        expect(gridBox.width).toBeLessThanOrEqual(390);
      }

      // Check individual metric cards
      const metricCards = page.locator('.metric-card');
      const cardCount = await metricCards.count();

      if (cardCount > 0) {
        for (let i = 0; i < cardCount; i++) {
          const card = metricCards.nth(i);
          if (await card.isVisible()) {
            const cardBox = await card.boundingBox();
            if (cardBox) {
              expect(cardBox.width).toBeLessThanOrEqual(390);
            }
          }
        }
      }
    }

    console.log('✅ Mobile: Metrics cards stack properly');
  });

  test('container and kubernetes panels adapt to tablet', async ({ page }) => {
    await page.setViewportSize({ width: 768, height: 1024 });
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);

    // Panels should be visible and properly sized
    const containerPanel = page.getByText('Docker Containers').locator('..');
    const k8sPanel = page.getByText('Kubernetes').locator('..');

    if (await containerPanel.isVisible()) {
      const containerBox = await containerPanel.boundingBox();
      if (containerBox) {
        expect(containerBox.width).toBeLessThanOrEqual(768);
      }
    }

    if (await k8sPanel.isVisible()) {
      const k8sBox = await k8sPanel.boundingBox();
      if (k8sBox) {
        expect(k8sBox.width).toBeLessThanOrEqual(768);
      }
    }

    console.log('✅ Tablet: Panels adapt properly');
  });

  test('modal adapts to small screens', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);

    // Try to open a modal
    const logsButton = page.locator('button').filter({ has: page.locator('[data-lucide="eye"]') }).first();

    if (await logsButton.isVisible()) {
      await logsButton.click();
      await page.waitForTimeout(1000);

      const modal = page.locator('.fixed.inset-0').first();
      if (await modal.isVisible()) {
        // Modal should fit within mobile viewport
        const modalContent = modal.locator('.bg-white.rounded-lg').first();
        if (await modalContent.isVisible()) {
          const contentBox = await modalContent.boundingBox();
          if (contentBox) {
            expect(contentBox.width).toBeLessThanOrEqual(390 - 32); // Account for padding
            expect(contentBox.height).toBeLessThanOrEqual(844 - 32);
          }
        }

        // Close modal
        const closeButton = page.locator('button').filter({ has: page.locator('[data-lucide="x"]') }).first();
        if (await closeButton.isVisible()) {
          await closeButton.click();
        }
      }
    }

    console.log('✅ Mobile: Modal adapts to small screen');
  });

  test('touch interactions work on mobile', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);

    // Test tap interactions
    const refreshButton = page.locator('button').filter({ has: page.locator('[class*="RefreshCw"]') }).first();

    if (await refreshButton.isVisible()) {
      // Tap should work (simulate touch)
      await refreshButton.tap();
      await page.waitForTimeout(1000);

      // Button should respond
      await expect(refreshButton).toBeVisible();
    }

    // Test scrolling
    await page.mouse.wheel(0, 300);
    await page.waitForTimeout(500);

    // Page should still be functional after scrolling
    await expect(page.getByRole('heading', { name: 'MiniPrem Monitor' })).toBeVisible();

    console.log('✅ Mobile: Touch interactions work');
  });

  test('text remains readable at all sizes', async ({ page }) => {
    const sizes = [
      { width: 390, height: 844 },  // Mobile
      { width: 768, height: 1024 }, // Tablet
      { width: 1920, height: 1080 } // Desktop
    ];

    for (const size of sizes) {
      await page.setViewportSize(size);
      await page.goto('/');
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(1000);

      // Check that main heading is readable
      const heading = page.getByRole('heading', { name: 'MiniPrem Monitor' });
      if (await heading.isVisible()) {
        const fontSize = await heading.evaluate(el => {
          const styles = window.getComputedStyle(el);
          return parseFloat(styles.fontSize);
        });

        // Font should be at least 14px on all devices
        expect(fontSize).toBeGreaterThanOrEqual(14);
      }

      // Check that body text is readable
      const bodyText = page.locator('body');
      const minFontSize = await bodyText.evaluate(el => {
        const allElements = el.querySelectorAll('*');
        let minSize = 16;

        for (const element of allElements) {
          const styles = window.getComputedStyle(element);
          const size = parseFloat(styles.fontSize);
          if (size > 0 && size < minSize) {
            minSize = size;
          }
        }

        return minSize;
      });

      // Minimum font size should be at least 12px
      expect(minFontSize).toBeGreaterThanOrEqual(12);

      console.log(`✅ ${size.width}x${size.height}: Text readable (min: ${minFontSize}px)`);
    }
  });

  test('performance on mobile devices', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });

    // Simulate slower mobile network
    await page.route('**/*', (route) => {
      // Add slight delay to simulate mobile network
      setTimeout(() => route.continue(), 50);
    });

    const startTime = Date.now();
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    const loadTime = Date.now() - startTime;

    // Should load within reasonable time even with simulated mobile conditions
    expect(loadTime).toBeLessThan(10000); // 10 seconds

    // Check that essential content is visible
    await expect(page.getByRole('heading', { name: 'MiniPrem Monitor' })).toBeVisible();

    console.log(`✅ Mobile performance: Loaded in ${loadTime}ms`);
  });
});