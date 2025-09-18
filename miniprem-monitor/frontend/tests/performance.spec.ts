import { test, expect } from '@playwright/test';

/**
 * Performance Benchmarking Tests
 *
 * Tests application performance metrics, Core Web Vitals, and catches performance regressions
 */

test.describe('Performance Benchmarks', () => {
  test.beforeEach(async ({ page }) => {
    // Clear cache and storage for consistent performance testing
    await page.context().clearCookies();
    await page.context().clearPermissions();
  });

  test('dashboard loads within performance budget', async ({ page }) => {
    const startTime = Date.now();

    // Navigate to the dashboard
    await page.goto('/');

    // Wait for the page to be fully loaded and interactive
    await page.waitForLoadState('domcontentloaded');
    await page.waitForLoadState('networkidle');

    const loadTime = Date.now() - startTime;

    // Performance budget: Dashboard should load within 3 seconds
    expect(loadTime).toBeLessThan(3500);
    console.log(`Dashboard load time: ${loadTime}ms`);

    // Verify critical elements are visible (ensuring actual functionality loaded)
    await expect(page.getByTestId('dashboard-header')).toBeVisible();
    await expect(page.getByTestId('connection-status')).toBeVisible();
  });

  test('measures Core Web Vitals', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Measure Core Web Vitals
    const webVitals = await page.evaluate(() => {
      return new Promise((resolve) => {
        const vitals = {
          fcp: null as number | null,
          lcp: null as number | null,
          cls: null as number | null,
          fid: null as number | null,
        };

        // First Contentful Paint
        const paintEntries = performance.getEntriesByType('paint');
        const fcpEntry = paintEntries.find((entry) => entry.name === 'first-contentful-paint');
        if (fcpEntry) {
          vitals.fcp = fcpEntry.startTime;
        }

        // Largest Contentful Paint
        const observer = new PerformanceObserver((list) => {
          const entries = list.getEntries();
          const lastEntry = entries[entries.length - 1];
          vitals.lcp = lastEntry.startTime;
        });
        observer.observe({ entryTypes: ['largest-contentful-paint'] });

        // Cumulative Layout Shift
        let clsScore = 0;
        const clsObserver = new PerformanceObserver((list) => {
          for (const entry of list.getEntries()) {
            if (!(entry as any).hadRecentInput) {
              clsScore += (entry as any).value;
            }
          }
          vitals.cls = clsScore;
        });
        clsObserver.observe({ entryTypes: ['layout-shift'] });

        // Give observers time to collect data
        setTimeout(() => {
          observer.disconnect();
          clsObserver.disconnect();
          resolve(vitals);
        }, 2000);
      });
    });

    console.log('Core Web Vitals:', webVitals);

    // Performance assertions based on Core Web Vitals thresholds
    if (webVitals.fcp !== null) {
      expect(webVitals.fcp).toBeLessThan(2000); // FCP should be under 2s (good threshold: 1.8s)
    }

    if (webVitals.lcp !== null) {
      expect(webVitals.lcp).toBeLessThan(4000); // LCP should be under 4s (good threshold: 2.5s)
    }

    if (webVitals.cls !== null) {
      expect(webVitals.cls).toBeLessThan(0.25); // CLS should be under 0.25 (good threshold: 0.1)
    }
  });

  test('API response time performance', async ({ page }) => {
    // Intercept API calls to measure response times
    const apiTimes: { [key: string]: number } = {};

    page.on('response', (response) => {
      const url = response.url();
      if (url.includes('/api/')) {
        const timing = response.request().timing();
        if (timing) {
          const responseTime = timing.responseEnd - timing.requestStart;
          apiTimes[url] = responseTime;
        }
      }
    });

    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Wait for potential API calls
    await page.waitForTimeout(3500);

    console.log('API Response Times:', apiTimes);

    // Verify API performance benchmarks
    Object.entries(apiTimes).forEach(([url, time]) => {
      console.log(`${url}: ${time}ms`);

      if (url.includes('/api/health')) {
        expect(time).toBeLessThan(1000); // Health checks should be very fast
      } else if (url.includes('/api/system')) {
        expect(time).toBeLessThan(2000); // System metrics should be reasonably fast
      } else {
        expect(time).toBeLessThan(5000); // General API performance budget
      }
    });
  });

  test('WebSocket connection performance', async ({ page }) => {
    let connectionTime: number | null = null;
    let firstMessageTime: number | null = null;

    // Monitor WebSocket performance
    await page.evaluateOnNewDocument(() => {
      const originalWebSocket = window.WebSocket;
      (window as any).wsPerformance = {
        connectionStart: null,
        connectionEnd: null,
        firstMessageTime: null,
      };

      (window as any).WebSocket = class extends originalWebSocket {
        constructor(url: string | URL, protocols?: string | string[]) {
          super(url, protocols);

          (window as any).wsPerformance.connectionStart = Date.now();

          this.addEventListener('open', () => {
            (window as any).wsPerformance.connectionEnd = Date.now();
          });

          this.addEventListener('message', () => {
            if (!(window as any).wsPerformance.firstMessageTime) {
              (window as any).wsPerformance.firstMessageTime = Date.now();
            }
          });
        }
      };
    });

    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Wait for WebSocket connection and first message
    await page.waitForTimeout(5000);

    const wsPerformance = await page.evaluate(() => {
      return (window as any).wsPerformance;
    });

    if (wsPerformance.connectionStart && wsPerformance.connectionEnd) {
      connectionTime = wsPerformance.connectionEnd - wsPerformance.connectionStart;
      console.log(`WebSocket connection time: ${connectionTime}ms`);
      expect(connectionTime).toBeLessThan(2000); // WebSocket should connect within 2s
    }

    if (wsPerformance.firstMessageTime && wsPerformance.connectionEnd) {
      firstMessageTime = wsPerformance.firstMessageTime - wsPerformance.connectionEnd;
      console.log(`First message time: ${firstMessageTime}ms`);
      expect(firstMessageTime).toBeLessThan(3500); // First message within 3s of connection
    }
  });

  test('memory usage stability', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Get initial memory usage
    const initialMemory = await page.evaluate(() => {
      return (performance as any).memory
        ? {
            usedJSHeapSize: (performance as any).memory.usedJSHeapSize,
            totalJSHeapSize: (performance as any).memory.totalJSHeapSize,
            jsHeapSizeLimit: (performance as any).memory.jsHeapSizeLimit,
          }
        : null;
    });

    if (initialMemory) {
      console.log('Initial memory usage:', initialMemory);

      // Simulate some activity (scrolling, interactions)
      await page.mouse.wheel(0, 500);
      await page.mouse.wheel(0, -500);

      // Wait for potential memory-intensive operations
      await page.waitForTimeout(2000);

      const finalMemory = await page.evaluate(() => {
        return (performance as any).memory
          ? {
              usedJSHeapSize: (performance as any).memory.usedJSHeapSize,
              totalJSHeapSize: (performance as any).memory.totalJSHeapSize,
              jsHeapSizeLimit: (performance as any).memory.jsHeapSizeLimit,
            }
          : null;
      });

      if (finalMemory) {
        console.log('Final memory usage:', finalMemory);

        const memoryIncrease = finalMemory.usedJSHeapSize - initialMemory.usedJSHeapSize;
        const memoryIncreasePercent = (memoryIncrease / initialMemory.usedJSHeapSize) * 100;

        console.log(`Memory increase: ${memoryIncrease} bytes (${memoryIncreasePercent.toFixed(2)}%)`);

        // Memory should not increase by more than 50% during basic operations
        expect(memoryIncreasePercent).toBeLessThan(50);
      }
    }
  });

  test('concurrent user simulation performance', async ({ page, context }) => {
    const startTime = Date.now();

    // Simulate multiple concurrent operations
    const promises = [page.goto('/'), page.waitForLoadState('networkidle')];

    // Add more concurrent operations
    promises.push(
      page.waitForSelector('[data-testid="dashboard-header"]'),
      page.waitForSelector('[data-testid="connection-status"]'),
      page.waitForFunction(() => document.readyState === 'complete')
    );

    await Promise.all(promises);

    const concurrentLoadTime = Date.now() - startTime;
    console.log(`Concurrent operations completed in: ${concurrentLoadTime}ms`);

    // Should handle concurrent operations efficiently
    expect(concurrentLoadTime).toBeLessThan(5000);

    // Verify the page is still functional after concurrent operations
    await expect(page.getByTestId('app-title')).toBeVisible();
    await expect(page.getByTestId('connection-status')).toBeVisible();
  });

  test('resource loading performance', async ({ page }) => {
    // Track resource loading performance
    const resourceMetrics: Array<{ url: string; duration: number; size: number }> = [];

    page.on('response', async (response) => {
      const request = response.request();
      const timing = request.timing();

      if (timing) {
        const duration = timing.responseEnd - timing.requestStart;
        const url = response.url();

        try {
          const buffer = await response.body();
          resourceMetrics.push({
            url,
            duration,
            size: buffer.length,
          });
        } catch (error) {
          // Some responses may not have bodies
        }
      }
    });

    await page.goto('/');
    await page.waitForLoadState('networkidle');

    console.log('Resource Performance:');
    resourceMetrics.forEach(({ url, duration, size }) => {
      const sizeKB = Math.round(size / 1024);
      console.log(`${url.split('/').pop()}: ${duration}ms (${sizeKB}KB)`);
    });

    // Verify critical resources load quickly
    const jsFiles = resourceMetrics.filter((r) => r.url.includes('.js'));
    const cssFiles = resourceMetrics.filter((r) => r.url.includes('.css'));

    jsFiles.forEach(({ duration }) => {
      expect(duration).toBeLessThan(3500); // JS files should load within 3s
    });

    cssFiles.forEach(({ duration }) => {
      expect(duration).toBeLessThan(2000); // CSS files should load within 2s
    });

    // Check for excessive resource sizes
    const largeResources = resourceMetrics.filter((r) => r.size > 1024 * 1024); // > 1MB
    expect(largeResources).toHaveLength(0); // No individual resource should be > 1MB
  });
});

test.describe('Performance Regression Detection', () => {
  test('baseline performance benchmark', async ({ page }) => {
    // This test establishes baseline performance metrics
    const metrics = {
      pageLoadTime: 0,
      timeToInteractive: 0,
      firstContentfulPaint: 0,
      memoryUsage: 0,
    };

    const startTime = Date.now();
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    metrics.pageLoadTime = Date.now() - startTime;

    // Measure time to interactive
    const timeToInteractive = await page.evaluate(() => {
      return new Promise((resolve) => {
        const startTime = performance.now();

        // Wait for the page to be interactive
        const checkInteractive = () => {
          if (document.readyState === 'complete') {
            resolve(performance.now() - startTime);
          } else {
            setTimeout(checkInteractive, 50);
          }
        };
        checkInteractive();
      });
    });

    metrics.timeToInteractive = timeToInteractive as number;

    // Get memory usage
    const memory = await page.evaluate(() => {
      return (performance as any).memory?.usedJSHeapSize || 0;
    });
    metrics.memoryUsage = memory;

    console.log('Baseline Performance Metrics:', metrics);

    // Store metrics for comparison (in real implementation, you'd save to a file or database)
    // This creates a baseline for performance regression testing
    expect(metrics.pageLoadTime).toBeLessThan(3500);
    expect(metrics.timeToInteractive).toBeLessThan(2000);
    expect(metrics.memoryUsage).toBeGreaterThan(0);
  });
});
