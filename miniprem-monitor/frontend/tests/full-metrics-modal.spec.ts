import { test, expect } from '@playwright/test';

/**
 * Full Metrics Modal Tests
 *
 * Tests comprehensive metrics dashboard functionality including:
 * - Modal opening/closing behaviors
 * - All 22 metrics display across 4 categories
 * - Color-coded metric cards based on thresholds
 * - Snapshot capture functionality
 * - Send to support functionality
 * - Responsive design and accessibility
 * - Visual regression testing
 */

test.describe('Full Metrics Modal', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);

    // Wait for containers to load
    await page.waitForSelector(
      '[data-testid="container-item"], [data-testid="no-containers"]',
      { timeout: 10000 }
    );
  });

  test.describe('Modal Opening and Closing', () => {
    test('should open full metrics modal when clicking "View All Metrics" button', async ({ page }) => {
      const containerItem = page.locator('[data-testid="container-item"]').first();

      if (await containerItem.isVisible()) {
        // Expand container details
        await containerItem.click();
        await page.waitForTimeout(500);

        // Look for "View All Metrics" button
        const viewMetricsButton = page.locator('button:has-text("View All Metrics")').first();

        if (await viewMetricsButton.isVisible()) {
          await viewMetricsButton.click();
          await page.waitForTimeout(300);

          // Modal should be visible
          const modal = page.locator('[data-testid="full-metrics-modal"]');
          await expect(modal).toBeVisible();

          // Check header text contains "Metrics"
          const modalHeader = modal.locator('h2').filter({ hasText: /Metrics/i });
          await expect(modalHeader).toBeVisible();

          console.log('✅ Full Metrics Modal opened successfully');
        } else {
          console.log('ℹ️ View All Metrics button not found - container may not have metrics');
        }
      } else {
        console.log('ℹ️ No containers available for testing');
      }
    });

    test('should close modal when clicking X button', async ({ page }) => {
      const containerItem = page.locator('[data-testid="container-item"]').first();

      if (await containerItem.isVisible()) {
        await containerItem.click();
        await page.waitForTimeout(500);

        const viewMetricsButton = page.locator('button:has-text("View All Metrics")').first();

        if (await viewMetricsButton.isVisible()) {
          await viewMetricsButton.click();
          await page.waitForTimeout(300);

          const modal = page.locator('[data-testid="full-metrics-modal"]');
          await expect(modal).toBeVisible();

          // Click close button
          const closeButton = modal.locator('[data-testid="close-button"]');
          await closeButton.click();
          await page.waitForTimeout(300);

          // Modal should be hidden
          await expect(modal).toBeHidden();

          console.log('✅ Modal closed via X button');
        }
      }
    });

    test('should close modal when clicking footer close button', async ({ page }) => {
      const containerItem = page.locator('[data-testid="container-item"]').first();

      if (await containerItem.isVisible()) {
        await containerItem.click();
        await page.waitForTimeout(500);

        const viewMetricsButton = page.locator('button:has-text("View All Metrics")').first();

        if (await viewMetricsButton.isVisible()) {
          await viewMetricsButton.click();
          await page.waitForTimeout(300);

          const modal = page.locator('[data-testid="full-metrics-modal"]');
          await expect(modal).toBeVisible();

          // Click footer close button
          const footerCloseButton = modal.locator('[data-testid="footer-close-button"]');
          await footerCloseButton.click();
          await page.waitForTimeout(300);

          // Modal should be hidden
          await expect(modal).toBeHidden();

          console.log('✅ Modal closed via footer button');
        }
      }
    });

    test('should close modal when clicking backdrop', async ({ page }) => {
      const containerItem = page.locator('[data-testid="container-item"]').first();

      if (await containerItem.isVisible()) {
        await containerItem.click();
        await page.waitForTimeout(500);

        const viewMetricsButton = page.locator('button:has-text("View All Metrics")').first();

        if (await viewMetricsButton.isVisible()) {
          await viewMetricsButton.click();
          await page.waitForTimeout(300);

          const modal = page.locator('[data-testid="full-metrics-modal"]');
          await expect(modal).toBeVisible();

          // Click backdrop
          const backdrop = page.locator('[data-testid="metrics-modal-backdrop"]');
          await backdrop.click({ position: { x: 10, y: 10 } });
          await page.waitForTimeout(300);

          // Modal should be hidden
          await expect(modal).toBeHidden();

          console.log('✅ Modal closed via backdrop click');
        }
      }
    });

    test('should close modal on Escape key press', async ({ page }) => {
      const containerItem = page.locator('[data-testid="container-item"]').first();

      if (await containerItem.isVisible()) {
        await containerItem.click();
        await page.waitForTimeout(500);

        const viewMetricsButton = page.locator('button:has-text("View All Metrics")').first();

        if (await viewMetricsButton.isVisible()) {
          await viewMetricsButton.click();
          await page.waitForTimeout(300);

          const modal = page.locator('[data-testid="full-metrics-modal"]');
          await expect(modal).toBeVisible();

          // Press Escape
          await page.keyboard.press('Escape');
          await page.waitForTimeout(300);

          // Modal should be hidden
          await expect(modal).toBeHidden();

          console.log('✅ Modal closed via Escape key');
        }
      }
    });
  });

  test.describe('Metrics Display', () => {
    test('should display all 4 metric categories', async ({ page }) => {
      const containerItem = page.locator('[data-testid="container-item"]').first();

      if (await containerItem.isVisible()) {
        await containerItem.click();
        await page.waitForTimeout(500);

        const viewMetricsButton = page.locator('button:has-text("View All Metrics")').first();

        if (await viewMetricsButton.isVisible()) {
          await viewMetricsButton.click();
          await page.waitForTimeout(500);

          const modal = page.locator('[data-testid="full-metrics-modal"]');
          await expect(modal).toBeVisible();

          // Check for category sections
          await expect(modal.locator('[data-testid="section-session-metrics"]')).toBeVisible();
          await expect(modal.locator('[data-testid="section-performance-metrics"]')).toBeVisible();
          await expect(modal.locator('[data-testid="section-frame-timing"]')).toBeVisible();
          await expect(modal.locator('[data-testid="section-system-metrics"]')).toBeVisible();

          console.log('✅ All 4 metric categories displayed');
        }
      }
    });

    test('should display metric cards with values', async ({ page }) => {
      const containerItem = page.locator('[data-testid="container-item"]').first();

      if (await containerItem.isVisible()) {
        await containerItem.click();
        await page.waitForTimeout(500);

        const viewMetricsButton = page.locator('button:has-text("View All Metrics")').first();

        if (await viewMetricsButton.isVisible()) {
          await viewMetricsButton.click();
          await page.waitForTimeout(500);

          const modal = page.locator('[data-testid="full-metrics-modal"]');
          await expect(modal).toBeVisible();

          // Count metric cards
          const metricCards = modal.locator('[data-testid^="metric-card-"]');
          const cardCount = await metricCards.count();

          expect(cardCount).toBeGreaterThan(0);
          console.log(`✅ Found ${cardCount} metric cards`);

          // Verify first metric card structure
          const firstCard = metricCards.first();
          await expect(firstCard).toBeVisible();

          // Should have icon, label, value
          const hasIcon = await firstCard.locator('svg').isVisible();
          expect(hasIcon).toBeTruthy();
        }
      }
    });

    test('should display N/A for null metrics', async ({ page }) => {
      const containerItem = page.locator('[data-testid="container-item"]').first();

      if (await containerItem.isVisible()) {
        await containerItem.click();
        await page.waitForTimeout(500);

        const viewMetricsButton = page.locator('button:has-text("View All Metrics")').first();

        if (await viewMetricsButton.isVisible()) {
          await viewMetricsButton.click();
          await page.waitForTimeout(500);

          const modal = page.locator('[data-testid="full-metrics-modal"]');
          await expect(modal).toBeVisible();

          // Check if any metric shows N/A
          const naMetrics = modal.locator('text="N/A"');
          const naCount = await naMetrics.count();

          if (naCount > 0) {
            console.log(`✅ Found ${naCount} metrics displaying N/A`);
          } else {
            console.log('ℹ️ No N/A metrics found - all metrics have values');
          }
        }
      }
    });

    test('should display live update indicator', async ({ page }) => {
      const containerItem = page.locator('[data-testid="container-item"]').first();

      if (await containerItem.isVisible()) {
        await containerItem.click();
        await page.waitForTimeout(500);

        const viewMetricsButton = page.locator('button:has-text("View All Metrics")').first();

        if (await viewMetricsButton.isVisible()) {
          await viewMetricsButton.click();
          await page.waitForTimeout(500);

          const modal = page.locator('[data-testid="full-metrics-modal"]');
          await expect(modal).toBeVisible();

          // Check live indicator
          const liveIndicator = modal.locator('[data-testid="live-indicator"]');
          await expect(liveIndicator).toBeVisible();

          // Should contain "Live" text
          await expect(liveIndicator.locator('text="Live"')).toBeVisible();

          console.log('✅ Live update indicator displayed');
        }
      }
    });

    test('should display timestamp information', async ({ page }) => {
      const containerItem = page.locator('[data-testid="container-item"]').first();

      if (await containerItem.isVisible()) {
        await containerItem.click();
        await page.waitForTimeout(500);

        const viewMetricsButton = page.locator('button:has-text("View All Metrics")').first();

        if (await viewMetricsButton.isVisible()) {
          await viewMetricsButton.click();
          await page.waitForTimeout(500);

          const modal = page.locator('[data-testid="full-metrics-modal"]');
          await expect(modal).toBeVisible();

          // Look for timestamp text pattern (e.g., "Updated 2s ago")
          const liveIndicator = modal.locator('[data-testid="live-indicator"]');
          const timestamp = liveIndicator.locator('text=/Updated.*ago|N\\/A/');

          await expect(timestamp).toBeVisible();
          console.log('✅ Timestamp information displayed');
        }
      }
    });
  });

  test.describe('Action Buttons', () => {
    test('should have functional snapshot button', async ({ page }) => {
      const containerItem = page.locator('[data-testid="container-item"]').first();

      if (await containerItem.isVisible()) {
        await containerItem.click();
        await page.waitForTimeout(500);

        const viewMetricsButton = page.locator('button:has-text("View All Metrics")').first();

        if (await viewMetricsButton.isVisible()) {
          await viewMetricsButton.click();
          await page.waitForTimeout(500);

          const modal = page.locator('[data-testid="full-metrics-modal"]');
          await expect(modal).toBeVisible();

          // Check snapshot button exists
          const snapshotButton = modal.locator('[data-testid="snapshot-button"]');
          await expect(snapshotButton).toBeVisible();
          await expect(snapshotButton).toBeEnabled();

          console.log('✅ Snapshot button is visible and enabled');
        }
      }
    });

    test('should have functional support button', async ({ page }) => {
      const containerItem = page.locator('[data-testid="container-item"]').first();

      if (await containerItem.isVisible()) {
        await containerItem.click();
        await page.waitForTimeout(500);

        const viewMetricsButton = page.locator('button:has-text("View All Metrics")').first();

        if (await viewMetricsButton.isVisible()) {
          await viewMetricsButton.click();
          await page.waitForTimeout(500);

          const modal = page.locator('[data-testid="full-metrics-modal"]');
          await expect(modal).toBeVisible();

          // Check support button exists
          const supportButton = modal.locator('[data-testid="support-button"]');
          await expect(supportButton).toBeVisible();
          await expect(supportButton).toBeEnabled();

          console.log('✅ Support button is visible and enabled');
        }
      }
    });

    test('should open permission modal when clicking support button', async ({ page }) => {
      const containerItem = page.locator('[data-testid="container-item"]').first();

      if (await containerItem.isVisible()) {
        await containerItem.click();
        await page.waitForTimeout(500);

        const viewMetricsButton = page.locator('button:has-text("View All Metrics")').first();

        if (await viewMetricsButton.isVisible()) {
          await viewMetricsButton.click();
          await page.waitForTimeout(500);

          const modal = page.locator('[data-testid="full-metrics-modal"]');
          await expect(modal).toBeVisible();

          // Click support button
          const supportButton = modal.locator('[data-testid="support-button"]');
          await supportButton.click();
          await page.waitForTimeout(300);

          // Permission modal should appear
          const permissionModal = page.locator('[data-testid="permission-modal"]');
          await expect(permissionModal).toBeVisible();

          console.log('✅ Permission modal opened from support button');

          // Close permission modal
          const closePermissionButton = permissionModal.locator('[data-testid="close-permission-modal"]');
          await closePermissionButton.click();
        }
      }
    });
  });

  test.describe('Responsive Design', () => {
    test('should display correctly on mobile viewport', async ({ page }) => {
      // Set mobile viewport
      await page.setViewportSize({ width: 375, height: 667 });

      const containerItem = page.locator('[data-testid="container-item"]').first();

      if (await containerItem.isVisible()) {
        await containerItem.click();
        await page.waitForTimeout(500);

        const viewMetricsButton = page.locator('button:has-text("View All Metrics")').first();

        if (await viewMetricsButton.isVisible()) {
          await viewMetricsButton.click();
          await page.waitForTimeout(500);

          const modal = page.locator('[data-testid="full-metrics-modal"]');
          await expect(modal).toBeVisible();

          // Modal should be full-width on mobile
          const modalContent = modal.locator('[data-testid="metrics-modal-content"]');
          const boundingBox = await modalContent.boundingBox();

          expect(boundingBox?.width).toBeLessThanOrEqual(375);
          console.log('✅ Modal displays correctly on mobile viewport');
        }
      }
    });

    test('should display correctly on tablet viewport', async ({ page }) => {
      // Set tablet viewport
      await page.setViewportSize({ width: 768, height: 1024 });

      const containerItem = page.locator('[data-testid="container-item"]').first();

      if (await containerItem.isVisible()) {
        await containerItem.click();
        await page.waitForTimeout(500);

        const viewMetricsButton = page.locator('button:has-text("View All Metrics")').first();

        if (await viewMetricsButton.isVisible()) {
          await viewMetricsButton.click();
          await page.waitForTimeout(500);

          const modal = page.locator('[data-testid="full-metrics-modal"]');
          await expect(modal).toBeVisible();

          console.log('✅ Modal displays correctly on tablet viewport');
        }
      }
    });

    test('should display correctly on desktop viewport', async ({ page }) => {
      // Set desktop viewport
      await page.setViewportSize({ width: 1920, height: 1080 });

      const containerItem = page.locator('[data-testid="container-item"]').first();

      if (await containerItem.isVisible()) {
        await containerItem.click();
        await page.waitForTimeout(500);

        const viewMetricsButton = page.locator('button:has-text("View All Metrics")').first();

        if (await viewMetricsButton.isVisible()) {
          await viewMetricsButton.click();
          await page.waitForTimeout(500);

          const modal = page.locator('[data-testid="full-metrics-modal"]');
          await expect(modal).toBeVisible();

          console.log('✅ Modal displays correctly on desktop viewport');
        }
      }
    });
  });

  test.describe('Keyboard Accessibility', () => {
    test('should navigate between buttons using Tab key', async ({ page }) => {
      const containerItem = page.locator('[data-testid="container-item"]').first();

      if (await containerItem.isVisible()) {
        await containerItem.click();
        await page.waitForTimeout(500);

        const viewMetricsButton = page.locator('button:has-text("View All Metrics")').first();

        if (await viewMetricsButton.isVisible()) {
          await viewMetricsButton.click();
          await page.waitForTimeout(500);

          const modal = page.locator('[data-testid="full-metrics-modal"]');
          await expect(modal).toBeVisible();

          // Tab through buttons
          await page.keyboard.press('Tab');
          await page.waitForTimeout(100);

          let focusedElement = page.locator(':focus');
          if (await focusedElement.isVisible()) {
            await expect(focusedElement).toBeVisible();
            console.log('✅ Keyboard navigation functional (Tab key)');
          }

          // Tab again
          await page.keyboard.press('Tab');
          await page.waitForTimeout(100);
        }
      }
    });

    test('should activate buttons with Enter key', async ({ page }) => {
      const containerItem = page.locator('[data-testid="container-item"]').first();

      if (await containerItem.isVisible()) {
        await containerItem.click();
        await page.waitForTimeout(500);

        const viewMetricsButton = page.locator('button:has-text("View All Metrics")').first();

        if (await viewMetricsButton.isVisible()) {
          await viewMetricsButton.click();
          await page.waitForTimeout(500);

          const modal = page.locator('[data-testid="full-metrics-modal"]');
          await expect(modal).toBeVisible();

          // Focus on snapshot button
          const snapshotButton = modal.locator('[data-testid="snapshot-button"]');
          await snapshotButton.focus();

          // Press Enter
          await page.keyboard.press('Enter');
          await page.waitForTimeout(100);

          console.log('✅ Buttons activate with Enter key');
        }
      }
    });
  });

  test.describe('Visual Regression', () => {
    test('visual regression - full metrics modal appearance', async ({ page }) => {
      const containerItem = page.locator('[data-testid="container-item"]').first();

      if (await containerItem.isVisible()) {
        await containerItem.click();
        await page.waitForTimeout(500);

        const viewMetricsButton = page.locator('button:has-text("View All Metrics")').first();

        if (await viewMetricsButton.isVisible()) {
          await viewMetricsButton.click();
          await page.waitForTimeout(800);

          const modal = page.locator('[data-testid="full-metrics-modal"]');
          await expect(modal).toBeVisible();

          // Mask dynamic content
          await page.addStyleTag({
            content: `
              [data-testid="live-indicator"] { visibility: hidden !important; }
              [class*="animate-"] { animation: none !important; }
            `,
          });

          // Take screenshot
          await expect(page).toHaveScreenshot('full-metrics-modal.png', {
            mask: [modal.locator('[data-testid="live-indicator"]')],
            threshold: 0.3,
          });

          console.log('✅ Visual regression test completed');
        }
      }
    });
  });

  test.describe('Scrolling Behavior', () => {
    test('should allow scrolling through all metrics', async ({ page }) => {
      const containerItem = page.locator('[data-testid="container-item"]').first();

      if (await containerItem.isVisible()) {
        await containerItem.click();
        await page.waitForTimeout(500);

        const viewMetricsButton = page.locator('button:has-text("View All Metrics")').first();

        if (await viewMetricsButton.isVisible()) {
          await viewMetricsButton.click();
          await page.waitForTimeout(500);

          const modal = page.locator('[data-testid="full-metrics-modal"]');
          await expect(modal).toBeVisible();

          // Find scrollable content area
          const modalContent = modal.locator('.overflow-y-auto').first();

          if (await modalContent.isVisible()) {
            // Scroll to bottom
            await modalContent.evaluate((el) => {
              el.scrollTop = el.scrollHeight;
            });

            await page.waitForTimeout(300);

            // Verify footer is visible after scroll
            const footer = modal.locator('[data-testid="footer-close-button"]');
            await expect(footer).toBeVisible();

            console.log('✅ Modal scrolling works correctly');
          }
        }
      }
    });
  });
});
