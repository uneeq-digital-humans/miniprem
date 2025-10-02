import { test, expect } from '@playwright/test';

/**
 * System Health Status Integration Tests
 *
 * Tests that verify the EXISTING simple Docker Status and Kubernetes Status
 * sections display actual availability values instead of "not available" messages.
 *
 * CONTEXT: The user reported that the System Health section shows "not available"
 * instead of actual Docker and Kubernetes availability status. The backend has been
 * updated to include Docker/Kubernetes availability in systemInfo, but the frontend
 * conditional rendering may not be working.
 */

test.describe('System Health Status Integration', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
  });

  test('should display actual Docker Status instead of not being visible', async ({ page }) => {
    // Navigate to the dashboard
    await page.goto('/');

    // Wait for page to load and WebSocket to connect
    await page.waitForTimeout(8000);

    // Look for the existing simple Docker Status section (not SystemHealthPanel)
    // This is the section at lines 244-252 in page.tsx
    const dockerStatusCard = page.locator('.card', { hasText: 'Docker Status' });

    // The test should FAIL initially because this section might not be visible
    // due to systemInfo not being populated
    await expect(dockerStatusCard).toBeVisible({ timeout: 15000 });

    // Within the Docker Status card, look for the status text
    const statusSpan = dockerStatusCard.locator('span.text-sm.text-gray-600');
    await expect(statusSpan).toBeVisible();

    // The status should be either "Available" or "Unavailable: [error]"
    // It should NOT be empty or contain "not available" (lowercase)
    const statusText = await statusSpan.textContent();
    console.log('Docker status text:', statusText);

    // This assertion should FAIL initially if systemInfo is not populated
    expect(statusText).toMatch(/(Available|Unavailable)/);
    expect(statusText).not.toContain('not available');

    console.log('✅ Docker Status section is visible with actual availability status');
  });

  test('should display actual Kubernetes Status instead of not being visible', async ({ page }) => {
    // Navigate to the dashboard
    await page.goto('/');

    // Wait for page to load and WebSocket to connect
    await page.waitForTimeout(8000);

    // Look for the existing simple Kubernetes Status section
    // This is the section at lines 254-262 in page.tsx
    const kubernetesStatusCard = page.locator('.card', { hasText: 'Kubernetes Status' });

    // The test should FAIL initially because this section might not be visible
    await expect(kubernetesStatusCard).toBeVisible({ timeout: 15000 });

    // Within the Kubernetes Status card, look for the status text
    const statusSpan = kubernetesStatusCard.locator('span.text-sm.text-gray-600');
    await expect(statusSpan).toBeVisible();

    // The status should be either "Available" or "Unavailable: [error]"
    const statusText = await statusSpan.textContent();
    console.log('Kubernetes status text:', statusText);

    // This assertion should FAIL initially if systemInfo is not populated
    expect(statusText).toMatch(/(Available|Unavailable)/);
    expect(statusText).not.toContain('not available');

    console.log('✅ Kubernetes Status section is visible with actual availability status');
  });

  test('should have systemInfo populated via WebSocket system:info subscription', async ({ page }) => {
    // Monitor WebSocket messages to debug systemInfo population
    const wsMessages: any[] = [];

    page.on('websocket', ws => {
      ws.on('framesent', event => {
        try {
          const data = JSON.parse(event.payload.toString());
          wsMessages.push({ type: 'sent', data });
          if (data.type === 'subscribe' && data.target === 'system') {
            console.log('WebSocket sent system subscription:', data);
          }
        } catch (e) {
          // Ignore non-JSON frames
        }
      });

      ws.on('framereceived', event => {
        try {
          const data = JSON.parse(event.payload.toString());
          wsMessages.push({ type: 'received', data });
          if (data.requestId && data.requestId.includes('system:info')) {
            console.log('WebSocket received system:info response:', data);
          }
        } catch (e) {
          // Ignore non-JSON frames
        }
      });
    });

    // Navigate and wait for WebSocket activity
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(10000); // Give time for WebSocket communication

    // Check that system:info subscription was sent
    const systemInfoSubscriptions = wsMessages.filter(msg =>
      msg.type === 'sent' &&
      msg.data.type === 'subscribe' &&
      msg.data.target === 'system' &&
      msg.data.command === 'info'
    );

    // This should FAIL if the WebSocket schema doesn't allow 'system' target
    expect(systemInfoSubscriptions.length).toBeGreaterThan(0);

    // Check for successful system:info responses containing Docker/Kubernetes data
    const systemInfoResponses = wsMessages.filter(msg =>
      msg.type === 'received' &&
      msg.data.success === true &&
      msg.data.requestId &&
      msg.data.requestId.includes('system:info') &&
      msg.data.data &&
      msg.data.data.system &&
      msg.data.data.system.docker &&
      msg.data.data.system.kubernetes
    );

    // This will FAIL initially if backend doesn't send system info with Docker/K8s availability
    expect(systemInfoResponses.length).toBeGreaterThan(0);

    console.log('✅ System info WebSocket communication is working properly');
  });

  test('should show Docker and Kubernetes status indicators with correct colors', async ({ page }) => {
    // Navigate and wait
    await page.goto('/');
    await page.waitForTimeout(8000);

    // Check Docker status indicator (colored dot)
    const dockerCard = page.locator('.card', { hasText: 'Docker Status' });
    await expect(dockerCard).toBeVisible();

    const dockerStatusDot = dockerCard.locator('.w-3.h-3.rounded-full');
    await expect(dockerStatusDot).toBeVisible();

    // The dot should have either 'bg-status-healthy' (green) or 'bg-status-error' (red)
    const dockerDotClass = await dockerStatusDot.getAttribute('class');
    expect(dockerDotClass).toMatch(/(bg-status-healthy|bg-status-error)/);

    // Check Kubernetes status indicator
    const kubernetesCard = page.locator('.card', { hasText: 'Kubernetes Status' });
    await expect(kubernetesCard).toBeVisible();

    const kubernetesStatusDot = kubernetesCard.locator('.w-3.h-3.rounded-full');
    await expect(kubernetesStatusDot).toBeVisible();

    const kubernetesDotClass = await kubernetesStatusDot.getAttribute('class');
    expect(kubernetesDotClass).toMatch(/(bg-status-healthy|bg-status-error)/);

    console.log('✅ Status indicators are present with proper styling');
  });
});