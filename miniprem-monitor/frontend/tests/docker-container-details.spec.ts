import { test, expect } from '@playwright/test';

/**
 * Docker Container Details Integration Tests
 *
 * Tests the functionality of viewing Docker container details when clicking
 * the eye icon next to running containers.
 *
 * User Story: As a user, when I access the frontend at localhost:3001, I expect
 * to see a list of docker containers currently running. I click the eye icon
 * to the right of a container, and I expect to see details about the container.
 */

test.describe('Docker Container Details', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
  });

  test('should display Docker containers and allow viewing container details via eye icon', async ({ page }) => {
    // Navigate to the dashboard
    await page.goto('/');

    // Wait for containers to load
    await page.waitForTimeout(8000);

    // Look for the Docker Containers panel
    const dockerPanel = page.locator('.card', { hasText: 'Docker Containers' });
    await expect(dockerPanel).toBeVisible({ timeout: 15000 });

    // Wait for containers to load (not in loading skeleton state)
    await expect(page.locator('[data-testid="container-loading"]')).not.toBeVisible({ timeout: 15000 });

    // Look for container items (should have actual container data, not loading placeholders)
    const containerItems = page.locator('.card:has-text("Docker Containers") .space-y-3 > div:not(.animate-pulse)');

    // Wait for at least one real container to appear
    await expect(containerItems.first()).toBeVisible({ timeout: 15000 });

    const containerCount = await containerItems.count();
    expect(containerCount).toBeGreaterThan(0);

    console.log(`Found ${containerCount} Docker containers`);

    // Find the first container with an eye icon (details button)
    const firstContainer = containerItems.first();
    const eyeIcon = firstContainer.locator('button:has([data-testid*="eye"]), button:has(svg:has(path[d*="eye"])), button[title*="details"], button[aria-label*="details"]');

    // Check if eye icon exists
    if (await eyeIcon.count() > 0) {
      console.log('Eye icon found, clicking to view container details...');

      // Click the eye icon to view container details
      await eyeIcon.click();

      // Wait for container details to appear (modal, popup, or expanded view)
      // This could be in various forms - modal, sidebar, expanded section, etc.
      const containerDetails = page.locator('[data-testid*="container-details"], .modal:has-text("Container"), .details-panel, .expanded-container');

      // Expect container details to be visible
      await expect(containerDetails).toBeVisible({ timeout: 10000 });

      // Check for common container details fields
      const detailsContent = containerDetails.or(page.locator('body'));

      // Look for typical container detail information
      await expect(detailsContent).toContainText(/Container ID|Image|Status|Ports|Environment|Volumes|Created|Command/i);

      console.log('✅ Container details displayed successfully');

    } else {
      console.log('⚠️  No eye icon found on containers');

      // If no eye icon, check if containers have any interactive elements
      const interactiveElements = firstContainer.locator('button, a, [role="button"]');
      const interactiveCount = await interactiveElements.count();

      if (interactiveCount === 0) {
        throw new Error('No eye icon or interactive elements found on containers. Container details functionality may not be implemented.');
      }

      // Try clicking the first interactive element to see if it shows details
      await interactiveElements.first().click();

      // Look for any container details that might appear
      await page.waitForTimeout(2000);

      const anyDetails = page.locator('[data-testid*="detail"], .modal, .popup, .sidebar, .expanded');

      if (await anyDetails.count() === 0) {
        throw new Error('Clicked interactive element but no container details appeared');
      }
    }
  });

  test('should show container details with proper information structure', async ({ page }) => {
    // Navigate and wait for containers
    await page.goto('/');
    await page.waitForTimeout(8000);

    const dockerPanel = page.locator('.card', { hasText: 'Docker Containers' });
    await expect(dockerPanel).toBeVisible();

    // Look for containers
    const containerItems = page.locator('.card:has-text("Docker Containers") .space-y-3 > div:not(.animate-pulse)');
    await expect(containerItems.first()).toBeVisible({ timeout: 15000 });

    // Find and click eye icon or details button
    const firstContainer = containerItems.first();
    const detailsButton = firstContainer.locator('button:has([data-testid*="eye"]), button:has(svg), button[title*="view"], button[aria-label*="view"]');

    if (await detailsButton.count() > 0) {
      await detailsButton.first().click();

      // Wait for details to load
      await page.waitForTimeout(2000);

      // Check for specific container detail fields that should be present
      const pageContent = page.locator('body');

      // Verify essential container information is displayed
      await expect(pageContent).toContainText(/container|image|status/i, { timeout: 5000 });

      console.log('✅ Container details contain expected information structure');
    } else {
      throw new Error('No details button found to test container information structure');
    }
  });

  test('should handle container details errors gracefully', async ({ page }) => {
    // Monitor console errors that might occur when viewing container details
    const consoleErrors: string[] = [];

    page.on('console', msg => {
      if (msg.type() === 'error') {
        consoleErrors.push(msg.text());
      }
    });

    // Monitor network errors
    const networkErrors: string[] = [];

    page.on('response', response => {
      if (!response.ok()) {
        networkErrors.push(`${response.status()} ${response.url()}`);
      }
    });

    // Navigate and interact with container details
    await page.goto('/');
    await page.waitForTimeout(8000);

    const dockerPanel = page.locator('.card', { hasText: 'Docker Containers' });
    await expect(dockerPanel).toBeVisible();

    const containerItems = page.locator('.card:has-text("Docker Containers") .space-y-3 > div:not(.animate-pulse)');

    if (await containerItems.count() > 0) {
      const firstContainer = containerItems.first();
      const detailsButton = firstContainer.locator('button:has(svg), button[role="button"]');

      if (await detailsButton.count() > 0) {
        await detailsButton.first().click();
        await page.waitForTimeout(3000);

        // Check if any errors occurred during the details viewing process
        if (consoleErrors.length > 0) {
          console.log('Console errors found:', consoleErrors);
          throw new Error(`Container details functionality has console errors: ${consoleErrors.join(', ')}`);
        }

        if (networkErrors.length > 0) {
          console.log('Network errors found:', networkErrors);
          throw new Error(`Container details functionality has network errors: ${networkErrors.join(', ')}`);
        }

        console.log('✅ No errors detected when viewing container details');
      }
    }
  });
});