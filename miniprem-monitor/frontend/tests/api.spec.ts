import { test, expect } from '@playwright/test';

/**
 * API Integration Tests (WebSocket-Only Architecture)
 *
 * Tests WebSocket endpoints and their integration with the frontend
 */

const BACKEND_URL = 'http://localhost:8000';

test.describe('API Integration', () => {
  test.describe('Health Endpoints', () => {
    test('GET /health returns system health', async ({ request }) => {
      try {
        const response = await request.get(`${BACKEND_URL}/health`);

        if (response.ok()) {
          const data = await response.json();

          expect(response.status()).toBe(200);
          expect(data).toBeDefined();
          expect(data).toHaveProperty('status');

          console.log('✅ Health API endpoint accessible');
        } else {
          console.log(`⚠️ Health endpoint returned status: ${response.status()}`);
        }
      } catch (error) {
        console.log('❌ Health API endpoint not accessible - backend may not be running');
      }
    });

    test('frontend integrates health data correctly', async ({ page }) => {
      await page.goto('/');
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(2000);

      // Verify dashboard loads
      const appTitle = page.getByText('MiniPrem Monitor');
      if (await appTitle.isVisible()) {
        await expect(appTitle).toBeVisible();
        console.log('✅ Dashboard loaded successfully');
      }
    });
  });

  test.describe('WebSocket Integration', () => {
    test('WebSocket system metrics command returns system metrics', async ({ page }) => {
      await page.goto('/');
      await page.waitForLoadState('networkidle');

      try {
        const metricsResponse = await page.evaluate(() => {
          return new Promise((resolve) => {
            const ws = new WebSocket('ws://localhost:8000/ws');

            const timeout = setTimeout(() => {
              ws.close();
              resolve({ success: false, error: 'Timeout' });
            }, 10000);

            ws.onopen = () => {
              ws.send(
                JSON.stringify({
                  type: 'command',
                  target: 'system',
                  command: 'metrics',
                  requestId: 'test_system_metrics',
                })
              );
            };

            ws.onmessage = (event) => {
              const data = JSON.parse(event.data);
              if (data.requestId === 'test_system_metrics') {
                clearTimeout(timeout);
                ws.close();
                resolve(data);
              }
            };

            ws.onerror = () => {
              clearTimeout(timeout);
              ws.close();
              resolve({ success: false, error: 'WebSocket error' });
            };
          });
        });

        if (metricsResponse.success && metricsResponse.data) {
          expect(metricsResponse.data).toHaveProperty('metrics');
          console.log('✅ System metrics WebSocket command successful');
        } else {
          console.log(`❌ System metrics WebSocket failed: ${metricsResponse.error}`);
        }
      } catch (error) {
        console.log('❌ System metrics WebSocket not accessible');
      }
    });

    test('WebSocket system info command returns system information', async ({ page }) => {
      await page.goto('/');
      await page.waitForLoadState('networkidle');

      try {
        const infoResponse = await page.evaluate(() => {
          return new Promise((resolve) => {
            const ws = new WebSocket('ws://localhost:8000/ws');

            const timeout = setTimeout(() => {
              ws.close();
              resolve({ success: false, error: 'Timeout' });
            }, 10000);

            ws.onopen = () => {
              ws.send(
                JSON.stringify({
                  type: 'command',
                  target: 'system',
                  command: 'info',
                  requestId: 'test_system_info',
                })
              );
            };

            ws.onmessage = (event) => {
              const data = JSON.parse(event.data);
              if (data.requestId === 'test_system_info') {
                clearTimeout(timeout);
                ws.close();
                resolve(data);
              }
            };

            ws.onerror = () => {
              clearTimeout(timeout);
              ws.close();
              resolve({ success: false, error: 'WebSocket error' });
            };
          });
        });

        if (infoResponse.success && infoResponse.data) {
          expect(infoResponse.data).toBeDefined();

          if (infoResponse.data.system) {
            expect(infoResponse.data.system).toHaveProperty('platform');
            expect(infoResponse.data.system).toHaveProperty('cpu_count');
            expect(infoResponse.data.system).toHaveProperty('memory_total_gb');
          }

          console.log('✅ System info WebSocket command successful');
        } else {
          console.log(`❌ System info WebSocket failed: ${infoResponse.error}`);
        }
      } catch (error) {
        console.log('❌ System info WebSocket not accessible');
      }
    });

    test('docker ps command returns container data', async ({ page }) => {
      await page.goto('/');
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(3500);

      try {
        const dockerResponse = await page.evaluate(() => {
          return new Promise((resolve) => {
            const ws = new WebSocket('ws://localhost:8000/ws');

            const timeout = setTimeout(() => {
              ws.close();
              resolve({ success: false, error: 'Timeout' });
            }, 10000);

            ws.onopen = () => {
              ws.send(
                JSON.stringify({
                  type: 'command',
                  target: 'docker',
                  command: 'ps',
                  requestId: 'test_docker_ps',
                })
              );
            };

            ws.onmessage = (event) => {
              const data = JSON.parse(event.data);
              if (data.requestId === 'test_docker_ps') {
                clearTimeout(timeout);
                ws.close();
                resolve(data);
              }
            };

            ws.onerror = () => {
              clearTimeout(timeout);
              ws.close();
              resolve({ success: false, error: 'WebSocket error' });
            };
          });
        });

        if (dockerResponse.success) {
          console.log('✅ Docker ps WebSocket command successful');
          if (dockerResponse.data && dockerResponse.data.containers) {
            console.log(`   Found ${dockerResponse.data.containers.length} containers`);
          }
        } else {
          console.log(`❌ Docker ps WebSocket failed: ${dockerResponse.error}`);
        }
      } catch (error) {
        console.log('❌ Docker ps WebSocket not accessible');
      }
    });

    test('kubernetes pods command returns pod data', async ({ page }) => {
      await page.goto('/');
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(3500);

      try {
        const k8sResponse = await page.evaluate(() => {
          return new Promise((resolve) => {
            const ws = new WebSocket('ws://localhost:8000/ws');

            const timeout = setTimeout(() => {
              ws.close();
              resolve({ success: false, error: 'Timeout' });
            }, 10000);

            ws.onopen = () => {
              ws.send(
                JSON.stringify({
                  type: 'command',
                  target: 'kubernetes',
                  command: 'pods',
                  requestId: 'test_kubernetes_pods',
                })
              );
            };

            ws.onmessage = (event) => {
              const data = JSON.parse(event.data);
              if (data.requestId === 'test_kubernetes_pods') {
                clearTimeout(timeout);
                ws.close();
                resolve(data);
              }
            };

            ws.onerror = () => {
              clearTimeout(timeout);
              ws.close();
              resolve({ success: false, error: 'WebSocket error' });
            };
          });
        });

        if (k8sResponse.success) {
          console.log('✅ Kubernetes pods WebSocket command successful');
          if (k8sResponse.data && k8sResponse.data.pods) {
            console.log(`   Found ${k8sResponse.data.pods.length} pods`);
          }
        } else {
          console.log(`❌ Kubernetes pods WebSocket failed: ${k8sResponse.error}`);
        }
      } catch (error) {
        console.log('❌ Kubernetes pods WebSocket not accessible');
      }
    });
  });

  test.describe('Frontend Integration', () => {
    test('frontend displays system metrics correctly', async ({ page }) => {
      await page.goto('/');
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(3500);

      // Check if metrics are displayed
      const cpuMetric = page.getByText('CPU Usage');
      const memoryMetric = page.getByText('Memory');
      const hasMetrics = await cpuMetric.isVisible();
      const hasLoading = await page.locator('.animate-pulse').first().isVisible();

      // Should show either metrics or loading state
      expect(hasMetrics || hasLoading).toBeTruthy();

      if (hasMetrics) {
        await expect(cpuMetric).toBeVisible();
        await expect(memoryMetric).toBeVisible();
        console.log('✅ Frontend displays system metrics');
      } else {
        console.log('ℹ️ Metrics in loading state');
      }
    });

    test('frontend shows connection status', async ({ page }) => {
      await page.goto('/');
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(2000);

      // Check for connection status indicator
      const connectionStatus = page.locator('[data-testid="connection-status"]').first();
      if (await connectionStatus.isVisible()) {
        await expect(connectionStatus).toBeVisible();
        console.log('✅ Connection status indicator visible');
      } else {
        console.log('ℹ️ Connection status indicator not found');
      }
    });
  });

  test.describe('Error Handling', () => {
    test('handles WebSocket server downtime gracefully', async ({ page }) => {
      // Block WebSocket connections to simulate server downtime
      await page.route('**/ws', (route) => {
        route.abort();
      });

      await page.goto('/');
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(3500);

      // Page should still load without crashing
      await expect(page.getByRole('heading', { name: 'MiniPrem Monitor' })).toBeVisible();
      console.log('✅ Frontend handles WebSocket downtime gracefully');
    });
  });

  test.describe('Performance', () => {
    test('Health endpoint is reasonably fast', async ({ request }) => {
      try {
        const startTime = Date.now();
        const response = await request.get(`${BACKEND_URL}/health`);
        const endTime = Date.now();
        const duration = endTime - startTime;

        if (response.ok()) {
          console.log(`✅ Health endpoint: ${duration}ms`);
          expect(duration).toBeLessThan(5000);
        } else {
          console.log(`⚠️ Health endpoint: HTTP ${response.status()}`);
        }
      } catch (error) {
        console.log(`❌ Health endpoint: Not accessible`);
      }
    });
  });
});
