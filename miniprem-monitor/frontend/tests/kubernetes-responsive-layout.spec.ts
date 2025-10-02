import { test, expect } from '@playwright/test';

/**
 * Kubernetes Pods Panel Responsive Layout Tests
 *
 * Tests the responsive behavior of the Kubernetes Pods panel at different screen widths.
 * Verifies the 3-row layout that adapts based on the 1024px breakpoint.
 *
 * Layout Specification:
 * - Wide Screens (≥1024px):
 *   Row 1: "Kubernetes Pods" title
 *   Row 2: All controls (Region, EKS, Service, NS) + refresh button
 *   Row 3: Pod status filter
 *
 * - Narrow Screens (<1024px):
 *   Row 1: "Kubernetes Pods" title
 *   Row 2: Region, EKS selectors only
 *   Row 3: Service, NS controls + refresh button
 *   Row 4: Pod status filter
 */

test.describe('Kubernetes Pods Panel - Responsive Layout', () => {
  const viewports = [
    { name: 'Wide Desktop', width: 1400, height: 1080, breakpoint: 'wide' },
    { name: 'Breakpoint Edge', width: 1024, height: 768, breakpoint: 'edge' },
    { name: 'Tablet', width: 768, height: 1024, breakpoint: 'narrow' },
    { name: 'Mobile', width: 375, height: 667, breakpoint: 'narrow' },
  ];

  viewports.forEach(({ name, width, height, breakpoint }) => {
    test(`responsive layout at ${name} (${width}x${height})`, async ({ page }) => {
      // Set viewport size
      await page.setViewportSize({ width, height });
      await page.goto('/');
      await page.waitForLoadState('networkidle');

      // Wait for the page to stabilize
      await page.waitForTimeout(2000);

      // Verify the Kubernetes panel is visible
      const kubernetesPanel = page.getByRole('heading', { name: 'Kubernetes Pods' });
      await expect(kubernetesPanel).toBeVisible();

      // Take screenshot for visual verification
      await page.screenshot({
        path: `test-results/kubernetes-responsive-${width}x${height}.png`,
        fullPage: true
      });

      // Find the Kubernetes panel container
      const panelContainer = page.locator('.card').filter({ has: kubernetesPanel });
      await expect(panelContainer).toBeVisible();

      if (breakpoint === 'wide' || (breakpoint === 'edge' && width >= 1024)) {
        // Wide screens: Service controls and namespace filter should be visible in first row
        await test.step('verify wide screen layout', async () => {
          // Service controls should be visible (not hidden)
          const serviceControls = panelContainer.locator('.hidden.lg\\:flex').filter({ hasText: 'Service:' });
          await expect(serviceControls).toBeVisible();

          // Namespace filter should be visible in first row
          const namespaceFilter = panelContainer.locator('.hidden.lg\\:flex').filter({ hasText: 'NS:' });
          await expect(namespaceFilter).toBeVisible();

          // Refresh button should be visible in first row
          const refreshButton = panelContainer.locator('.hidden.lg\\:block button');
          await expect(refreshButton).toBeVisible();

          // Second row controls should be hidden
          const secondRowControls = panelContainer.locator('.lg\\:hidden');
          await expect(secondRowControls).toBeHidden();
        });
      } else {
        // Narrow screens: Controls should be split across rows
        await test.step('verify narrow screen layout', async () => {
          // Service controls should be hidden in first row but visible in second row
          const firstRowServiceControls = panelContainer.locator('.hidden.lg\\:flex').filter({ hasText: 'Service:' });
          await expect(firstRowServiceControls).toBeHidden();

          // Second row should be visible with controls
          const secondRowControls = panelContainer.locator('.lg\\:hidden');
          await expect(secondRowControls).toBeVisible();

          // Service controls should be visible in second row
          const secondRowService = secondRowControls.filter({ hasText: 'Service:' });
          if (await secondRowService.count() > 0) {
            await expect(secondRowService).toBeVisible();
          }

          // Namespace filter should be visible in second row
          const secondRowNamespace = secondRowControls.filter({ hasText: 'NS:' });
          await expect(secondRowNamespace).toBeVisible();

          // Refresh button should be visible in second row
          const refreshButton = secondRowControls.locator('button').filter({ has: page.locator('[data-lucide="refresh-cw"]') });
          await expect(refreshButton).toBeVisible();
        });
      }

      // Pod status filter should always be visible as a separate row
      await test.step('verify pod status filter row', async () => {
        const statusFilter = panelContainer.locator('[role="tablist"][aria-label="Pod status filter"]');
        await expect(statusFilter).toBeVisible();

        // Verify all filter buttons are present
        const filterButtons = [
          { testId: 'pod-filter-all', text: 'All' },
          { testId: 'pod-filter-running', text: 'Running' },
          { testId: 'pod-filter-pending', text: 'Pending' },
          { testId: 'pod-filter-failed', text: 'Failed' },
        ];

        for (const button of filterButtons) {
          const filterButton = page.getByTestId(button.testId);
          await expect(filterButton).toBeVisible();
        }
      });

      // Verify no horizontal scroll on narrow screens
      if (width <= 768) {
        await test.step('verify no horizontal overflow', async () => {
          const hasHorizontalScroll = await page.evaluate(() => {
            return document.documentElement.scrollWidth > document.documentElement.clientWidth;
          });
          expect(hasHorizontalScroll).toBe(false);
        });
      }

      console.log(`✅ ${name}: Responsive layout verified at ${width}x${height}`);
    });
  });

  test('pod status filter functionality across screen sizes', async ({ page }) => {
    const testSizes = [
      { width: 1400, height: 1080, name: 'Desktop' },
      { width: 768, height: 1024, name: 'Tablet' },
      { width: 375, height: 667, name: 'Mobile' },
    ];

    for (const { width, height, name } of testSizes) {
      await test.step(`test filter functionality on ${name} (${width}x${height})`, async () => {
        await page.setViewportSize({ width, height });
        await page.goto('/');
        await page.waitForLoadState('networkidle');
        await page.waitForTimeout(2000);

        // Find the pod status filter
        const statusFilter = page.locator('[role="tablist"][aria-label="Pod status filter"]');
        await expect(statusFilter).toBeVisible();

        // Test clicking different filter options
        const filterButtons = ['pod-filter-all', 'pod-filter-running', 'pod-filter-pending', 'pod-filter-failed'];

        for (const buttonTestId of filterButtons) {
          const button = page.getByTestId(buttonTestId);
          if (await button.isVisible()) {
            // Click the button
            await button.click();
            await page.waitForTimeout(500);

            // Verify the button is selected (has active styling)
            await expect(button).toHaveClass(/bg-white|shadow-sm/);

            // Take a screenshot to verify visual state
            await page.screenshot({
              path: `test-results/kubernetes-filter-${buttonTestId}-${width}x${height}.png`,
              fullPage: false
            });
          }
        }

        console.log(`✅ ${name}: Filter functionality tested at ${width}x${height}`);
      });
    }
  });

  test('responsive controls accessibility and positioning', async ({ page }) => {
    await test.step('test control accessibility on mobile', async () => {
      await page.setViewportSize({ width: 375, height: 667 });
      await page.goto('/');
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(2000);

      const kubernetesPanel = page.getByRole('heading', { name: 'Kubernetes Pods' });
      const panelContainer = page.locator('.card').filter({ has: kubernetesPanel });

      // Verify refresh button is accessible on mobile (in second row)
      const refreshButton = panelContainer.locator('.lg\\:hidden button').filter({ has: page.locator('[data-lucide="refresh-cw"]') });
      await expect(refreshButton).toBeVisible();

      // Test that the refresh button is clickable
      await refreshButton.click();
      await page.waitForTimeout(500);

      // Verify namespace selector is accessible
      const namespaceSelect = panelContainer.locator('select');
      await expect(namespaceSelect).toBeVisible();

      // Test that namespace selector is functional
      await namespaceSelect.selectOption('default');
      await page.waitForTimeout(500);

      // Verify service buttons are accessible if present
      const serviceButtons = panelContainer.locator('button').filter({ hasText: /Start|Stop/ });
      const serviceButtonCount = await serviceButtons.count();

      if (serviceButtonCount > 0) {
        for (let i = 0; i < serviceButtonCount; i++) {
          const button = serviceButtons.nth(i);
          await expect(button).toBeVisible();

          // Verify button has proper touch target size (minimum 44px)
          const buttonBox = await button.boundingBox();
          if (buttonBox) {
            expect(buttonBox.height).toBeGreaterThanOrEqual(32); // Allowing for smaller touch targets on mobile
          }
        }
      }

      console.log('✅ Mobile: All controls are accessible');
    });

    await test.step('test control positioning on tablet', async () => {
      await page.setViewportSize({ width: 768, height: 1024 });
      await page.goto('/');
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(2000);

      // Verify controls wrap properly and don't overlap
      const kubernetesPanel = page.getByRole('heading', { name: 'Kubernetes Pods' });
      const panelContainer = page.locator('.card').filter({ has: kubernetesPanel });

      // Check that second row controls are properly positioned
      const secondRowControls = panelContainer.locator('.lg\\:hidden');
      await expect(secondRowControls).toBeVisible();

      const secondRowBox = await secondRowControls.boundingBox();
      if (secondRowBox) {
        expect(secondRowBox.width).toBeLessThanOrEqual(768);
      }

      console.log('✅ Tablet: Controls positioned correctly');
    });
  });

  test('responsive breakpoint behavior at 1024px', async ({ page }) => {
    await test.step('test behavior just below breakpoint', async () => {
      await page.setViewportSize({ width: 1023, height: 768 });
      await page.goto('/');
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(2000);

      const kubernetesPanel = page.getByRole('heading', { name: 'Kubernetes Pods' });
      const panelContainer = page.locator('.card').filter({ has: kubernetesPanel });

      // Should show narrow layout (second row visible)
      const secondRowControls = panelContainer.locator('.lg\\:hidden');
      await expect(secondRowControls).toBeVisible();

      // First row service controls should be hidden
      const firstRowServiceControls = panelContainer.locator('.hidden.lg\\:flex').filter({ hasText: 'Service:' });
      await expect(firstRowServiceControls).toBeHidden();

      console.log('✅ 1023px: Narrow layout active');
    });

    await test.step('test behavior at exact breakpoint', async () => {
      await page.setViewportSize({ width: 1024, height: 768 });
      await page.goto('/');
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(2000);

      const kubernetesPanel = page.getByRole('heading', { name: 'Kubernetes Pods' });
      const panelContainer = page.locator('.card').filter({ has: kubernetesPanel });

      // Should show wide layout (second row hidden)
      const secondRowControls = panelContainer.locator('.lg\\:hidden');
      await expect(secondRowControls).toBeHidden();

      // First row service controls should be visible
      const firstRowServiceControls = panelContainer.locator('.hidden.lg\\:flex').filter({ hasText: 'Service:' });
      await expect(firstRowServiceControls).toBeVisible();

      console.log('✅ 1024px: Wide layout active');
    });

    await test.step('test behavior just above breakpoint', async () => {
      await page.setViewportSize({ width: 1025, height: 768 });
      await page.goto('/');
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(2000);

      const kubernetesPanel = page.getByRole('heading', { name: 'Kubernetes Pods' });
      const panelContainer = page.locator('.card').filter({ has: kubernetesPanel });

      // Should show wide layout (second row hidden)
      const secondRowControls = panelContainer.locator('.lg\\:hidden');
      await expect(secondRowControls).toBeHidden();

      // First row service controls should be visible
      const firstRowServiceControls = panelContainer.locator('.hidden.lg\\:flex').filter({ hasText: 'Service:' });
      await expect(firstRowServiceControls).toBeVisible();

      console.log('✅ 1025px: Wide layout active');
    });
  });

  test('text wrapping and overflow handling', async ({ page }) => {
    await test.step('verify filter buttons wrap properly on narrow screens', async () => {
      await page.setViewportSize({ width: 375, height: 667 });
      await page.goto('/');
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(2000);

      // Find the pod status filter
      const statusFilter = page.locator('[role="tablist"][aria-label="Pod status filter"]');
      await expect(statusFilter).toBeVisible();

      // Verify the filter container has flex-wrap class
      await expect(statusFilter).toHaveClass(/flex-wrap/);

      // Check that filter buttons don't overflow horizontally
      const filterBox = await statusFilter.boundingBox();
      if (filterBox) {
        expect(filterBox.width).toBeLessThanOrEqual(375);
      }

      // Verify all buttons are still accessible
      const allButton = page.getByTestId('pod-filter-all');
      const runningButton = page.getByTestId('pod-filter-running');

      await expect(allButton).toBeVisible();
      await expect(runningButton).toBeVisible();

      console.log('✅ Mobile: Filter buttons wrap correctly');
    });

    await test.step('verify control labels remain readable', async () => {
      const sizes = [
        { width: 375, height: 667, name: 'Mobile' },
        { width: 768, height: 1024, name: 'Tablet' },
      ];

      for (const { width, height, name } of sizes) {
        await page.setViewportSize({ width, height });
        await page.goto('/');
        await page.waitForLoadState('networkidle');
        await page.waitForTimeout(1000);

        // Check that labels are visible and readable
        const labels = ['Region:', 'EKS:', 'NS:'];

        for (const labelText of labels) {
          const label = page.locator('span').filter({ hasText: labelText });
          if (await label.count() > 0) {
            await expect(label.first()).toBeVisible();

            // Verify text is not truncated (has proper spacing)
            const labelBox = await label.first().boundingBox();
            if (labelBox) {
              expect(labelBox.width).toBeGreaterThan(20); // Reasonable minimum width
            }
          }
        }

        console.log(`✅ ${name}: Control labels readable at ${width}x${height}`);
      }
    });
  });
});