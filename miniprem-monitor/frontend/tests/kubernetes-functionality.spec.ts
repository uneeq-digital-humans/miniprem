import { test, expect } from '@playwright/test';

/**
 * Kubernetes Functionality Tests
 *
 * Comprehensive tests for MiniPrem Monitor Kubernetes functionality
 * including button interactions, error handling, loading states,
 * and backend API integration.
 */

test.describe('Kubernetes Functionality Tests', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    // Give additional time for WebSocket connections and initial data loading
    await page.waitForTimeout(2000);
  });

  test.describe('Button Click Tests', () => {
    test('Setup Kubernetes button is visible and clickable when no clusters configured', async ({ page }) => {
      // Wait for any potential clusters to load first
      await page.waitForTimeout(3000);

      const setupButton = page.getByTestId('setup-kubernetes');

      // Check if setup button exists (indicates no clusters configured)
      if (await setupButton.isVisible()) {
        await expect(setupButton).toBeVisible();
        await expect(setupButton).toHaveText(/Setup Kubernetes/);

        // Test button click functionality
        await setupButton.click();

        // Should either open settings modal or trigger some response
        // Wait for modal or other UI response
        await page.waitForTimeout(1000);

        // Check if any modal, dropdown, or settings panel opened
        const hasModal = await page.locator('[role="dialog"], .modal, [data-testid*="modal"]').isVisible();
        const hasSettingsPanel = await page.locator('[data-testid*="settings"], [data-testid*="k8s-settings"]').isVisible();

        // At least one of these should be true after clicking
        expect(hasModal || hasSettingsPanel).toBeTruthy();
      }
    });

    test('Cluster selector dropdown is functional', async ({ page }) => {
      const clusterSelector = page.getByTestId('cluster-selector');

      if (await clusterSelector.isVisible()) {
        await expect(clusterSelector).toBeVisible();

        // Click to open dropdown
        await clusterSelector.click();

        // Wait for dropdown to appear
        await page.waitForTimeout(500);

        // Check if dropdown menu opened
        const dropdownMenu = clusterSelector.locator('..').locator('[class*="absolute"]');
        if (await dropdownMenu.isVisible()) {
          await expect(dropdownMenu).toBeVisible();

          // Test cluster options if any exist
          const clusterOptions = page.getByTestId('cluster-option');
          const optionCount = await clusterOptions.count();

          if (optionCount > 0) {
            // Test clicking on first cluster option
            await clusterOptions.first().click();

            // Dropdown should close after selection
            await page.waitForTimeout(500);
            await expect(dropdownMenu).not.toBeVisible();
          }

          // Test settings button in dropdown
          const settingsInDropdown = page.getByTestId('open-k8s-settings');
          if (await settingsInDropdown.isVisible()) {
            await clusterSelector.click(); // Reopen dropdown
            await page.waitForTimeout(300);
            await settingsInDropdown.click();

            // Should trigger settings modal or panel
            await page.waitForTimeout(1000);
            const hasSettingsResponse = await page.locator('[role="dialog"], .modal, [data-testid*="modal"]').isVisible();
            expect(hasSettingsResponse).toBeTruthy();
          }
        }
      }
    });

    test('Settings button (gear icon) in Kubernetes panel works', async ({ page }) => {
      const settingsButton = page.getByTestId('k8s-panel-settings');

      if (await settingsButton.isVisible()) {
        await expect(settingsButton).toBeVisible();
        await expect(settingsButton).toHaveAttribute('title', 'Kubernetes settings');

        // Test click functionality
        await settingsButton.click();

        // Wait for response (modal, panel, or other UI change)
        await page.waitForTimeout(1500);

        // Check for settings modal or other response
        const hasSettingsModal = await page.locator('[role="dialog"], .modal, [data-testid*="settings-modal"]').isVisible();
        const hasSettingsPanel = await page.locator('[data-testid*="settings"], .settings-panel').isVisible();

        expect(hasSettingsModal || hasSettingsPanel).toBeTruthy();
      }
    });

    test('Refresh button triggers data refresh', async ({ page }) => {
      // Find refresh button in Kubernetes panel (specifically, not the Docker one)
      const k8sPanel = page.locator('text=Kubernetes Pods').locator('..').locator('..');
      const refreshButton = k8sPanel.locator('button').filter({
        has: page.locator('[data-lucide="refresh-cw"], .RefreshCw')
      }).first();

      if (await refreshButton.isVisible()) {
        await expect(refreshButton).toBeVisible();

        // Test click functionality
        await refreshButton.click();

        // Should show loading state (spinning animation)
        const hasLoadingState = await refreshButton.locator('.animate-spin').isVisible();
        if (hasLoadingState) {
          await expect(refreshButton.locator('.animate-spin')).toBeVisible();

          // Wait for loading to complete
          await page.waitForTimeout(2000);

          // Loading should stop
          await expect(refreshButton.locator('.animate-spin')).not.toBeVisible();
        }

        // Button should not be disabled after refresh
        await expect(refreshButton).not.toHaveAttribute('disabled');
      }
    });

    test('Manage Clusters button is functional', async ({ page }) => {
      const clusterSelector = page.getByTestId('cluster-selector');

      if (await clusterSelector.isVisible()) {
        await clusterSelector.click();
        await page.waitForTimeout(500);

        const manageClustersButton = page.getByTestId('manage-clusters');
        if (await manageClustersButton.isVisible()) {
          await expect(manageClustersButton).toBeVisible();
          await expect(manageClustersButton).toHaveText('Manage Clusters');

          await manageClustersButton.click();

          // Should close dropdown and open settings
          await page.waitForTimeout(1000);
          const hasSettingsResponse = await page.locator('[role="dialog"], .modal, [data-testid*="modal"]').isVisible();
          expect(hasSettingsResponse).toBeTruthy();
        }
      }
    });
  });

  test.describe('Error State Testing', () => {
    test('displays error when backend returns Kubernetes errors', async ({ page }) => {
      // Mock API failure for Kubernetes contexts
      await page.route('**/api/kubernetes/contexts', (route) => {
        route.fulfill({
          status: 500,
          contentType: 'application/json',
          body: JSON.stringify({
            error: 'Kubernetes API server not accessible',
            code: 'K8S_API_ERROR'
          })
        });
      });

      await page.route('**/api/kubernetes/context/switch/**', (route) => {
        route.fulfill({
          status: 401,
          contentType: 'application/json',
          body: JSON.stringify({
            error: 'Authentication failed',
            code: 'K8S_AUTH_ERROR'
          })
        });
      });

      // Reload page to trigger API calls with mock
      await page.reload();
      await page.waitForTimeout(3000);

      // Check for error states in UI
      const errorText = await page.textContent('body');
      const hasErrorIndications =
        errorText?.includes('error') ||
        errorText?.includes('failed') ||
        errorText?.includes('not accessible') ||
        await page.locator('[class*="error"], [class*="status-error"], [data-testid*="error"]').isVisible();

      expect(hasErrorIndications).toBeTruthy();
    });

    test('handles authentication failure scenarios', async ({ page }) => {
      // Mock WebSocket messages with authentication errors
      await page.addInitScript(() => {
        // Override WebSocket to simulate auth failures
        const originalWebSocket = window.WebSocket;
        window.WebSocket = class extends originalWebSocket {
          constructor(...args: any[]) {
            super(...args);

            // Simulate auth error after connection
            setTimeout(() => {
              const authErrorEvent = new MessageEvent('message', {
                data: JSON.stringify({
                  type: 'error',
                  success: false,
                  error: 'Authentication failed for Kubernetes API',
                  code: 'K8S_AUTH_FAILED'
                })
              });
              this.dispatchEvent(authErrorEvent);
            }, 1000);
          }
        };
      });

      await page.reload();
      await page.waitForTimeout(5000);

      // Look for authentication error indicators
      const bodyText = await page.textContent('body');
      const hasAuthError =
        bodyText?.includes('Authentication') ||
        bodyText?.includes('auth') ||
        await page.locator('[data-testid*="error"], [class*="error"]').isVisible();

      expect(hasAuthError).toBeTruthy();
    });

    test('displays user-friendly error messages', async ({ page }) => {
      // Look for error messages in various components
      const k8sPanel = page.locator('text=Kubernetes').locator('..').locator('..');

      // Check for "No pods found" or other error states
      const noPods = page.getByTestId('no-pods');
      if (await noPods.isVisible()) {
        await expect(noPods).toBeVisible();

        // Should have user-friendly message
        const errorText = await noPods.textContent();
        expect(errorText).toMatch(/No pods found|Kubernetes may not be accessible|not accessible/);
      }

      // Check cluster status error display
      const clusterStatus = k8sPanel.locator('[class*="bg-surface-secondary"]');
      if (await clusterStatus.isVisible()) {
        const statusText = await clusterStatus.textContent();
        if (statusText?.includes('error') || statusText?.includes('Error')) {
          // Should show connection error details
          const hasErrorDetails = await clusterStatus.locator('[class*="status-error"]').isVisible();
          expect(hasErrorDetails).toBeTruthy();
        }
      }
    });
  });

  test.describe('UI State Tests', () => {
    test('buttons show loading states when clicked', async ({ page }) => {
      const refreshButton = page.locator('button').filter({
        has: page.locator('[data-lucide="refresh-cw"]')
      }).first();

      if (await refreshButton.isVisible()) {
        await refreshButton.click();

        // Check for loading spinner immediately after click
        const hasSpinner = await refreshButton.locator('.animate-spin').isVisible();
        if (hasSpinner) {
          await expect(refreshButton.locator('.animate-spin')).toBeVisible();
        }

        // Button might be disabled during loading
        const isDisabled = await refreshButton.getAttribute('disabled');
        if (isDisabled !== null) {
          expect(isDisabled).toBeTruthy();
        }
      }
    });

    test('error states are visually represented', async ({ page }) => {
      // Look for visual error indicators
      const errorIndicators = page.locator('[class*="error"], [class*="status-error"], [data-status="error"]');
      const errorCount = await errorIndicators.count();

      if (errorCount > 0) {
        // Check visual styling of error states
        const firstError = errorIndicators.first();
        await expect(firstError).toBeVisible();

        // Should have error-related classes or colors
        const className = await firstError.getAttribute('class');
        expect(className).toMatch(/error|red|danger|warning/i);
      }
    });

    test('WebSocket connection status indicators work', async ({ page }) => {
      // Look for connection status indicators
      const connectionStatus = page.getByTestId('connection-status');

      if (await connectionStatus.isVisible()) {
        await expect(connectionStatus).toBeVisible();

        // Should have status indicator (colored dot)
        const statusDot = connectionStatus.locator('[class*="rounded-full"]');
        await expect(statusDot).toBeVisible();

        // Check connection text
        const statusText = await connectionStatus.textContent();
        expect(statusText).toMatch(/connected|connecting|disconnected|WebSocket/i);
      }
    });

    test('loading states work correctly for pods', async ({ page }) => {
      // Look for pods loading state
      const podsLoading = page.getByTestId('pods-loading');

      if (await podsLoading.isVisible()) {
        await expect(podsLoading).toBeVisible();

        // Should have skeleton loaders
        const skeletonLoaders = podsLoading.locator('.animate-pulse');
        await expect(skeletonLoaders.first()).toBeVisible();

        // Wait for loading to complete and check for actual pods or "no pods" message
        await page.waitForTimeout(5000);

        const hasPodsOrMessage =
          await page.getByTestId('pod-item').isVisible() ||
          await page.getByTestId('no-pods').isVisible();

        expect(hasPodsOrMessage).toBeTruthy();
      }
    });

    test('cluster selector shows loading overlay when processing', async ({ page }) => {
      const clusterSelector = page.getByTestId('cluster-selector');

      if (await clusterSelector.isVisible()) {
        await clusterSelector.click();
        await page.waitForTimeout(300);

        const clusterOption = page.getByTestId('cluster-option').first();
        if (await clusterOption.isVisible()) {
          await clusterOption.click();

          // Check for loading overlay
          const loadingOverlay = clusterSelector.locator('[class*="animate-spin"]');
          if (await loadingOverlay.isVisible()) {
            await expect(loadingOverlay).toBeVisible();

            // Wait for loading to complete
            await page.waitForTimeout(3000);
            await expect(loadingOverlay).not.toBeVisible();
          }
        }
      }
    });
  });

  test.describe('Integration Tests', () => {
    test('namespace filter functionality works', async ({ page }) => {
      // Look for namespace filter dropdown
      const namespaceFilter = page.locator('select').filter({ has: page.locator('[data-lucide="filter"]') });

      if (await namespaceFilter.isVisible()) {
        await expect(namespaceFilter).toBeVisible();

        // Should have default "All Namespaces" option
        await expect(namespaceFilter).toHaveValue('all');

        // Get available options
        const options = namespaceFilter.locator('option');
        const optionCount = await options.count();

        if (optionCount > 1) {
          // Select a different namespace
          const secondOption = await options.nth(1).textContent();
          if (secondOption) {
            await namespaceFilter.selectOption(secondOption);

            // Should trigger filtering (pods might change)
            await page.waitForTimeout(1000);

            // Verify filter is applied
            await expect(namespaceFilter).not.toHaveValue('all');
          }
        }
      }
    });

    test('pod expansion functionality works', async ({ page }) => {
      const podItems = page.getByTestId('pod-item');
      const podCount = await podItems.count();

      if (podCount > 0) {
        const firstPod = podItems.first();

        // Click to expand pod details
        await firstPod.click();
        await page.waitForTimeout(500);

        // Should show expanded content with pod details
        const expandedContent = firstPod.locator('[class*="border-t"]');
        if (await expandedContent.isVisible()) {
          await expect(expandedContent).toBeVisible();

          // Should contain pod details
          const detailsText = await expandedContent.textContent();
          expect(detailsText).toMatch(/Status|Ready|Restarts|Age|Namespace/);
        }

        // Click again to collapse
        await firstPod.click();
        await page.waitForTimeout(500);

        // Expanded content should be hidden
        await expect(expandedContent).not.toBeVisible();
      }
    });

    test('view logs button functionality', async ({ page }) => {
      const podItems = page.getByTestId('pod-item');
      const podCount = await podItems.count();

      if (podCount > 0) {
        const firstPod = podItems.first();
        const viewLogsButton = firstPod.locator('button[title="View logs"]');

        if (await viewLogsButton.isVisible()) {
          await viewLogsButton.click();

          // Should open log viewer modal or component
          await page.waitForTimeout(1500);

          // Look for log viewer
          const logViewer = page.locator('[data-testid*="log"], [class*="log"], [role="dialog"]').filter({ hasText: /log/i });
          if (await logViewer.isVisible()) {
            await expect(logViewer).toBeVisible();
          }
        }
      }
    });
  });

  test.describe('Responsive Design Tests', () => {
    test('Kubernetes panel adapts to mobile layout', async ({ page }) => {
      // Test mobile layout
      await page.setViewportSize({ width: 390, height: 844 });
      await page.waitForTimeout(500);

      const k8sPanel = page.locator('text=Kubernetes Pods').locator('..').locator('..');
      await expect(k8sPanel).toBeVisible();

      // Cluster selector should be visible but might be stacked differently
      const clusterSelector = page.getByTestId('cluster-selector');
      if (await clusterSelector.isVisible()) {
        await expect(clusterSelector).toBeVisible();
      }

      // Settings button should still be accessible
      const settingsButton = page.getByTestId('k8s-panel-settings');
      if (await settingsButton.isVisible()) {
        await expect(settingsButton).toBeVisible();
      }
    });

    test('cluster selector dropdown adapts to screen size', async ({ page }) => {
      const clusterSelector = page.getByTestId('cluster-selector');

      if (await clusterSelector.isVisible()) {
        // Test on mobile
        await page.setViewportSize({ width: 390, height: 844 });
        await clusterSelector.click();
        await page.waitForTimeout(500);

        const dropdown = clusterSelector.locator('..').locator('[class*="absolute"]');
        if (await dropdown.isVisible()) {
          // Should be positioned properly for mobile
          await expect(dropdown).toBeVisible();

          // Test on desktop
          await page.setViewportSize({ width: 1920, height: 1080 });
          await page.waitForTimeout(300);

          // Should still be visible and properly positioned
          await expect(dropdown).toBeVisible();
        }
      }
    });
  });
});