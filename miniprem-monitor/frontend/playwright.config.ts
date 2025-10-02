import { defineConfig, devices } from '@playwright/test';

/**
 * MiniPrem Monitor - Playwright Test Configuration
 *
 * This configuration is optimized for testing the real-time monitoring dashboard
 * with WebSocket connections, API integrations, and component interactions.
 */

export default defineConfig({
  testDir: './tests',

  /* Test timeout configuration for monitoring operations */
  timeout: 35000,
  expect: {
    timeout: 10000,
    // Visual comparison threshold
    toHaveScreenshot: {
      threshold: 0.3, // Allow small differences (increased for better stability)
      animations: 'disabled', // Disable animations in screenshots
    },
    toMatchSnapshot: {
      threshold: 0.3,
    },
  },

  /* Run tests in files in parallel */
  fullyParallel: true,

  /* Fail the build on CI if you accidentally left test.only in the source code. */
  forbidOnly: !!process.env.CI,

  /* Retry on CI only - monitoring tests can be flaky due to network/timing */
  retries: process.env.CI ? 2 : 1,

  /* Opt out of parallel tests on CI due to WebSocket connection limits */
  workers: process.env.CI ? 1 : 2,

  /* Reporter configuration */
  reporter: [['html'], ['json', { outputFile: 'test-results/results.json' }], process.env.CI ? ['github'] : ['list']],

  /* Global test setup */
  globalSetup: require.resolve('./tests/global-setup.ts'),

  /* Shared settings for all projects */
  use: {
    /* Base URL for the frontend application */
    baseURL: 'http://localhost:3001',

    /* Backend API URL for direct API testing - removed to prevent CORS issues with font loading */
    // extraHTTPHeaders: {
    //   'X-Test-Backend-URL': 'http://localhost:8000',
    // },

    /* Collect trace and screenshots on failure for debugging */
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',

    /* Ignore HTTPS errors for local development */
    ignoreHTTPSErrors: true,

    /* Disable animations for more stable tests */
    // reducedMotion: 'reduce', // Removing as this may not be supported

    /* Set viewport for consistent testing */
    viewport: { width: 1920, height: 1080 },

    /* Configure visual testing */
    launchOptions: {
      args: [
        '--font-render-hinting=none', // Consistent font rendering
        '--disable-font-subpixel-positioning', // Consistent font rendering across platforms
      ],
    },
  },

  /* Projects for different testing scenarios */
  projects: [
    {
      name: 'setup',
      testMatch: '**/setup.spec.ts',
      teardown: 'cleanup',
    },

    /* Main functional tests on Chrome */
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
      // dependencies: ['setup'], // Temporarily disabled for testing without backend
    },

    /* Cross-browser testing for critical paths */
    {
      name: 'firefox',
      use: { ...devices['Desktop Firefox'] },
      dependencies: ['setup'],
      testIgnore: ['**/websocket.spec.ts'], // Firefox WebSocket behavior can differ
    },

    /* Mobile responsive testing */
    {
      name: 'mobile',
      use: { ...devices['Pixel 5'] },
      dependencies: ['setup'],
      testMatch: ['**/responsive.spec.ts', '**/dashboard.spec.ts'],
    },

    /* Cleanup after all tests */
    {
      name: 'cleanup',
      testMatch: '**/cleanup.spec.ts',
    },
  ],

  /* Run local development servers before tests */
  webServer: [
    {
      command: 'PORT=3001 npm run dev',
      url: 'http://localhost:3001',
      reuseExistingServer: !process.env.CI,
      timeout: 120000,
      stdout: 'pipe',
      stderr: 'pipe',
    },
    // Note: Backend server should be started separately via setup script
  ],

  /* Output directory for test results */
  outputDir: 'test-results/',
});
