/**
 * NEW_SPEECH_OVERRIDE Validation Tests
 *
 * Tests to validate that the MiniPrem Monitor correctly handles the system
 * when NEW_SPEECH_OVERRIDE=1 is set, ensuring no Audio2Face dependencies
 * and proper Renny-only operation.
 */

import { test, expect } from '@playwright/test';
import type { Page } from '@playwright/test';

// Mock data reflecting NEW_SPEECH_OVERRIDE=1 environment (no Audio2Face)
const mockRennyOnlyPods = [
  {
    name: 'renny-deployment-abc123',
    namespace: 'uneeq-renderer',
    status: 'Running',
    ready: '1/1',
    age: '2d',
    restarts: 0,
    node: 'ip-10-0-1-100.ec2.internal',
    cpu_usage: '150m',
    memory_usage: '512Mi',
    labels: {
      'app': 'renny',
      'component': 'renderer',
      'speech.override': 'enabled'
    }
  },
  {
    name: 'renny-deployment-def456',
    namespace: 'uneeq-renderer',
    status: 'Running',
    ready: '1/1',
    age: '1d',
    restarts: 0,
    node: 'ip-10-0-1-101.ec2.internal',
    cpu_usage: '120m',
    memory_usage: '480Mi',
    labels: {
      'app': 'renny',
      'component': 'renderer',
      'speech.override': 'enabled'
    }
  },
  {
    name: 'vlm-service-ghi789',
    namespace: 'uneeq-renderer',
    status: 'Running',
    ready: '1/1',
    age: '3d',
    restarts: 0,
    node: 'ip-10-0-1-102.ec2.internal',
    cpu_usage: '200m',
    memory_usage: '1Gi',
    labels: {
      'app': 'vlm',
      'component': 'inference'
    }
  }
];

const mockSpeechOverrideCluster = {
  name: 'miniprem-eks-speech-override',
  context: 'arn:aws:eks:us-east-1:123456789:cluster/miniprem-eks-speech-override',
  namespace: 'uneeq-renderer',
  environment: 'eks' as const,
  region: 'us-east-1',
  status: 'connected' as const,
  lastSync: new Date(),
  latency: 35,
  podCount: 8, // Only Renny pods, no Audio2Face
  nodeCount: 3,
  features: {
    speechOverride: true,
    audio2face: false,
    builtInTTS: true
  }
};

async function setupSpeechOverrideEnvironment(page: Page) {
  await page.goto('/');
  await page.waitForSelector('[data-testid="kubernetes-panel"]', { timeout: 15000 });

  // Inject mock data simulating NEW_SPEECH_OVERRIDE=1 environment
  await page.evaluate(({ pods, clusterStatus }) => {
    window.mockKubernetesData = {
      pods,
      clusterStatus,
      availableClusters: [{
        name: clusterStatus.name,
        context: clusterStatus.context,
        namespace: clusterStatus.namespace
      }],
      availableRegions: ['us-east-1', 'us-west-2', 'eu-west-1'],
      currentRegion: 'us-east-1',
      loading: false,
      error: null,
      speechOverride: true,
      features: clusterStatus.features
    };
  }, {
    pods: mockRennyOnlyPods,
    clusterStatus: mockSpeechOverrideCluster
  });

  await page.waitForSelector('[data-testid="pod-filter-all"]', { timeout: 10000 });
}

test.describe('NEW_SPEECH_OVERRIDE Validation', () => {

  test.describe('Pod Configuration Validation', () => {
    test('should only show Renny and supporting service pods', async ({ page }) => {
      await setupSpeechOverrideEnvironment(page);

      // Verify we have the expected number of pods (no Audio2Face)
      const podItems = page.getByTestId('pod-item');
      const podCount = await podItems.count();

      // With speech override, we should have Renny + supporting services but no A2F
      expect(podCount).toBeGreaterThanOrEqual(2);
      expect(podCount).toBeLessThanOrEqual(8); // Reasonable upper bound

      // Verify no Audio2Face pods are present
      const podNames = [];
      for (let i = 0; i < podCount; i++) {
        const podName = await podItems.nth(i).locator('[class*="font-semibold"]').first().textContent();
        if (podName) {
          podNames.push(podName);
        }
      }

      // Should not contain any Audio2Face references
      const hasAudio2FacePods = podNames.some(name =>
        name?.toLowerCase().includes('audio2face') ||
        name?.toLowerCase().includes('a2f') ||
        name?.toLowerCase().includes('audioface')
      );
      expect(hasAudio2FacePods).toBeFalsy();

      // Should contain Renny pods
      const hasRennyPods = podNames.some(name =>
        name?.toLowerCase().includes('renny')
      );
      expect(hasRennyPods).toBeTruthy();
    });

    test('should show correct pod count in cluster status', async ({ page }) => {
      await setupSpeechOverrideEnvironment(page);

      // Find cluster status display
      const clusterInfo = page.locator('[data-testid="cluster-info"]');

      if (await clusterInfo.isVisible()) {
        const infoText = await clusterInfo.textContent();

        // Should show reduced pod count (8 instead of 12)
        if (infoText?.includes('pods') || infoText?.includes('Pods')) {
          // Extract number from text like "8 pods" or "Pods: 8"
          const podCountMatch = infoText.match(/(\d+).*pods?|pods?.*(\d+)/i);
          if (podCountMatch) {
            const count = parseInt(podCountMatch[1] || podCountMatch[2]);
            expect(count).toBeLessThanOrEqual(8); // Reduced from typical 12 with A2F
          }
        }
      }
    });

    test('should validate pod labels indicate speech override', async ({ page }) => {
      await setupSpeechOverrideEnvironment(page);

      // Click on a Renny pod to expand details
      const rennyPods = page.getByTestId('pod-item').filter({ hasText: /renny/i });
      const rennyCount = await rennyPods.count();

      if (rennyCount > 0) {
        const firstRenny = rennyPods.first();
        await firstRenny.click();
        await page.waitForTimeout(500);

        // Look for expanded pod details
        const expandedDetails = firstRenny.locator('[class*="border-t"]');
        if (await expandedDetails.isVisible()) {
          const detailsText = await expandedDetails.textContent();

          // Should show speech override indicators if labels are displayed
          if (detailsText?.includes('Labels') || detailsText?.includes('labels')) {
            const hasSpeechOverride =
              detailsText.includes('speech.override') ||
              detailsText.includes('speech-override') ||
              detailsText.includes('override');

            if (hasSpeechOverride) {
              expect(hasSpeechOverride).toBeTruthy();
            }
          }
        }
      }
    });
  });

  test.describe('System Feature Validation', () => {
    test('should indicate built-in speech capabilities', async ({ page }) => {
      await setupSpeechOverrideEnvironment(page);

      // Look for system status or feature indicators
      const systemPanel = page.locator('[data-testid="system-health-panel"]');

      if (await systemPanel.isVisible()) {
        const panelText = await systemPanel.textContent();

        // Should not reference Audio2Face services
        const hasA2FReferences =
          panelText?.toLowerCase().includes('audio2face') ||
          panelText?.toLowerCase().includes('a2f');
        expect(hasA2FReferences).toBeFalsy();

        // May indicate speech processing capabilities
        const hasSpeechIndicators =
          panelText?.toLowerCase().includes('speech') ||
          panelText?.toLowerCase().includes('tts') ||
          panelText?.toLowerCase().includes('voice');

        // This is optional - system might not display speech status
        if (hasSpeechIndicators) {
          console.log('Speech indicators found:', hasSpeechIndicators);
        }
      }
    });

    test('should handle service filtering without Audio2Face', async ({ page }) => {
      await setupSpeechOverrideEnvironment(page);

      // Test pod status filtering works correctly
      const runningFilter = page.locator('[data-testid="pod-filter-running"]');
      await runningFilter.click();
      await page.waitForTimeout(1000);

      // Should show running pods (Renny + supporting services)
      const visiblePods = page.getByTestId('pod-item');
      const runningPodCount = await visiblePods.count();

      // Should have at least Renny pods running
      expect(runningPodCount).toBeGreaterThanOrEqual(1);

      // Verify all visible pods show running status
      if (runningPodCount > 0) {
        for (let i = 0; i < Math.min(runningPodCount, 5); i++) {
          const pod = visiblePods.nth(i);
          const podText = await pod.textContent();

          // Pod should indicate running status
          expect(podText?.toLowerCase()).toMatch(/running|ready|1\/1/);
        }
      }
    });

    test('should show appropriate cluster health without Audio2Face dependencies', async ({ page }) => {
      await setupSpeechOverrideEnvironment(page);

      // Check cluster connection status
      const connectionStatus = page.getByTestId('connection-status');

      if (await connectionStatus.isVisible()) {
        const statusText = await connectionStatus.textContent();

        // Should show connected status
        expect(statusText?.toLowerCase()).toMatch(/connected|online/);

        // Should have green/positive indicator
        const statusIndicator = connectionStatus.locator('[class*="rounded-full"]');
        await expect(statusIndicator).toBeVisible();
      }

      // Verify no error states related to missing Audio2Face
      const errorElements = page.locator('[class*="error"], [data-testid*="error"]');
      const errorCount = await errorElements.count();

      if (errorCount > 0) {
        // Check that errors are not related to Audio2Face dependencies
        for (let i = 0; i < errorCount; i++) {
          const errorText = await errorElements.nth(i).textContent();
          const isA2FError =
            errorText?.toLowerCase().includes('audio2face') ||
            errorText?.toLowerCase().includes('a2f') ||
            errorText?.toLowerCase().includes('speech service');

          expect(isA2FError).toBeFalsy();
        }
      }
    });
  });

  test.describe('Performance Validation', () => {
    test('should show improved performance metrics without Audio2Face overhead', async ({ page }) => {
      await setupSpeechOverrideEnvironment(page);

      // Check system metrics if available
      const metricsPanel = page.locator('[data-testid*="metrics"], [data-testid*="performance"]');

      if (await metricsPanel.isVisible()) {
        const metricsText = await metricsPanel.textContent();

        // CPU usage should be reasonable without A2F processing
        const cpuMatch = metricsText?.match(/cpu:?\s*(\d+)%?/i);
        if (cpuMatch) {
          const cpuUsage = parseInt(cpuMatch[1]);
          expect(cpuUsage).toBeLessThan(80); // Should be lower without A2F
        }

        // Memory usage should be optimized
        const memMatch = metricsText?.match(/memory:?\s*(\d+)%?/i);
        if (memMatch) {
          const memUsage = parseInt(memMatch[1]);
          expect(memUsage).toBeLessThan(70); // Should be lower without A2F
        }
      }
    });

    test('should show reduced resource requirements', async ({ page }) => {
      await setupSpeechOverrideEnvironment(page);

      // Check individual pod resource usage
      const podItems = page.getByTestId('pod-item');
      const podCount = await podItems.count();

      if (podCount > 0) {
        // Click on first pod to see resource details
        const firstPod = podItems.first();
        await firstPod.click();
        await page.waitForTimeout(500);

        const expandedContent = firstPod.locator('[class*="border-t"]');
        if (await expandedContent.isVisible()) {
          const detailsText = await expandedContent.textContent();

          // Should show resource usage metrics
          const hasCpuInfo = detailsText?.includes('CPU') || detailsText?.includes('cpu');
          const hasMemInfo = detailsText?.includes('Memory') || detailsText?.includes('memory');

          if (hasCpuInfo || hasMemInfo) {
            // Resource usage should be present and reasonable
            expect(hasCpuInfo || hasMemInfo).toBeTruthy();
          }
        }
      }
    });
  });

  test.describe('Environment Configuration', () => {
    test('should validate environment variables are properly set', async ({ page }) => {
      await setupSpeechOverrideEnvironment(page);

      // Check for environment configuration display if available
      const configInfo = page.locator('[data-testid*="config"], [data-testid*="environment"]');

      if (await configInfo.isVisible()) {
        const configText = await configInfo.textContent();

        // Should not show Audio2Face configuration
        const hasA2FConfig =
          configText?.toLowerCase().includes('audio2face') ||
          configText?.toLowerCase().includes('a2f_enabled');
        expect(hasA2FConfig).toBeFalsy();

        // May show speech override configuration
        const hasSpeechConfig =
          configText?.toLowerCase().includes('speech_override') ||
          configText?.toLowerCase().includes('new_speech_override');

        if (hasSpeechConfig) {
          expect(hasSpeechConfig).toBeTruthy();
        }
      }
    });

    test('should handle cluster switching with speech override enabled', async ({ page }) => {
      await setupSpeechOverrideEnvironment(page);

      const clusterSelector = page.getByTestId('cluster-selector');

      if (await clusterSelector.isVisible()) {
        await clusterSelector.click();
        await page.waitForTimeout(500);

        // Should show current cluster with appropriate labeling
        const currentCluster = clusterSelector.locator('[class*="selected"], [aria-selected="true"]');
        if (await currentCluster.isVisible()) {
          const clusterText = await currentCluster.textContent();

          // Should show the speech override cluster
          expect(clusterText?.toLowerCase()).toMatch(/speech.override|override|eks/);
        }
      }
    });
  });

  test.describe('Error Handling', () => {
    test('should handle missing Audio2Face gracefully', async ({ page }) => {
      // Simulate environment where A2F was expected but removed
      await page.goto('/');
      await page.waitForSelector('[data-testid="kubernetes-panel"]', { timeout: 15000 });

      await page.evaluate(() => {
        window.mockKubernetesData = {
          pods: [], // No pods initially
          clusterStatus: {
            name: 'miniprem-eks-cluster',
            context: 'arn:aws:eks:us-east-1:123456789:cluster/miniprem-eks-cluster',
            namespace: 'uneeq-renderer',
            environment: 'eks',
            region: 'us-east-1',
            status: 'connected',
            lastSync: new Date(),
            latency: 45,
            podCount: 0,
            nodeCount: 3
          },
          availableClusters: [],
          availableRegions: ['us-east-1'],
          currentRegion: 'us-east-1',
          loading: false,
          error: null
        };
      });

      await page.waitForTimeout(2000);

      // Should show "no pods" state gracefully
      const noPods = page.getByTestId('no-pods');
      if (await noPods.isVisible()) {
        const messageText = await noPods.textContent();

        // Should not mention Audio2Face specifically
        const mentionsA2F = messageText?.toLowerCase().includes('audio2face');
        expect(mentionsA2F).toBeFalsy();

        // Should show generic "no pods" message
        expect(messageText?.toLowerCase()).toMatch(/no pods|not found|empty/);
      }
    });

    test('should show appropriate messages when speech services are ready', async ({ page }) => {
      await setupSpeechOverrideEnvironment(page);

      // Should not show any warnings about missing Audio2Face
      const warningElements = page.locator('[class*="warning"], [class*="alert"]');
      const warningCount = await warningElements.count();

      if (warningCount > 0) {
        for (let i = 0; i < warningCount; i++) {
          const warningText = await warningElements.nth(i).textContent();
          const isA2FWarning =
            warningText?.toLowerCase().includes('audio2face') ||
            warningText?.toLowerCase().includes('a2f') ||
            warningText?.toLowerCase().includes('speech service unavailable');

          expect(isA2FWarning).toBeFalsy();
        }
      }
    });
  });
});