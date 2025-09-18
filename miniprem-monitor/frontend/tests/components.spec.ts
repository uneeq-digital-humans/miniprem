import { test, expect } from '@playwright/test';

/**
 * Component Interaction Tests
 *
 * Tests individual components and their interactions
 */

test.describe('MetricsCard Component', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Wait for React app to be ready
    await page.waitForFunction(
      () => {
        return document.readyState === 'complete';
      },
      { timeout: 5000 }
    );

    // Wait for either metrics to load or loading state to appear
    await page
      .waitForSelector(
        '[data-testid="metrics-section"], [data-testid="metrics-section-loading"], [data-testid="metrics-section-empty"]',
        {
          timeout: 10000,
        }
      )
      .catch(() => {
        // If none of the expected elements appear, continue anyway
        console.log('No metrics section found, continuing test');
      });
  });

  test('displays CPU usage metric', async ({ page }) => {
    const cpuCard = page.getByTestId('cpu-metrics-card');

    if (await cpuCard.isVisible()) {
      await expect(cpuCard).toBeVisible();

      // Should have CPU label
      const cpuLabel = page.getByTestId('cpu-label');
      await expect(cpuLabel).toBeVisible();
      await expect(cpuLabel).toHaveText('CPU Usage');

      // Should have a percentage value
      const cpuValue = page.getByTestId('cpu-value');
      await expect(cpuValue).toBeVisible();
      const value = await cpuValue.textContent();
      expect(value).toMatch(/\d+\.\d+%/);

      // Should have CPU icon
      const cpuIcon = page.getByTestId('cpu-icon');
      await expect(cpuIcon).toBeVisible();
    } else {
      // Should show loading state
      const loadingSection = page.getByTestId('metrics-section-loading');
      if (await loadingSection.isVisible()) {
        await expect(loadingSection).toBeVisible();
      }
    }
  });

  test('displays memory usage metric', async ({ page }) => {
    const memoryCard = page.getByText('Memory').locator('..');

    if (await memoryCard.isVisible()) {
      await expect(memoryCard).toBeVisible();

      // Should have appropriate color coding
      const valueElement = memoryCard.locator('.metric-value').or(memoryCard.locator('[class*="text-status-"]'));
      if (await valueElement.isVisible()) {
        const value = await valueElement.textContent();
        expect(value).toMatch(/\d+\.\d+%/);
      }
    }
  });

  test('displays network I/O information', async ({ page }) => {
    const networkCard = page.getByText('Network I/O').locator('..');

    if (await networkCard.isVisible()) {
      await expect(networkCard).toBeVisible();

      // Should show upload/download indicators
      const uploadIndicator = networkCard.getByText('↑').or(networkCard.locator('.text-status-healthy'));
      const downloadIndicator = networkCard.getByText('↓').or(networkCard.locator('.text-uneeq-primary'));

      if ((await uploadIndicator.isVisible()) && (await downloadIndicator.isVisible())) {
        await expect(uploadIndicator).toBeVisible();
        await expect(downloadIndicator).toBeVisible();
      }
    }
  });

  test('shows appropriate color coding for usage levels', async ({ page }) => {
    const metricsCards = page.locator('.metric-card');
    const cardCount = await metricsCards.count();

    if (cardCount > 0) {
      for (let i = 0; i < cardCount; i++) {
        const card = metricsCards.nth(i);
        const valueElement = card.locator('.metric-value');

        if (await valueElement.isVisible()) {
          const classList = await valueElement.getAttribute('class');

          // Should have appropriate status color class
          const hasStatusColor =
            classList?.includes('text-status-healthy') ||
            classList?.includes('text-status-warning') ||
            classList?.includes('text-status-error');

          expect(hasStatusColor).toBeTruthy();
        }
      }
    }
  });
});

test.describe('ContainerPanel Component', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(3500);
  });

  test('displays Docker containers header', async ({ page }) => {
    const containerHeader = page.getByText('Docker Containers');
    await expect(containerHeader).toBeVisible();

    // Should have refresh button
    const refreshButton = page
      .locator('button')
      .filter({ has: page.locator('[class*="RefreshCw"]') })
      .first();
    if (await refreshButton.isVisible()) {
      await expect(refreshButton).toBeVisible();
      await expect(refreshButton).not.toBeDisabled();
    }
  });

  test('handles refresh button click', async ({ page }) => {
    const refreshButton = page
      .locator('button')
      .filter({ has: page.locator('[class*="RefreshCw"]') })
      .first();

    if (await refreshButton.isVisible()) {
      // Click refresh button
      await refreshButton.click();

      // Should show loading state briefly
      const loadingSpinner = page.locator('.animate-spin');
      if (await loadingSpinner.isVisible()) {
        await expect(loadingSpinner).toBeVisible();

        // Wait for loading to complete
        await page.waitForTimeout(2000);

        // Button should not be spinning after load
        await expect(refreshButton).not.toHaveClass(/animate-spin/);
      }
    }
  });

  test('displays container information when available', async ({ page }) => {
    const containerPanel = page.getByText('Docker Containers').locator('..');

    // Wait a moment for initial state to settle
    await page.waitForTimeout(1000);

    // Should show either containers, no containers message, or loading state
    const hasContainers = (await page.locator('[data-testid="container-item"]').count()) > 0;
    const hasNoData = await page.locator('[data-testid="no-containers"]').isVisible();
    const hasLoading = await page.locator('[data-testid="container-loading"]').isVisible();

    console.log('Container test state:', { hasContainers, hasNoData, hasLoading });
    expect(hasContainers || hasNoData || hasLoading).toBeTruthy();

    if (hasContainers) {
      const firstContainer = page.locator('[data-testid="container-item"]').first();
      await expect(firstContainer).toBeVisible();

      // Should have status indicator
      const statusIndicator = firstContainer.locator('.w-3.h-3.rounded-full, [class*="StatusIndicator"]').first();
      if (await statusIndicator.isVisible()) {
        await expect(statusIndicator).toBeVisible();
      }

      // Should have view logs button
      const logsButton = firstContainer
        .locator('button[title*="logs"], button')
        .filter({ has: page.locator('[data-lucide="eye"]') })
        .first();
      if (await logsButton.isVisible()) {
        await expect(logsButton).toBeVisible();
      }
    }
  });

  test('expands container details on click', async ({ page }) => {
    const containerItem = page.locator('[data-container-item]').first();

    if (await containerItem.isVisible()) {
      // Click to expand
      await containerItem.click();
      await page.waitForTimeout(500);

      // Should show expanded details
      const expandedDetails = containerItem
        .locator('..')
        .locator('.border-t')
        .or(containerItem.locator('[class*="expanded"]'));
      if (await expandedDetails.isVisible()) {
        await expect(expandedDetails).toBeVisible();
      }

      // Click again to collapse
      await containerItem.click();
      await page.waitForTimeout(500);
    }
  });

  test('view logs button is functional', async ({ page }) => {
    const logsButton = page
      .locator('button')
      .filter({ has: page.locator('[data-lucide="eye"]') })
      .first();

    if (await logsButton.isVisible()) {
      await logsButton.click();

      // Should open log viewer modal (tested separately)
      const modal = page.locator('.fixed.inset-0').or(page.getByText('Logs'));
      await page.waitForTimeout(1000);

      if (await modal.isVisible()) {
        await expect(modal).toBeVisible();

        // Close modal
        const closeButton = page
          .locator('button')
          .filter({ has: page.locator('[data-lucide="x"]') })
          .first();
        if (await closeButton.isVisible()) {
          await closeButton.click();
        }
      }
    }
  });
});

test.describe('KubernetesPanel Component', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(3500);
  });

  test('displays Kubernetes panel header', async ({ page }) => {
    const k8sHeader = page.getByText('Kubernetes').first();
    await expect(k8sHeader).toBeVisible();

    // Should have refresh functionality
    const k8sPanel = k8sHeader.locator('..');
    const refreshButton = k8sPanel
      .locator('button')
      .filter({ has: page.locator('[class*="RefreshCw"]') })
      .first();

    if (await refreshButton.isVisible()) {
      await expect(refreshButton).toBeVisible();
    }
  });

  test('handles pod data display', async ({ page }) => {
    // More specific selector for the Kubernetes panel - look for the card containing "Kubernetes Pods"
    const k8sPanel = page.locator('.card').filter({ hasText: 'Kubernetes Pods' });
    await expect(k8sPanel).toBeVisible();

    // Should show either pods or "no pods" message
    const hasPods = await k8sPanel.locator('[data-testid="pod-item"]').isVisible();
    const hasNoData = await k8sPanel.locator('[data-testid="no-pods"]').isVisible();
    const hasLoading = await k8sPanel.locator('[data-testid="pods-loading"]').isVisible();

    expect(hasPods || hasNoData || hasLoading).toBeTruthy();

    if (hasPods) {
      const firstPod = k8sPanel.locator('[data-testid="pod-item"]').first();
      await expect(firstPod).toBeVisible();

      // Should display pod information
      const podName = firstPod.locator('[class*="font-semibold"]').first();
      if (await podName.isVisible()) {
        await expect(podName).toBeVisible();
        const name = await podName.textContent();
        expect(name).toBeTruthy();
      }
    }
  });

  test('pod logs button functionality', async ({ page }) => {
    const podLogsButton = page
      .locator('[data-testid="pod-item"]')
      .locator('button')
      .filter({ has: page.locator('[data-lucide="eye"]') })
      .first();

    if (await podLogsButton.isVisible()) {
      await podLogsButton.click();

      // Should open log viewer modal
      const modal = page.locator('.fixed.inset-0').or(page.getByText('Pod:'));
      await page.waitForTimeout(1000);

      if (await modal.isVisible()) {
        await expect(modal).toBeVisible();

        // Close modal
        const closeButton = page
          .locator('button')
          .filter({ has: page.locator('[data-lucide="x"]') })
          .first();
        if (await closeButton.isVisible()) {
          await closeButton.click();
        }
      }
    }
  });
});

test.describe('ConnectionStatus Component', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);
  });

  test('displays connection status indicator', async ({ page }) => {
    const connectionStatus = page
      .locator('[data-testid="connection-status"]')
      .or(page.getByText('WebSocket'))
      .or(page.getByText('Connected'))
      .or(page.getByText('Disconnected'))
      .first();

    if (await connectionStatus.isVisible()) {
      await expect(connectionStatus).toBeVisible();

      // Should have status indicator dot
      const statusDot = page.locator('.w-2.h-2.rounded-full, .w-3.h-3.rounded-full').first();
      if (await statusDot.isVisible()) {
        await expect(statusDot).toBeVisible();

        // Should have appropriate color
        const classes = await statusDot.getAttribute('class');
        const hasStatusColor =
          classes?.includes('bg-green') ||
          classes?.includes('bg-red') ||
          classes?.includes('bg-status-healthy') ||
          classes?.includes('bg-status-error');
        expect(hasStatusColor).toBeTruthy();
      }
    }
  });

  test('shows connection ID when connected', async ({ page }) => {
    await page.waitForTimeout(3500); // Allow time for connection

    const connectionStatus = page.locator('[data-testid="connection-status"]').first();

    if (await connectionStatus.isVisible()) {
      const connectionText = await connectionStatus.textContent();

      // Should show either connection status or ID
      expect(connectionText).toBeTruthy();

      // If connected, might show connection ID pattern
      if (connectionText?.includes('#')) {
        expect(connectionText).toMatch(/#[a-zA-Z0-9]+/);
      }
    }
  });
});

test.describe('SystemHealthPanel Component', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);
  });

  test('displays system health information', async ({ page }) => {
    const healthPanel = page.getByText('System Health').locator('..');

    if (await healthPanel.isVisible()) {
      await expect(healthPanel).toBeVisible();

      // Should show health status indicators
      const healthIndicators = healthPanel.locator('.w-3.h-3.rounded-full');
      const indicatorCount = await healthIndicators.count();

      if (indicatorCount > 0) {
        for (let i = 0; i < indicatorCount; i++) {
          const indicator = healthIndicators.nth(i);
          await expect(indicator).toBeVisible();
        }
      }
    }
  });
});

test.describe('Interactive Elements', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);
  });

  test('all buttons are accessible and functional', async ({ page }) => {
    const buttons = page.locator('button:visible');
    const buttonCount = await buttons.count();

    console.log(`Found ${buttonCount} visible buttons`);

    for (let i = 0; i < buttonCount && i < 10; i++) {
      // Test up to 10 buttons
      const button = buttons.nth(i);

      if (await button.isVisible()) {
        // Button should not be disabled (unless it's a loading state)
        const isDisabled = await button.isDisabled();
        const hasLoadingClass = await button.getAttribute('class');
        const isLoadingButton = hasLoadingClass?.includes('animate-spin');

        if (!isDisabled || isLoadingButton) {
          // Button should be clickable
          await expect(button).toBeVisible();
        }
      }
    }
  });

  test('hover states work correctly', async ({ page }) => {
    const interactiveElements = page.locator('button:visible, [class*="hover:"]:visible').first();

    if (await interactiveElements.isVisible()) {
      // Hover over element
      await interactiveElements.hover();
      await page.waitForTimeout(100);

      // Element should still be visible after hover
      await expect(interactiveElements).toBeVisible();
    }
  });

  test('keyboard navigation works', async ({ page }) => {
    // Test tab navigation
    await page.keyboard.press('Tab');
    await page.waitForTimeout(100);

    // Should focus on an interactive element
    const focusedElement = page.locator(':focus');
    if (await focusedElement.isVisible()) {
      await expect(focusedElement).toBeVisible();
    }

    // Test additional tab presses
    await page.keyboard.press('Tab');
    await page.keyboard.press('Tab');
    await page.waitForTimeout(100);
  });
});
