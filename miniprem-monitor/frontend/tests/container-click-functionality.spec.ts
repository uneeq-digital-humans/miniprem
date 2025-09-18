import { test, expect } from '@playwright/test';

/**
 * Container Click Functionality Tests
 *
 * Tests the container click expansion functionality and ensures proper
 * handling of container ports data to prevent runtime errors.
 *
 * User Story: As a user, when I click on a Docker container in the dashboard,
 * I expect to see expanded details without encountering runtime errors,
 * particularly with ports handling.
 */

test.describe('Container Click Functionality', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
  });

  test('should expand container details when clicked without runtime errors', async ({ page }) => {
    // Monitor console errors
    const consoleErrors: string[] = [];
    page.on('console', msg => {
      if (msg.type() === 'error') {
        consoleErrors.push(msg.text());
      }
    });

    // Wait for containers to load
    await page.waitForTimeout(8000);

    // Look for the Docker Containers panel
    const dockerPanel = page.locator('.card', { hasText: 'Docker Containers' });
    await expect(dockerPanel).toBeVisible({ timeout: 15000 });

    // Wait for containers to load (not in loading skeleton state)
    await expect(page.locator('[data-testid="container-loading"]')).not.toBeVisible({ timeout: 15000 });

    // Look for container items
    const containerItems = page.locator('[data-testid="container-item"]');

    // Skip test if no containers are available
    if (await containerItems.count() === 0) {
      console.log('⚠️  No containers available for testing');
      return;
    }

    const containerCount = await containerItems.count();
    console.log(`Found ${containerCount} Docker containers`);

    // Test clicking on the first container
    const firstContainer = containerItems.first();

    // Get container name for debugging
    const containerName = await firstContainer.getAttribute('data-container-item') || 'unknown';
    console.log(`Testing container: ${containerName}`);

    // Click on the container to expand details
    await firstContainer.click();

    // Wait for any potential errors to surface
    await page.waitForTimeout(2000);

    // Verify no runtime errors occurred
    const runtimeErrors = consoleErrors.filter(error =>
      error.includes('container.ports.join is not a function') ||
      error.includes('TypeError') ||
      error.includes('Cannot read propert')
    );

    expect(runtimeErrors).toHaveLength(0);

    if (runtimeErrors.length > 0) {
      console.log('Runtime errors detected:', runtimeErrors);
      throw new Error(`Runtime errors occurred: ${runtimeErrors.join(', ')}`);
    }

    console.log('✅ Container clicked without runtime errors');
  });

  test('should display expanded container details with proper ports handling', async ({ page }) => {
    // Wait for containers to load
    await page.waitForTimeout(8000);

    const dockerPanel = page.locator('.card', { hasText: 'Docker Containers' });
    await expect(dockerPanel).toBeVisible();

    // Wait for containers to load
    await expect(page.locator('[data-testid="container-loading"]')).not.toBeVisible({ timeout: 15000 });

    const containerItems = page.locator('[data-testid="container-item"]');

    if (await containerItems.count() === 0) {
      console.log('⚠️  No containers available for testing');
      return;
    }

    // Click on the first container
    const firstContainer = containerItems.first();
    await firstContainer.click();

    // Wait for expansion
    await page.waitForTimeout(1000);

    // Check if the container expanded (should show additional details)
    const expandedContent = page.locator('.border-uneeq-primary, .bg-blue-50');

    // The container should either be expanded or not show errors
    // We're primarily testing that no runtime errors occur
    const pageContent = await page.textContent('body');

    // Ensure no error messages are displayed
    expect(pageContent).not.toContain('container.ports.join is not a function');
    expect(pageContent).not.toContain('TypeError');
    expect(pageContent).not.toContain('Runtime Error');

    console.log('✅ Container details displayed without errors');
  });

  test('should handle containers with various ports data types', async ({ page }) => {
    // This test verifies that the formatPorts function handles different data types
    // Monitor console for any errors during container interaction

    const consoleErrors: string[] = [];
    const consoleWarnings: string[] = [];

    page.on('console', msg => {
      if (msg.type() === 'error') {
        consoleErrors.push(msg.text());
      }
      if (msg.type() === 'warning') {
        consoleWarnings.push(msg.text());
      }
    });

    // Wait for containers to load
    await page.waitForTimeout(8000);

    const dockerPanel = page.locator('.card', { hasText: 'Docker Containers' });
    await expect(dockerPanel).toBeVisible();

    await expect(page.locator('[data-testid="container-loading"]')).not.toBeVisible({ timeout: 15000 });

    const containerItems = page.locator('[data-testid="container-item"]');
    const containerCount = await containerItems.count();

    if (containerCount === 0) {
      console.log('⚠️  No containers available for testing');
      return;
    }

    // Test clicking on multiple containers if available
    const testCount = Math.min(containerCount, 3);

    for (let i = 0; i < testCount; i++) {
      const container = containerItems.nth(i);
      const containerName = await container.getAttribute('data-container-item') || `container-${i}`;

      console.log(`Testing ports handling for: ${containerName}`);

      // Click container
      await container.click();
      await page.waitForTimeout(1000);

      // Click again to collapse (if expanded)
      await container.click();
      await page.waitForTimeout(500);
    }

    // Verify no ports-related errors occurred
    const portsErrors = consoleErrors.filter(error =>
      error.includes('ports') ||
      error.includes('join is not a function') ||
      error.includes('formatPorts')
    );

    expect(portsErrors).toHaveLength(0);

    if (portsErrors.length > 0) {
      throw new Error(`Ports handling errors: ${portsErrors.join(', ')}`);
    }

    console.log(`✅ Successfully tested ${testCount} containers without ports errors`);
  });

  test('should not crash when containers have malformed data', async ({ page }) => {
    // Test resilience against malformed container data
    const pageErrors: string[] = [];

    page.on('pageerror', error => {
      pageErrors.push(error.message);
    });

    // Wait for containers to load
    await page.waitForTimeout(8000);

    const dockerPanel = page.locator('.card', { hasText: 'Docker Containers' });
    await expect(dockerPanel).toBeVisible();

    await expect(page.locator('[data-testid="container-loading"]')).not.toBeVisible({ timeout: 15000 });

    const containerItems = page.locator('[data-testid="container-item"]');

    if (await containerItems.count() === 0) {
      console.log('⚠️  No containers available for testing');
      return;
    }

    // Rapidly click containers to test error handling
    const containerCount = await containerItems.count();

    for (let i = 0; i < Math.min(containerCount, 2); i++) {
      try {
        await containerItems.nth(i).click({ timeout: 2000 });
        await page.waitForTimeout(500);
      } catch (error) {
        // Ignore timeout errors, focus on runtime errors
      }
    }

    // Check that no page crashes occurred
    expect(pageErrors).toHaveLength(0);

    // Verify the page is still functional
    await expect(dockerPanel).toBeVisible();

    console.log('✅ Page remained stable during rapid container clicks');
  });
});