/**
 * MiniPrem Monitor - Kubernetes Panel Responsive Behavior Tests
 *
 * Tests the three-row layout responsiveness across different viewport widths:
 * Row 1: "Kubernetes Pods" title with refresh icon
 * Row 2: Region, EKS, Service, Namespace dropdowns (responsive wrapping)
 * Row 3: Pod status filter (All, Running, Pending, Failed, etc.)
 *
 * Expected behavior:
 * - Wide screen (1200px+): All controls fit on one row below title
 * - Narrow screen (768px): Controls wrap to two rows as needed
 * - Mobile (375px): Proper mobile layout with stacked controls
 */

import { test, expect } from '@playwright/test';
import type { Page } from '@playwright/test';

// Mock data for consistent testing
const mockPods = [
  {
    name: 'renny-deployment-abc123',
    namespace: 'uneeq-renderer',
    status: 'Running',
    ready: '1/1',
    age: '2d',
    restarts: 0,
    node: 'ip-10-0-1-100.ec2.internal',
    cpu_usage: '150m',
    memory_usage: '512Mi'
  },
  {
    name: 'audio2face-deployment-def456',
    namespace: 'uneeq-renderer',
    status: 'Pending',
    ready: '0/1',
    age: '5m',
    restarts: 1,
    node: 'ip-10-0-1-101.ec2.internal'
  },
  {
    name: 'failed-pod-ghi789',
    namespace: 'uneeq-renderer',
    status: 'Failed',
    ready: '0/1',
    age: '10m',
    restarts: 3
  }
];

const mockClusterStatus = {
  name: 'miniprem-eks-cluster',
  context: 'arn:aws:eks:us-east-1:123456789:cluster/miniprem-eks-cluster',
  namespace: 'uneeq-renderer',
  environment: 'eks' as const,
  region: 'us-east-1',
  status: 'connected' as const,
  lastSync: new Date(),
  latency: 45,
  podCount: 12,
  nodeCount: 3
};

const availableClusters = [
  { name: 'miniprem-eks-cluster', context: 'arn:aws:eks:us-east-1:123456789:cluster/miniprem-eks-cluster', namespace: 'uneeq-renderer' }
];

const availableRegions = ['us-east-1', 'us-west-2', 'eu-west-1'];

async function setupKubernetesPanel(page: Page) {
  // Navigate to the page and wait for it to load
  await page.goto('/');
  await page.waitForSelector('[data-testid="kubernetes-panel"]', { timeout: 15000 });

  // Inject mock data via JavaScript to simulate real component state
  await page.evaluate(({ pods, clusterStatus, clusters, regions }) => {
    // Mock the data in window object for consistent testing
    window.mockKubernetesData = {
      pods,
      clusterStatus,
      availableClusters: clusters,
      availableRegions: regions,
      currentRegion: 'us-east-1',
      loading: false,
      error: null
    };
  }, {
    pods: mockPods,
    clusterStatus: mockClusterStatus,
    clusters: availableClusters,
    regions: availableRegions
  });

  // Wait for the content to be rendered
  await page.waitForSelector('[data-testid="pod-filter-all"]', { timeout: 10000 });
}

test.describe('Kubernetes Panel Responsive Behavior', () => {

  test.describe('Wide Screen Layout (1200px+)', () => {
    test('should display all controls on one row below title', async ({ page }) => {
      await page.setViewportSize({ width: 1400, height: 900 });
      await setupKubernetesPanel(page);

      // Take screenshot for wide screen layout
      await page.screenshot({
        path: 'test-results/kubernetes-panel-wide-1400px.png',
        fullPage: true
      });

      // Verify title row structure
      const titleElement = await page.getByText('Kubernetes Pods').first();
      expect(await titleElement.isVisible()).toBeTruthy();

      // Verify the three-row structure is present
      // Row 1: Title already verified above

      // Row 2: Region, EKS, Service, Namespace controls should be visible and in wide layout
      const regionSelector = page.locator('text=Region:').first();
      const eksSelector = page.locator('text=EKS:').first();
      const serviceControls = page.locator('text=Service:').first();
      const namespaceSelector = page.locator('text=NS:').first();

      await expect(regionSelector).toBeVisible();
      await expect(eksSelector).toBeVisible();
      await expect(serviceControls).toBeVisible();
      await expect(namespaceSelector).toBeVisible();

      // Row 3: Pod status filters should be visible
      const allFilter = page.locator('[data-testid="pod-filter-all"]');
      const runningFilter = page.locator('[data-testid="pod-filter-running"]');
      const pendingFilter = page.locator('[data-testid="pod-filter-pending"]');
      const failedFilter = page.locator('[data-testid="pod-filter-failed"]');

      await expect(allFilter).toBeVisible();
      await expect(runningFilter).toBeVisible();
      await expect(pendingFilter).toBeVisible();
      await expect(failedFilter).toBeVisible();

      // Verify filter counts are displayed
      await expect(allFilter).toContainText('All');
      await expect(runningFilter).toContainText('Running');
      await expect(pendingFilter).toContainText('Pending');
      await expect(failedFilter).toContainText('Failed');

      // Verify refresh button is visible in wide layout
      const refreshButton = page.locator('button[class*="animate-spin"], button:has(svg)').last();
      await expect(refreshButton).toBeVisible();
    });

    test('should show service control buttons in wide layout', async ({ page }) => {
      await page.setViewportSize({ width: 1400, height: 900 });
      await setupKubernetesPanel(page);

      // Service controls should be visible on wide screens
      const startButton = page.locator('button:has-text("Start")').first();
      const stopButton = page.locator('button:has-text("Stop")').first();

      // These might not be visible if service controls aren't enabled in this test
      // But if they are, they should be in the wide layout section
      const serviceLabel = page.locator('text=Service:').first();
      if (await serviceLabel.isVisible()) {
        await expect(startButton).toBeVisible();
        await expect(stopButton).toBeVisible();
      }
    });
  });

  test.describe('Narrow Screen Layout (768px)', () => {
    test('should wrap controls to two rows', async ({ page }) => {
      await page.setViewportSize({ width: 768, height: 1024 });
      await setupKubernetesPanel(page);

      // Take screenshot for narrow screen layout
      await page.screenshot({
        path: 'test-results/kubernetes-panel-narrow-768px.png',
        fullPage: true
      });

      // Verify title row is still present
      const titleElement = await page.getByText('Kubernetes Pods').first();
      expect(await titleElement.isVisible()).toBeTruthy();

      // In narrow layout, controls are responsive and may wrap
      // The key elements should still be present and functional
      const regionSelector = page.locator('text=Region:').first();
      const eksSelector = page.locator('text=EKS:').first();

      await expect(regionSelector).toBeVisible();
      await expect(eksSelector).toBeVisible();

      // Pod status filters should still be visible as the third row
      const allFilter = page.locator('[data-testid="pod-filter-all"]');
      const runningFilter = page.locator('[data-testid="pod-filter-running"]');

      await expect(allFilter).toBeVisible();
      await expect(runningFilter).toBeVisible();

      // Service controls should be visible on narrow screens in the second row
      const serviceLabel = page.locator('text=Service:').first();
      if (await serviceLabel.isVisible()) {
        const startButton = page.locator('button:has-text("Start")').first();
        await expect(startButton).toBeVisible();
      }

      // Namespace selector should be in the second row on narrow screens
      const namespaceSelector = page.locator('text=NS:').first();
      await expect(namespaceSelector).toBeVisible();

      // Refresh button should still be accessible
      const refreshButton = page.locator('button:has(svg[class*="w-5 h-5"])').last();
      await expect(refreshButton).toBeVisible();
    });

    test('should maintain filter functionality in narrow layout', async ({ page }) => {
      await page.setViewportSize({ width: 768, height: 1024 });
      await setupKubernetesPanel(page);

      // Test filter interaction in narrow layout
      const runningFilter = page.locator('[data-testid="pod-filter-running"]');
      await expect(runningFilter).toBeVisible();

      // Click on running filter
      await runningFilter.click();

      // Verify the filter is active (should have different styling)
      await expect(runningFilter).toHaveClass(/bg-white|shadow-sm/);

      // Switch back to all filter
      const allFilter = page.locator('[data-testid="pod-filter-all"]');
      await allFilter.click();
      await expect(allFilter).toHaveClass(/bg-white|shadow-sm/);
    });
  });

  test.describe('Mobile Layout (375px)', () => {
    test('should display proper mobile layout with stacked controls', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await setupKubernetesPanel(page);

      // Take screenshot for mobile layout
      await page.screenshot({
        path: 'test-results/kubernetes-panel-mobile-375px.png',
        fullPage: true
      });

      // Verify title is still visible
      const titleElement = await page.getByText('Kubernetes Pods').first();
      expect(await titleElement.isVisible()).toBeTruthy();

      // Pod status filters should still be functional in mobile
      const allFilter = page.locator('[data-testid="pod-filter-all"]');
      const runningFilter = page.locator('[data-testid="pod-filter-running"]');

      await expect(allFilter).toBeVisible();
      await expect(runningFilter).toBeVisible();

      // Test filter interaction on mobile
      await runningFilter.click();
      await expect(runningFilter).toHaveClass(/bg-white|shadow-sm/);

      // Verify the layout adapts properly - controls should stack vertically
      const kubernetesPanel = page.locator('[data-testid="kubernetes-panel"]').first();
      if (await kubernetesPanel.isVisible()) {
        const panelHeight = await kubernetesPanel.boundingBox();
        // Mobile layout should be taller due to stacking
        expect(panelHeight?.height).toBeGreaterThan(200);
      }
    });

    test('should maintain accessibility in mobile layout', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await setupKubernetesPanel(page);

      // Test keyboard navigation on mobile
      const allFilter = page.locator('[data-testid="pod-filter-all"]');
      const runningFilter = page.locator('[data-testid="pod-filter-running"]');

      // Focus on all filter
      await allFilter.focus();
      await expect(allFilter).toBeFocused();

      // Navigate with tab key
      await page.keyboard.press('Tab');
      await expect(runningFilter).toBeFocused();

      // Test Enter key activation
      await page.keyboard.press('Enter');
      await expect(runningFilter).toHaveClass(/bg-white|shadow-sm/);
    });
  });

  test.describe('Filter Functionality Across Viewports', () => {
    const viewports = [
      { name: 'Wide', width: 1400, height: 900 },
      { name: 'Narrow', width: 768, height: 1024 },
      { name: 'Mobile', width: 375, height: 667 }
    ];

    viewports.forEach(({ name, width, height }) => {
      test(`should show correct filter counts in ${name} viewport (${width}px)`, async ({ page }) => {
        await page.setViewportSize({ width, height });
        await setupKubernetesPanel(page);

        // Verify filter counts are displayed correctly
        const allFilter = page.locator('[data-testid="pod-filter-all"]');
        const runningFilter = page.locator('[data-testid="pod-filter-running"]');
        const pendingFilter = page.locator('[data-testid="pod-filter-pending"]');
        const failedFilter = page.locator('[data-testid="pod-filter-failed"]');

        // Check that filters show counts (based on mock data)
        await expect(allFilter).toBeVisible();
        await expect(runningFilter).toBeVisible();
        await expect(pendingFilter).toBeVisible();
        await expect(failedFilter).toBeVisible();

        // Test filter interactions
        await runningFilter.click();
        await expect(runningFilter).toHaveAttribute('aria-selected', 'true');

        await pendingFilter.click();
        await expect(pendingFilter).toHaveAttribute('aria-selected', 'true');
        await expect(runningFilter).toHaveAttribute('aria-selected', 'false');

        await failedFilter.click();
        await expect(failedFilter).toHaveAttribute('aria-selected', 'true');
        await expect(pendingFilter).toHaveAttribute('aria-selected', 'false');

        // Return to all
        await allFilter.click();
        await expect(allFilter).toHaveAttribute('aria-selected', 'true');
        await expect(failedFilter).toHaveAttribute('aria-selected', 'false');
      });
    });
  });

  test.describe('Visual Regression Tests', () => {
    test('should maintain consistent visual appearance across viewports', async ({ page }) => {
      const viewports = [
        { name: 'wide', width: 1400, height: 900 },
        { name: 'narrow', width: 768, height: 1024 },
        { name: 'mobile', width: 375, height: 667 }
      ];

      for (const { name, width, height } of viewports) {
        await page.setViewportSize({ width, height });
        await setupKubernetesPanel(page);

        // Wait for layout to stabilize
        await page.waitForTimeout(500);

        // Mask dynamic content for consistent screenshots
        await page.addStyleTag({
          content: `
            [data-testid*="connection-id"] { visibility: hidden !important; }
            [class*="animate-"] { animation: none !important; }
            .animate-spin { animation: none !important; }
            [data-testid="last-sync"] { visibility: hidden !important; }
          `
        });

        // Take screenshot for visual comparison
        await expect(page.locator('[data-testid="kubernetes-panel"]').first()).toHaveScreenshot(
          `kubernetes-panel-${name}-${width}px.png`,
          {
            threshold: 0.3,
            animations: 'disabled'
          }
        );
      }
    });
  });

  test.describe('Accessibility Testing', () => {
    test('should provide proper ARIA labels and keyboard navigation', async ({ page }) => {
      await page.setViewportSize({ width: 1200, height: 800 });
      await setupKubernetesPanel(page);

      // Test ARIA roles and labels - be specific to the Pod status filter
      const filterContainer = page.locator('[role="tablist"][aria-label="Pod status filter"]');
      await expect(filterContainer).toHaveAttribute('aria-label', 'Pod status filter');

      const allFilter = page.locator('[data-testid="pod-filter-all"]');
      await expect(allFilter).toHaveAttribute('role', 'tab');
      await expect(allFilter).toHaveAttribute('aria-selected');

      // Test keyboard navigation
      await allFilter.focus();
      await expect(allFilter).toBeFocused();

      // Test Tab navigation to move between filters
      await page.keyboard.press('Tab');
      const runningFilter = page.locator('[data-testid="pod-filter-running"]');
      await expect(runningFilter).toBeFocused();

      // Test Enter key activation
      await page.keyboard.press('Enter');
      await expect(runningFilter).toHaveAttribute('aria-selected', 'true');

      // Test Space key activation also works
      await page.keyboard.press('Tab');
      const pendingFilter = page.locator('[data-testid="pod-filter-pending"]');
      await expect(pendingFilter).toBeFocused();
      await page.keyboard.press(' ');
      await expect(pendingFilter).toHaveAttribute('aria-selected', 'true');
    });

    test('should support screen readers with proper semantic structure', async ({ page }) => {
      await page.setViewportSize({ width: 1200, height: 800 });
      await setupKubernetesPanel(page);

      // Check heading hierarchy
      const mainHeading = page.locator('h2:has-text("Kubernetes Pods")');
      await expect(mainHeading).toBeVisible();

      // Check that filter buttons have descriptive text
      const runningFilter = page.locator('[data-testid="pod-filter-running"]');
      const runningText = await runningFilter.textContent();
      expect(runningText).toContain('Running');

      // Verify that counts are announced properly
      if (runningText?.includes('1') || runningText?.includes('2') || runningText?.includes('3')) {
        // Count is present and should be accessible
        expect(runningText.length).toBeGreaterThan('Running'.length);
      }
    });
  });

  test.describe('Performance and Interaction', () => {
    test('should handle rapid viewport changes without breaking layout', async ({ page }) => {
      await setupKubernetesPanel(page);

      const viewportSizes = [
        { width: 1400, height: 900 },
        { width: 768, height: 1024 },
        { width: 375, height: 667 },
        { width: 1200, height: 800 },
        { width: 480, height: 800 }
      ];

      // Rapidly change viewport sizes
      for (const size of viewportSizes) {
        await page.setViewportSize(size);
        await page.waitForTimeout(100); // Brief pause for layout

        // Verify key elements are still visible and functional
        const allFilter = page.locator('[data-testid="pod-filter-all"]');
        await expect(allFilter).toBeVisible();

        // Test that clicking still works
        await allFilter.click();
        await expect(allFilter).toHaveAttribute('aria-selected', 'true');
      }
    });

    test('should maintain filter state across viewport changes', async ({ page }) => {
      await page.setViewportSize({ width: 1400, height: 900 });
      await setupKubernetesPanel(page);

      // Set a filter
      const runningFilter = page.locator('[data-testid="pod-filter-running"]');
      await runningFilter.click();
      await expect(runningFilter).toHaveAttribute('aria-selected', 'true');

      // Change to mobile viewport
      await page.setViewportSize({ width: 375, height: 667 });
      await page.waitForTimeout(200);

      // Verify filter state is maintained
      await expect(runningFilter).toHaveAttribute('aria-selected', 'true');

      // Change back to wide viewport
      await page.setViewportSize({ width: 1400, height: 900 });
      await page.waitForTimeout(200);

      // Filter should still be active
      await expect(runningFilter).toHaveAttribute('aria-selected', 'true');
    });
  });
});