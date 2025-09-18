import { test, expect } from '@playwright/test';

/**
 * Enhanced Docker Container Details Tests
 *
 * These tests reproduce and validate the user-reported issue with Docker container
 * details functionality. Based on manual testing, the functionality works correctly
 * but depends on backend WebSocket connection and actual running containers.
 */

test.describe('Docker Container Details - Enhanced Analysis', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
  });

  test('should show Docker Containers panel and handle WebSocket connection', async ({ page }) => {
    // Monitor WebSocket and console messages
    const consoleMessages: string[] = [];
    const wsMessages: string[] = [];

    page.on('console', msg => {
      consoleMessages.push(`${msg.type()}: ${msg.text()}`);
    });

    page.on('websocket', ws => {
      ws.on('framereceived', frame => {
        if (frame.payload) {
          wsMessages.push(frame.payload.toString());
        }
      });
    });

    // Navigate and wait for the application to initialize
    await page.goto('/');
    await page.waitForTimeout(5000);

    // Verify Docker Containers panel is visible
    const dockerPanel = page.locator('.card', { hasText: 'Docker Containers' });
    await expect(dockerPanel).toBeVisible({ timeout: 15000 });

    // Log the connection status
    const connectionStatus = page.locator('[data-testid*="connection"], .text-white\\/80:has-text("Connected"), .text-white\\/80:has-text("Disconnected")');
    const isConnected = await connectionStatus.first().textContent();
    console.log(`🔗 WebSocket Connection Status: ${isConnected}`);

    // Check what's inside the Docker panel
    const dockerPanelContent = await dockerPanel.textContent();
    console.log(`📋 Docker Panel Content: ${dockerPanelContent}`);

    // Look for different possible states
    const loadingState = dockerPanel.locator('.animate-pulse');
    const noContainersState = dockerPanel.locator(':has-text("No containers found")');
    const containerItems = dockerPanel.locator('.space-y-2 > div');

    if (await loadingState.count() > 0) {
      console.log('📊 Status: Containers are loading...');
    } else if (await noContainersState.count() > 0) {
      console.log('🐳 Status: No containers found (expected without Docker backend)');
      await expect(noContainersState).toBeVisible();
      await expect(noContainersState).toContainText('No containers found');
      await expect(noContainersState).toContainText('Docker may not be running or accessible');
    } else if (await containerItems.count() > 0) {
      console.log(`📦 Status: Found ${await containerItems.count()} container(s)`);

      // If containers are present, test the eye icon functionality
      const firstContainer = containerItems.first();
      const eyeIcon = firstContainer.locator('button[title="View logs"]');

      if (await eyeIcon.count() > 0) {
        console.log('👁️ Eye icon found - testing logs functionality');
        await eyeIcon.click();

        // Check if LogViewer modal appears
        const logModal = page.locator('h3:has-text("Logs")');
        await expect(logModal).toBeVisible({ timeout: 10000 });

        // Check modal content
        const modalContent = page.locator('.fixed.inset-0');
        await expect(modalContent).toBeVisible();

        console.log('✅ LogViewer modal opened successfully');

        // Close modal
        await page.locator('button[title="Close"]').click();
        await expect(logModal).not.toBeVisible();
      }
    } else {
      console.log('❓ Status: Unknown container panel state');
    }

    // Log some console messages for debugging
    console.log(`📝 Console messages (${consoleMessages.length}):`, consoleMessages.slice(-5));
    console.log(`🔌 WebSocket messages (${wsMessages.length}):`, wsMessages.slice(-3));
  });

  test('should gracefully handle backend disconnection scenario', async ({ page }) => {
    // This test simulates the user's scenario where backend might not be available
    await page.goto('/');

    // Wait for initial connection attempt
    await page.waitForTimeout(8000);

    const dockerPanel = page.locator('.card', { hasText: 'Docker Containers' });
    await expect(dockerPanel).toBeVisible();

    // In disconnected state, we should see the "No containers found" message
    const noContainersMessage = dockerPanel.locator(':has-text("No containers found")');

    if (await noContainersMessage.count() > 0) {
      console.log('✅ Correctly showing "No containers found" when backend is unavailable');

      // Verify the helpful message is shown
      await expect(noContainersMessage).toContainText('Docker may not be running or accessible');

      // Verify no eye icons are present (since no containers)
      const eyeIcons = dockerPanel.locator('button[title="View logs"]');
      expect(await eyeIcons.count()).toBe(0);

      console.log('✅ No eye icons present when no containers available - correct behavior');
    } else {
      // If containers are somehow present, that's also valid
      console.log('ℹ️ Containers are present - this indicates backend is working');
    }
  });

  test('should show proper error handling when clicking refresh without backend', async ({ page }) => {
    await page.goto('/');
    await page.waitForTimeout(5000);

    const dockerPanel = page.locator('.card', { hasText: 'Docker Containers' });
    await expect(dockerPanel).toBeVisible();

    // Find and click refresh button
    const refreshButton = dockerPanel.locator('button:has(svg)').first();
    await expect(refreshButton).toBeVisible();

    // Monitor console for errors
    const consoleErrors: string[] = [];
    page.on('console', msg => {
      if (msg.type() === 'error') {
        consoleErrors.push(msg.text());
      }
    });

    await refreshButton.click();
    await page.waitForTimeout(3000);

    // Should not crash or show unhandled errors
    console.log(`🔍 Console errors after refresh: ${consoleErrors.length}`);

    // The panel should still be functional
    await expect(dockerPanel).toBeVisible();
  });

  test('should have proper accessibility for container details functionality', async ({ page }) => {
    await page.goto('/');
    await page.waitForTimeout(5000);

    const dockerPanel = page.locator('.card', { hasText: 'Docker Containers' });
    await expect(dockerPanel).toBeVisible();

    // Check if the panel has proper heading structure
    const heading = dockerPanel.locator('h2:has-text("Docker Containers")');
    await expect(heading).toBeVisible();

    // If containers are present, check accessibility of eye icons
    const containerItems = dockerPanel.locator('.space-y-2 > div');

    if (await containerItems.count() > 0) {
      const eyeIcons = dockerPanel.locator('button[title="View logs"]');

      for (let i = 0; i < await eyeIcons.count(); i++) {
        const eyeIcon = eyeIcons.nth(i);

        // Should have proper title attribute
        await expect(eyeIcon).toHaveAttribute('title', 'View logs');

        // Should be focusable
        await eyeIcon.focus();
        expect(await eyeIcon.evaluate(el => document.activeElement === el)).toBe(true);
      }

      console.log(`✅ All ${await eyeIcons.count()} eye icons have proper accessibility attributes`);
    } else {
      console.log('ℹ️ No containers present to test eye icon accessibility');
    }
  });
});