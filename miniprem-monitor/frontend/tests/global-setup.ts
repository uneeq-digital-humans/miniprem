import { chromium, FullConfig } from '@playwright/test';

/**
 * Global test setup for MiniPrem Monitor
 *
 * Verifies backend connectivity and prepares test environment
 */
async function globalSetup(config: FullConfig) {
  console.log('🚀 MiniPrem Monitor - Global Test Setup');

  const browser = await chromium.launch();
  const page = await browser.newPage();

  try {
    // Check if backend is accessible
    console.log('🔍 Checking backend connectivity...');
    const backendUrl = 'http://localhost:8000';

    try {
      const response = await page.request.get(`${backendUrl}/api/health`);
      if (response.ok()) {
        console.log('✅ Backend is accessible');
      } else {
        console.log(`⚠️ Backend responded with status: ${response.status()}`);
      }
    } catch (error) {
      console.log('❌ Backend not accessible - some tests may fail');
      console.log('   Make sure the backend is running on localhost:8000');
    }

    // Check if frontend builds successfully
    console.log('🔍 Checking frontend accessibility...');
    try {
      await page.goto('http://localhost:3001', { waitUntil: 'domcontentloaded', timeout: 60000 });
      console.log('✅ Frontend is accessible');
    } catch (error) {
      console.log('❌ Frontend not accessible');
      throw new Error('Frontend application is not running. Start with: npm run dev');
    }

    // Create test results directory
    const fs = require('fs');
    const path = require('path');
    const testResultsDir = path.join(process.cwd(), 'test-results');
    if (!fs.existsSync(testResultsDir)) {
      fs.mkdirSync(testResultsDir, { recursive: true });
      console.log('📁 Created test-results directory');
    }
  } finally {
    await browser.close();
  }

  console.log('✅ Global setup completed');
}

export default globalSetup;
