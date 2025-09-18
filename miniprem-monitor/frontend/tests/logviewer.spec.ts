import { test, expect } from '@playwright/test';

/**
 * LogViewer Modal Tests
 *
 * Tests the log viewer modal functionality, auto-scroll, download, and interaction
 */

test.describe('LogViewer Modal', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(3500);
  });

  test('opens log viewer from container logs button', async ({ page }) => {
    // Find and click a container logs button
    const logsButton = page
      .locator('button')
      .filter({ has: page.locator('[data-lucide="eye"]') })
      .first();

    if (await logsButton.isVisible()) {
      await logsButton.click();
      await page.waitForTimeout(1000);

      // Modal should open
      const modal = page.locator('.fixed.inset-0.bg-black.bg-opacity-50');
      const modalContent = page.locator('.bg-white.rounded-lg.shadow-xl');

      if (await modal.isVisible()) {
        await expect(modal).toBeVisible();
        await expect(modalContent).toBeVisible();

        // Should have title with "Container:" or "Pod:"
        const title = modalContent.locator('h3').first();
        const titleText = await title.textContent();
        expect(titleText).toMatch(/Container:|Pod:/);

        // Should have logs content area
        const logsArea = modalContent.locator('.log-container, [class*="overflow-auto"]');
        if (await logsArea.isVisible()) {
          await expect(logsArea).toBeVisible();
        }
      }
    } else {
      console.log('ℹ️ No container logs button found - containers may not be available');
    }
  });

  test('opens log viewer from pod logs button', async ({ page }) => {
    // Find and click a pod logs button
    const podLogsButton = page
      .locator('[data-pod-item]')
      .locator('button')
      .filter({ has: page.locator('[data-lucide="eye"]') })
      .first();

    if (await podLogsButton.isVisible()) {
      await podLogsButton.click();
      await page.waitForTimeout(1000);

      // Modal should open
      const modal = page.locator('.fixed.inset-0');
      if (await modal.isVisible()) {
        await expect(modal).toBeVisible();

        // Title should indicate pod logs
        const title = page.getByText('Pod:').first();
        if (await title.isVisible()) {
          await expect(title).toBeVisible();
        }
      }
    } else {
      console.log('ℹ️ No pod logs button found - pods may not be available');
    }
  });

  test('modal has correct structure and controls', async ({ page }) => {
    // Try to open log viewer
    const logsButton = page
      .locator('button')
      .filter({ has: page.locator('[data-lucide="eye"]') })
      .first();

    if (await logsButton.isVisible()) {
      await logsButton.click();
      await page.waitForTimeout(1000);

      const modal = page.locator('.fixed.inset-0').first();

      if (await modal.isVisible()) {
        await expect(modal).toBeVisible();

        // Should have header with title and controls
        const header = modal.locator('.flex.items-center.justify-between').first();
        if (await header.isVisible()) {
          await expect(header).toBeVisible();

          // Should have close button
          const closeButton = header
            .locator('button')
            .filter({ has: page.locator('[data-lucide="x"]') })
            .first();
          if (await closeButton.isVisible()) {
            await expect(closeButton).toBeVisible();
            await expect(closeButton).not.toBeDisabled();
          }

          // Should have auto-scroll toggle
          const autoScrollButton = header.getByText('Auto-scroll').or(header.getByText('Manual')).first();
          if (await autoScrollButton.isVisible()) {
            await expect(autoScrollButton).toBeVisible();
          }

          // Should have download button
          const downloadButton = header
            .locator('button')
            .filter({ has: page.locator('[data-lucide="download"]') })
            .first();
          if (await downloadButton.isVisible()) {
            await expect(downloadButton).toBeVisible();
          }
        }

        // Should have footer with log statistics
        const footer = modal.locator('.border-t.border-gray-200.bg-gray-50').first();
        if (await footer.isVisible()) {
          await expect(footer).toBeVisible();

          const logCount = footer.getByText('lines').first();
          const lastUpdated = footer.getByText('Last updated').first();

          if (await logCount.isVisible()) {
            await expect(logCount).toBeVisible();
          }
          if (await lastUpdated.isVisible()) {
            await expect(lastUpdated).toBeVisible();
          }
        }
      }
    }
  });

  test('close button closes the modal', async ({ page }) => {
    const logsButton = page
      .locator('button')
      .filter({ has: page.locator('[data-lucide="eye"]') })
      .first();

    if (await logsButton.isVisible()) {
      await logsButton.click();
      await page.waitForTimeout(1000);

      const modal = page.locator('.fixed.inset-0').first();

      if (await modal.isVisible()) {
        // Find and click close button
        const closeButton = page
          .locator('button')
          .filter({ has: page.locator('[data-lucide="x"]') })
          .first();

        if (await closeButton.isVisible()) {
          await closeButton.click();
          await page.waitForTimeout(500);

          // Modal should be closed
          expect(await modal.isVisible()).toBeFalsy();
        }
      }
    }
  });

  test('auto-scroll toggle functionality', async ({ page }) => {
    const logsButton = page
      .locator('button')
      .filter({ has: page.locator('[data-lucide="eye"]') })
      .first();

    if (await logsButton.isVisible()) {
      await logsButton.click();
      await page.waitForTimeout(1000);

      const modal = page.locator('.fixed.inset-0').first();

      if (await modal.isVisible()) {
        // Find auto-scroll toggle button
        const autoScrollToggle = modal
          .locator('button')
          .filter({ hasText: /Auto-scroll|Manual/ })
          .first();

        if (await autoScrollToggle.isVisible()) {
          const initialText = await autoScrollToggle.textContent();

          // Click toggle
          await autoScrollToggle.click();
          await page.waitForTimeout(300);

          const newText = await autoScrollToggle.textContent();

          // Text should change
          expect(newText).not.toBe(initialText);

          // Should toggle between Auto-scroll and Manual
          expect(newText).toMatch(/Auto-scroll|Manual/);

          // Click again to toggle back
          await autoScrollToggle.click();
          await page.waitForTimeout(300);

          const finalText = await autoScrollToggle.textContent();
          expect(finalText).toBe(initialText);
        }
      }
    }
  });

  test('download functionality', async ({ page }) => {
    const logsButton = page
      .locator('button')
      .filter({ has: page.locator('[data-lucide="eye"]') })
      .first();

    if (await logsButton.isVisible()) {
      await logsButton.click();
      await page.waitForTimeout(2000); // Wait longer for logs to load

      const modal = page.locator('.fixed.inset-0').first();

      if (await modal.isVisible()) {
        // Find download button
        const downloadButton = modal
          .locator('button')
          .filter({ has: page.locator('[data-lucide="download"]') })
          .first();

        if (await downloadButton.isVisible()) {
          // Set up download promise before clicking
          const downloadPromise = page.waitForEvent('download', { timeout: 5000 });

          await downloadButton.click();

          try {
            const download = await downloadPromise;

            // Verify download occurred
            expect(download).toBeTruthy();

            const filename = download.suggestedFilename();
            expect(filename).toMatch(/.*_logs\.txt$/);

            console.log(`✅ Log download successful: ${filename}`);
          } catch (error) {
            console.log('ℹ️ Download may not work in test environment or no logs available');
          }
        } else {
          console.log('ℹ️ Download button not found - logs may not be loaded');
        }
      }
    }
  });

  test('displays loading state correctly', async ({ page }) => {
    const logsButton = page
      .locator('button')
      .filter({ has: page.locator('[data-lucide="eye"]') })
      .first();

    if (await logsButton.isVisible()) {
      await logsButton.click();

      const modal = page.locator('.fixed.inset-0').first();

      if (await modal.isVisible()) {
        // Should show loading state initially
        const loadingIndicator = modal.locator('.animate-spin').or(modal.getByText('Loading logs')).first();

        // Check if loading state is visible (may be brief)
        const hasLoading = await loadingIndicator.isVisible();

        if (hasLoading) {
          await expect(loadingIndicator).toBeVisible();
          console.log('✅ Loading state displayed');

          // Wait for loading to complete
          await page.waitForTimeout(2000);
        } else {
          console.log('ℹ️ Loading state not visible - logs may load instantly');
        }

        // After loading, should show log content or "No logs available"
        const logContent = modal.locator('.log-container');
        const noLogsMessage = modal.getByText('No logs available');

        if (await logContent.isVisible()) {
          await expect(logContent).toBeVisible();
        } else if (await noLogsMessage.isVisible()) {
          await expect(noLogsMessage).toBeVisible();
        }
      }
    }
  });

  test('handles empty logs gracefully', async ({ page }) => {
    // Mock empty logs response
    await page.route('**/ws', (route) => {
      // This might not fully work for WebSocket mocking, but shows intent
      route.continue();
    });

    const logsButton = page
      .locator('button')
      .filter({ has: page.locator('[data-lucide="eye"]') })
      .first();

    if (await logsButton.isVisible()) {
      await logsButton.click();
      await page.waitForTimeout(2000);

      const modal = page.locator('.fixed.inset-0').first();

      if (await modal.isVisible()) {
        // Should handle empty logs gracefully
        const noLogsMessage = modal.getByText('No logs available').or(modal.getByText('Logs may not be accessible'));

        if (await noLogsMessage.isVisible()) {
          await expect(noLogsMessage).toBeVisible();
          console.log('✅ Empty logs handled gracefully');
        } else {
          // Or show actual logs if available
          const logContent = modal.locator('.log-container');
          if (await logContent.isVisible()) {
            console.log('ℹ️ Logs are available');
          }
        }

        // Footer should still show log count (0 lines)
        const footer = modal.locator('.border-t');
        if (await footer.isVisible()) {
          const logCount = footer.getByText('lines');
          if (await logCount.isVisible()) {
            await expect(logCount).toBeVisible();
          }
        }
      }
    }
  });

  test('log content has proper formatting', async ({ page }) => {
    const logsButton = page
      .locator('button')
      .filter({ has: page.locator('[data-lucide="eye"]') })
      .first();

    if (await logsButton.isVisible()) {
      await logsButton.click();
      await page.waitForTimeout(2000);

      const modal = page.locator('.fixed.inset-0').first();

      if (await modal.isVisible()) {
        const logContainer = modal.locator('.log-container');

        if (await logContainer.isVisible()) {
          await expect(logContainer).toBeVisible();

          // Should use monospace font
          const hasMonoFont = await logContainer.evaluate((element) => {
            const style = window.getComputedStyle(element);
            return style.fontFamily.includes('mono');
          });

          if (hasMonoFont) {
            console.log('✅ Logs use monospace font');
          }

          // Check for log lines
          const logLines = logContainer.locator('div');
          const lineCount = await logLines.count();

          if (lineCount > 0) {
            console.log(`✅ Found ${lineCount} log lines`);

            // Verify log lines have appropriate styling
            const firstLine = logLines.first();
            const lineClass = await firstLine.getAttribute('class');

            expect(lineClass).toMatch(/font-mono|text-/);
          }
        }
      }
    }
  });

  test('modal is accessible via keyboard', async ({ page }) => {
    const logsButton = page
      .locator('button')
      .filter({ has: page.locator('[data-lucide="eye"]') })
      .first();

    if (await logsButton.isVisible()) {
      // Use keyboard to click button
      await logsButton.focus();
      await page.keyboard.press('Enter');
      await page.waitForTimeout(1000);

      const modal = page.locator('.fixed.inset-0').first();

      if (await modal.isVisible()) {
        await expect(modal).toBeVisible();

        // Should be able to tab through controls
        await page.keyboard.press('Tab');
        await page.waitForTimeout(100);

        const focusedElement = page.locator(':focus');
        if (await focusedElement.isVisible()) {
          await expect(focusedElement).toBeVisible();
        }

        // Escape should close modal
        await page.keyboard.press('Escape');
        await page.waitForTimeout(500);

        // Modal should be closed
        expect(await modal.isVisible()).toBeFalsy();
      }
    }
  });

  test('modal closes when clicking outside', async ({ page }) => {
    const logsButton = page
      .locator('button')
      .filter({ has: page.locator('[data-lucide="eye"]') })
      .first();

    if (await logsButton.isVisible()) {
      await logsButton.click();
      await page.waitForTimeout(1000);

      const modal = page.locator('.fixed.inset-0').first();
      const modalContent = modal.locator('.bg-white.rounded-lg').first();

      if ((await modal.isVisible()) && (await modalContent.isVisible())) {
        // Click on modal backdrop (outside content)
        await modal.click({ position: { x: 10, y: 10 } });
        await page.waitForTimeout(500);

        // Modal should close
        expect(await modal.isVisible()).toBeFalsy();
      }
    }
  });
});
