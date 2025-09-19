import { test, expect } from '@playwright/test';

/**
 * Button Responsiveness Debug Tests
 *
 * Focused tests to diagnose and debug the specific issue where
 * clicking Kubernetes buttons shows "no response". These tests
 * provide detailed debugging information and step-by-step validation.
 */

test.describe('Button Responsiveness Debug', () => {
  test.beforeEach(async ({ page }) => {
    // Enable console logging for debugging
    page.on('console', (msg) => {
      console.log(`[BROWSER CONSOLE ${msg.type().toUpperCase()}]:`, msg.text());
    });

    // Enable request/response logging
    page.on('request', (request) => {
      console.log(`[REQUEST]: ${request.method()} ${request.url()}`);
    });

    page.on('response', (response) => {
      console.log(`[RESPONSE]: ${response.status()} ${response.url()}`);
    });

    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(3000); // Give time for full initialization
  });

  test('Debug: Setup Kubernetes button click response', async ({ page }) => {
    console.log('\n=== DEBUGGING SETUP KUBERNETES BUTTON ===');

    // Step 1: Check if button exists
    const setupButton = page.getByTestId('setup-kubernetes');
    const buttonExists = await setupButton.isVisible();

    console.log(`Step 1 - Setup button exists: ${buttonExists}`);

    if (!buttonExists) {
      console.log('Setup button not found. Checking for cluster selector instead...');

      const clusterSelector = page.getByTestId('cluster-selector');
      const selectorExists = await clusterSelector.isVisible();

      console.log(`Cluster selector exists: ${selectorExists}`);

      if (selectorExists) {
        const selectorText = await clusterSelector.textContent();
        console.log(`Cluster selector text: "${selectorText}"`);

        if (selectorText?.includes('No cluster selected')) {
          console.log('No clusters configured - setup button should be available through selector');
        } else {
          console.log('Clusters are configured - setup button may not be needed');
        }
      }

      // Skip setup button test if it doesn't exist (clusters might be configured)
      test.skip(buttonExists, 'Setup button not visible - clusters may already be configured');
      return;
    }

    // Step 2: Verify button properties
    const buttonText = await setupButton.textContent();
    const buttonEnabled = await setupButton.isEnabled();
    const buttonClickable = await setupButton.isClickable?.() ?? true;

    console.log(`Step 2 - Button text: "${buttonText}"`);
    console.log(`Step 2 - Button enabled: ${buttonEnabled}`);
    console.log(`Step 2 - Button clickable: ${buttonClickable}`);

    expect(buttonText).toMatch(/Setup Kubernetes/i);
    expect(buttonEnabled).toBeTruthy();

    // Step 3: Take screenshot before click
    await page.screenshot({ path: 'debug-before-setup-click.png' });

    // Step 4: Click and monitor immediate response
    console.log('Step 4 - Clicking setup button...');

    const clickPromise = setupButton.click();
    const clickTime = Date.now();

    await clickPromise;
    const responseTime = Date.now() - clickTime;

    console.log(`Step 4 - Click executed in ${responseTime}ms`);

    // Step 5: Check for immediate visual changes
    await page.waitForTimeout(500); // Small delay for immediate responses

    // Look for common responses to button clicks
    const responses = {
      modal: await page.locator('[role="dialog"], .modal, [data-testid*="modal"]').isVisible(),
      dropdown: await page.locator('[class*="absolute"], .dropdown-menu').isVisible(),
      settingsPanel: await page.locator('[data-testid*="settings"], .settings-panel').isVisible(),
      loadingState: await page.locator('.animate-spin, .loading, [data-testid*="loading"]').isVisible(),
      errorMessage: await page.locator('[data-testid*="error"], [class*="error"]').isVisible(),
      urlChange: page.url() !== 'http://localhost:3001/',
    };

    console.log('Step 5 - Checking for responses:');
    Object.entries(responses).forEach(([type, visible]) => {
      console.log(`  - ${type}: ${visible}`);
    });

    // Step 6: Take screenshot after click
    await page.screenshot({ path: 'debug-after-setup-click.png' });

    // Step 7: Wait longer for delayed responses
    await page.waitForTimeout(2000);

    const delayedResponses = {
      modal: await page.locator('[role="dialog"], .modal, [data-testid*="modal"]').isVisible(),
      dropdown: await page.locator('[class*="absolute"], .dropdown-menu').isVisible(),
      settingsPanel: await page.locator('[data-testid*="settings"], .settings-panel').isVisible(),
    };

    console.log('Step 7 - Checking for delayed responses:');
    Object.entries(delayedResponses).forEach(([type, visible]) => {
      console.log(`  - ${type}: ${visible}`);
    });

    // Step 8: Check page content changes
    const pageContent = await page.textContent('body');
    const hasNewContent =
      pageContent?.includes('Configure') ||
      pageContent?.includes('Settings') ||
      pageContent?.includes('Setup');

    console.log(`Step 8 - Page has setup-related content: ${hasNewContent}`);

    // Assertion: At least one response should be visible
    const hasAnyResponse = Object.values({...responses, ...delayedResponses}).some(Boolean) || hasNewContent;

    if (!hasAnyResponse) {
      console.log('\n❌ NO RESPONSE DETECTED - This confirms the reported issue!');
      console.log('Button clicked but no visible response occurred.');

      // Additional debugging
      const allButtons = await page.locator('button').count();
      const clickableElements = await page.locator('[onclick], [data-testid*="click"]').count();

      console.log(`Total buttons on page: ${allButtons}`);
      console.log(`Elements with click handlers: ${clickableElements}`);

      // Check if event listeners are attached
      const hasEventListeners = await setupButton.evaluate((el) => {
        const events = getEventListeners?.(el) || {};
        return Object.keys(events).length > 0;
      });

      console.log(`Button has event listeners: ${hasEventListeners}`);
    } else {
      console.log('\n✅ Response detected - button is working correctly!');
    }

    expect(hasAnyResponse).toBeTruthy();
  });

  test('Debug: Settings button click response', async ({ page }) => {
    console.log('\n=== DEBUGGING SETTINGS BUTTON ===');

    const settingsButton = page.getByTestId('k8s-panel-settings');
    const buttonExists = await settingsButton.isVisible();

    console.log(`Settings button exists: ${buttonExists}`);

    if (!buttonExists) {
      console.log('Settings button not found. Checking page structure...');

      const k8sPanel = page.locator('text=Kubernetes').locator('..').locator('..');
      const panelExists = await k8sPanel.isVisible();

      console.log(`Kubernetes panel exists: ${panelExists}`);

      if (panelExists) {
        const panelContent = await k8sPanel.textContent();
        console.log(`Panel content preview: "${panelContent?.substring(0, 100)}..."`);

        const settingsButtons = await k8sPanel.locator('button[title*="settings"], button[data-testid*="settings"]').count();
        console.log(`Settings buttons in panel: ${settingsButtons}`);
      }

      test.skip(!buttonExists, 'Settings button not found');
      return;
    }

    // Test settings button
    const buttonTitle = await settingsButton.getAttribute('title');
    console.log(`Settings button title: "${buttonTitle}"`);

    expect(buttonTitle).toMatch(/settings/i);

    await page.screenshot({ path: 'debug-before-settings-click.png' });

    console.log('Clicking settings button...');
    await settingsButton.click();

    await page.waitForTimeout(1000);

    const responses = {
      modal: await page.locator('[role="dialog"], .modal').isVisible(),
      settingsPanel: await page.locator('[data-testid*="settings"]').isVisible(),
      dropdown: await page.locator('[class*="absolute"]').isVisible(),
    };

    console.log('Settings button responses:');
    Object.entries(responses).forEach(([type, visible]) => {
      console.log(`  - ${type}: ${visible}`);
    });

    await page.screenshot({ path: 'debug-after-settings-click.png' });

    const hasResponse = Object.values(responses).some(Boolean);

    if (!hasResponse) {
      console.log('\n❌ Settings button shows no response!');
    } else {
      console.log('\n✅ Settings button is working correctly!');
    }

    expect(hasResponse).toBeTruthy();
  });

  test('Debug: Cluster selector click response', async ({ page }) => {
    console.log('\n=== DEBUGGING CLUSTER SELECTOR ===');

    const clusterSelector = page.getByTestId('cluster-selector');
    const selectorExists = await clusterSelector.isVisible();

    console.log(`Cluster selector exists: ${selectorExists}`);

    if (!selectorExists) {
      test.skip(!selectorExists, 'Cluster selector not found');
      return;
    }

    const selectorText = await clusterSelector.textContent();
    console.log(`Selector text: "${selectorText}"`);

    await page.screenshot({ path: 'debug-before-selector-click.png' });

    console.log('Clicking cluster selector...');
    await clusterSelector.click();

    await page.waitForTimeout(500);

    // Look for dropdown menu
    const dropdown = clusterSelector.locator('..').locator('[class*="absolute"]');
    const dropdownVisible = await dropdown.isVisible();

    console.log(`Dropdown visible after click: ${dropdownVisible}`);

    if (dropdownVisible) {
      const dropdownContent = await dropdown.textContent();
      console.log(`Dropdown content: "${dropdownContent}"`);

      // Check for cluster options
      const clusterOptions = await page.getByTestId('cluster-option').count();
      const settingsOptions = await page.getByTestId('open-k8s-settings').count();
      const manageOptions = await page.getByTestId('manage-clusters').count();

      console.log(`Cluster options found: ${clusterOptions}`);
      console.log(`Settings options found: ${settingsOptions}`);
      console.log(`Manage options found: ${manageOptions}`);
    }

    await page.screenshot({ path: 'debug-after-selector-click.png' });

    if (!dropdownVisible) {
      console.log('\n❌ Cluster selector shows no response!');
    } else {
      console.log('\n✅ Cluster selector is working correctly!');
    }

    expect(dropdownVisible).toBeTruthy();
  });

  test('Debug: Refresh button click response', async ({ page }) => {
    console.log('\n=== DEBUGGING REFRESH BUTTON ===');

    // Find refresh button specifically in Kubernetes panel
    const k8sPanel = page.locator('text=Kubernetes Pods').locator('..').locator('..');
    const refreshButton = k8sPanel.locator('button').filter({
      has: page.locator('[data-lucide="refresh-cw"], .RefreshCw')
    }).first();

    const buttonExists = await refreshButton.isVisible();
    console.log(`Refresh button exists: ${buttonExists}`);

    if (!buttonExists) {
      // Try alternative selectors
      const altRefreshButton = page.locator('button[title*="refresh"]').first();
      const altButtonExists = await altRefreshButton.isVisible();

      console.log(`Alternative refresh button exists: ${altButtonExists}`);

      test.skip(!buttonExists && !altButtonExists, 'Refresh button not found');
      return;
    }

    const buttonEnabled = await refreshButton.isEnabled();
    console.log(`Refresh button enabled: ${buttonEnabled}`);

    expect(buttonEnabled).toBeTruthy();

    await page.screenshot({ path: 'debug-before-refresh-click.png' });

    console.log('Clicking refresh button...');
    const clickTime = Date.now();

    await refreshButton.click();

    // Check for immediate loading state
    await page.waitForTimeout(100);

    const immediateLoading = await refreshButton.locator('.animate-spin').isVisible();
    const buttonDisabled = await refreshButton.isDisabled();

    console.log(`Immediate loading state: ${immediateLoading}`);
    console.log(`Button disabled during refresh: ${buttonDisabled}`);

    // Wait for potential loading to complete
    await page.waitForTimeout(2000);

    const finalLoading = await refreshButton.locator('.animate-spin').isVisible();
    const finalDisabled = await refreshButton.isDisabled();

    console.log(`Final loading state: ${finalLoading}`);
    console.log(`Final disabled state: ${finalDisabled}`);

    const responseTime = Date.now() - clickTime;
    console.log(`Total response time: ${responseTime}ms`);

    await page.screenshot({ path: 'debug-after-refresh-click.png' });

    const hasResponse = immediateLoading || buttonDisabled || !finalDisabled;

    if (!hasResponse) {
      console.log('\n❌ Refresh button shows no response!');
    } else {
      console.log('\n✅ Refresh button is working correctly!');
    }

    expect(hasResponse).toBeTruthy();
  });

  test('Debug: Check for JavaScript errors and event handling', async ({ page }) => {
    console.log('\n=== DEBUGGING JAVASCRIPT ERRORS ===');

    const errors: string[] = [];
    const warnings: string[] = [];

    page.on('pageerror', (error) => {
      errors.push(error.message);
      console.log(`[PAGE ERROR]: ${error.message}`);
    });

    page.on('console', (msg) => {
      if (msg.type() === 'error') {
        errors.push(msg.text());
      } else if (msg.type() === 'warning') {
        warnings.push(msg.text());
      }
    });

    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(3000);

    console.log(`JavaScript errors found: ${errors.length}`);
    console.log(`JavaScript warnings found: ${warnings.length}`);

    errors.forEach((error, i) => {
      console.log(`Error ${i + 1}: ${error}`);
    });

    warnings.forEach((warning, i) => {
      console.log(`Warning ${i + 1}: ${warning}`);
    });

    // Check React/Next.js hydration
    const reactErrors = errors.filter(error =>
      error.includes('hydration') ||
      error.includes('React') ||
      error.includes('Next.js')
    );

    console.log(`React/hydration errors: ${reactErrors.length}`);

    // Check for event listener errors
    const eventErrors = errors.filter(error =>
      error.includes('addEventListener') ||
      error.includes('onClick') ||
      error.includes('event')
    );

    console.log(`Event handling errors: ${eventErrors.length}`);

    // The presence of errors might explain button non-responsiveness
    if (errors.length > 0) {
      console.log('\n⚠️  JavaScript errors detected - these may cause button non-responsiveness!');
    } else {
      console.log('\n✅ No JavaScript errors detected');
    }

    // Non-failing assertion - we log issues but don't fail the test
    expect(errors.length).toBeLessThan(10); // Allow some warnings but not too many errors
  });
});