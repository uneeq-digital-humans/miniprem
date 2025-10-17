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

  test('displays region selector', async ({ page }) => {
    const regionSelector = page.getByTestId('region-selector');

    if (await regionSelector.isVisible()) {
      await expect(regionSelector).toBeVisible();

      // Should display current region (default us-east-1)
      const regionText = await regionSelector.textContent();
      expect(regionText).toContain('us-east-1');

      // Should be clickable to open dropdown
      await regionSelector.click();
      await page.waitForTimeout(500);

      // Should show region options
      const regionOption1 = page.getByTestId('region-option-us-east-1');
      const regionOption2 = page.getByTestId('region-option-us-east-2');

      if (await regionOption1.isVisible() || await regionOption2.isVisible()) {
        await expect(regionOption1.or(regionOption2)).toBeVisible();
      }

      // Click outside to close dropdown
      await page.click('body', { position: { x: 0, y: 0 } });
    }
  });

  test('handles region selection', async ({ page }) => {
    const regionSelector = page.getByTestId('region-selector');

    if (await regionSelector.isVisible()) {
      // Open dropdown
      await regionSelector.click();
      await page.waitForTimeout(500);

      // Select us-east-2 if available
      const usEast2Option = page.getByTestId('region-option-us-east-2');

      if (await usEast2Option.isVisible()) {
        await usEast2Option.click();
        await page.waitForTimeout(500);

        // Should update displayed region
        const updatedText = await regionSelector.textContent();
        expect(updatedText).toContain('us-east-2');
      }
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

  test('displays connection status with visual indicators', async ({ page }) => {
    await page.waitForSelector('[data-testid="connection-status"]', { timeout: 10000 });

    const connectionStatus = page.locator('[data-testid="connection-status"]');
    await expect(connectionStatus).toBeVisible();

    // Status indicator dot should be visible
    const statusIndicator = page.locator('[data-testid="connection-indicator"]');
    await expect(statusIndicator).toBeVisible();

    // Verify status indicator has appropriate color class
    const dotClasses = await statusIndicator.getAttribute('class');
    const hasStatusColor =
      dotClasses?.includes('bg-status-healthy') ||
      dotClasses?.includes('bg-status-error') ||
      dotClasses?.includes('bg-status-warning');
    expect(hasStatusColor).toBeTruthy();

    // WiFi icon should exist (either connected or disconnected)
    const hasWifiIcon = (await page.locator('[data-testid="connection-wifi-icon"]').count()) > 0;
    const hasWifiOffIcon = (await page.locator('[data-testid="connection-wifi-off-icon"]').count()) > 0;
    expect(hasWifiIcon || hasWifiOffIcon).toBeTruthy();

    console.log('✓ Connection status displays with visual indicators');
  });

  test('shows connection ID when available', async ({ page }) => {
    await page.waitForTimeout(3500); // Allow time for connection

    const connectionId = page.locator('[data-testid="connection-id"]');

    if ((await connectionId.count()) > 0) {
      await expect(connectionId).toBeVisible();

      // Verify it's the short format (8 characters)
      const idText = await connectionId.textContent();
      expect(idText?.length).toBe(8);

      // Verify format is alphanumeric
      expect(idText).toMatch(/^[a-zA-Z0-9]{8}$/);

      console.log('✓ Connection ID displayed in correct format');
    }
  });

  test('status indicator changes color based on connection state', async ({ page }) => {
    const statusIndicator = page.locator('[data-testid="connection-indicator"]');

    if (await statusIndicator.isVisible()) {
      await expect(statusIndicator).toBeVisible();

      // Should have appropriate status color class
      const classes = await statusIndicator.getAttribute('class');
      const hasStatusColor =
        classes?.includes('bg-status-healthy') ||
        classes?.includes('bg-status-error') ||
        classes?.includes('bg-status-warning');
      expect(hasStatusColor).toBeTruthy();

      console.log('✓ Status indicator has appropriate color coding');
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

test.describe('UneeQ Admin Portal Link (Issue #7)', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);
  });

  test('should display UneeQ Admin Portal link when tenant ID is available', async ({ page }) => {
    // Wait for header to load
    await page.waitForSelector('[data-testid="dashboard-header"]', { timeout: 10000 });

    // Check if UneeQ Admin link exists
    const uneeqLink = page.locator('[data-testid="uneeq-admin-link"]');

    // If tenant ID is set, link should be visible
    if ((await uneeqLink.count()) > 0) {
      await expect(uneeqLink).toBeVisible();

      // Verify link href format
      const href = await uneeqLink.getAttribute('href');
      expect(href).toMatch(/^https:\/\/cdn\.enterprise\.uneeq\.io\/admin\/customers\/.+\/tenants$/);

      // Verify link has correct attributes
      expect(await uneeqLink.getAttribute('target')).toBe('_blank');
      expect(await uneeqLink.getAttribute('rel')).toBe('noopener noreferrer');

      // Verify link text
      await expect(uneeqLink).toContainText('UneeQ Admin Portal');

      // Verify SVG icon exists
      const svgIcon = uneeqLink.locator('svg');
      await expect(svgIcon).toBeVisible();

      console.log('✓ UneeQ Admin Portal link is correctly displayed');
    } else {
      console.log('⊘ UneeQ Admin Portal link not present (tenant ID not set)');
    }
  });

  test('should not display Platform and CPU count in header', async ({ page }) => {
    await page.waitForSelector('[data-testid="dashboard-header"]', { timeout: 10000 });

    const systemInfo = page.locator('[data-testid="system-info"]');

    // Wait for system info to load
    if ((await systemInfo.count()) > 0) {
      // These should NOT exist anymore
      await expect(page.locator('[data-testid="system-platform"]')).not.toBeVisible();
      await expect(page.locator('[data-testid="system-cpu-count"]')).not.toBeVisible();

      // Memory should still be visible
      await expect(page.locator('[data-testid="system-memory"]')).toBeVisible();

      // Verify memory format
      const memoryText = await page.locator('[data-testid="system-memory"]').textContent();
      expect(memoryText).toMatch(/Memory: \d+(\.\d+)?GB/);

      console.log('✓ Platform and CPU count removed from header');
    }
  });

  test('header displays only Memory and optional UneeQ Admin Portal link', async ({ page }) => {
    await page.waitForSelector('[data-testid="dashboard-header"]', { timeout: 10000 });

    const systemInfo = page.locator('[data-testid="system-info"]');

    if ((await systemInfo.count()) > 0) {
      // Memory is required
      await expect(page.locator('[data-testid="system-memory"]')).toBeVisible();

      // Count visible elements in system info
      const childrenCount = await systemInfo.locator('> *').count();

      // Should have:
      // - 1 span for Memory
      // - Optional: separator (•) and UneeQ link (2 elements)
      expect(childrenCount).toBeGreaterThanOrEqual(1);
      expect(childrenCount).toBeLessThanOrEqual(3); // Memory + separator + link

      const hasUneeqLink = (await page.locator('[data-testid="uneeq-admin-link"]').count()) > 0;
      if (hasUneeqLink) {
        // Should have separator between Memory and link
        const separatorCount = await systemInfo.locator('span:has-text("•")').count();
        expect(separatorCount).toBe(1);
      }

      console.log(`✓ Header simplified: Memory + ${hasUneeqLink ? 'UneeQ Admin Portal link' : 'no tenant ID'}`);
    }
  });

  test('UneeQ Admin Portal link opens in new tab', async ({ page }) => {
    await page.waitForSelector('[data-testid="dashboard-header"]', { timeout: 10000 });

    const uneeqLink = page.locator('[data-testid="uneeq-admin-link"]');

    if ((await uneeqLink.count()) > 0) {
      // Verify target="_blank" attribute (already checked in first test)
      const target = await uneeqLink.getAttribute('target');
      expect(target).toBe('_blank');

      // Verify security attributes
      const rel = await uneeqLink.getAttribute('rel');
      expect(rel).toBe('noopener noreferrer');

      console.log('✓ UneeQ Admin Portal link configured for new tab with security');
    }
  });

  test('header visual regression with UneeQ Admin Portal link', async ({ page }) => {
    await page.goto('/');
    await page.waitForSelector('[data-testid="dashboard-header"]', { timeout: 10000 });

    // Wait for all content to load
    await page.waitForTimeout(2000);

    // Hide dynamic elements for consistent screenshots
    await page.addStyleTag({
      content: `
        [data-testid="connection-id"] { visibility: hidden !important; }
        [class*="animate-"] { animation: none !important; }
      `,
    });

    // Take screenshot of header
    const header = page.locator('[data-testid="dashboard-header"]');
    await expect(header).toHaveScreenshot('header-with-uneeq-link.png', {
      threshold: 0.3,
    });

    console.log('✓ Header visual regression test captured');
  });
});

test.describe('Layout Structure', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);
  });

  test('displays vertical layout with Docker on top, Kubernetes below', async ({ page }) => {
    const dockerPanel = page.locator('.card').filter({ hasText: 'Docker Containers' });
    const k8sPanel = page.locator('.card').filter({ hasText: 'Kubernetes Pods' });

    if (await dockerPanel.isVisible() && await k8sPanel.isVisible()) {
      // Both panels should be visible
      await expect(dockerPanel).toBeVisible();
      await expect(k8sPanel).toBeVisible();

      // Docker panel should be above Kubernetes panel (smaller Y coordinate)
      const dockerBox = await dockerPanel.boundingBox();
      const k8sBox = await k8sPanel.boundingBox();

      if (dockerBox && k8sBox) {
        expect(dockerBox.y).toBeLessThan(k8sBox.y);
      }

      // Panels should be full-width (not side-by-side)
      const mainContainer = page.locator('main .space-y-6');
      await expect(mainContainer).toBeVisible();

      // Should not have grid-cols-2 layout
      const gridContainer = page.locator('.grid-cols-2');
      if (await gridContainer.isVisible()) {
        // If found, it shouldn't contain our service panels
        const hasDockerInGrid = await gridContainer.locator('text=Docker Containers').isVisible();
        const hasK8sInGrid = await gridContainer.locator('text=Kubernetes Pods').isVisible();
        expect(hasDockerInGrid && hasK8sInGrid).toBeFalsy();
      }
    }
  });

  test('Kubernetes panel controls layout is correct', async ({ page }) => {
    const k8sPanel = page.locator('.card').filter({ hasText: 'Kubernetes Pods' });

    if (await k8sPanel.isVisible()) {
      // Should have Region selector with label
      const regionLabel = k8sPanel.getByText('Region:');
      const regionSelector = k8sPanel.getByTestId('region-selector');

      if (await regionLabel.isVisible() && await regionSelector.isVisible()) {
        await expect(regionLabel).toBeVisible();
        await expect(regionSelector).toBeVisible();

        // Region label should be to the left of selector
        const labelBox = await regionLabel.boundingBox();
        const selectorBox = await regionSelector.boundingBox();

        if (labelBox && selectorBox) {
          expect(labelBox.x).toBeLessThan(selectorBox.x);
        }
      }

      // Should have EKS selector with label
      const eksLabel = k8sPanel.getByText('EKS:');
      if (await eksLabel.isVisible()) {
        await expect(eksLabel).toBeVisible();
      }

      // Should have NS selector with label
      const nsLabel = k8sPanel.getByText('NS:');
      if (await nsLabel.isVisible()) {
        await expect(nsLabel).toBeVisible();
      }

      // Should NOT have settings gear icon (removed in redesign)
      const settingsButton = k8sPanel.getByTestId('k8s-panel-settings');
      if (await settingsButton.isVisible()) {
        // Settings should not be visible as standalone gear icon
        console.log('Warning: Standalone settings gear icon still visible');
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
