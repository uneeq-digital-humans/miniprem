#!/usr/bin/env node

/**
 * End-to-End Test Suite for MiniPrem Monitor
 * Combines dashboard and monitoring integration tests
 */

const DashboardTester = require('./dashboard-test');
const MonitoringTester = require('./monitoring-test');

class E2ETester {
  constructor() {
    this.dashboardTester = new DashboardTester();
    this.monitoringTester = new MonitoringTester();
  }

  async runFullTestSuite() {
    console.log('🎯 Starting Full End-to-End Test Suite');
    console.log('='.repeat(60));

    const startTime = Date.now();
    let overallSuccess = true;

    try {
      console.log('📊 Phase 1: Dashboard Functionality Tests');
      console.log('-'.repeat(40));
      const dashboardSuccess = await this.dashboardTester.runAllTests();

      console.log('\n🔌 Phase 2: Monitoring Integration Tests');
      console.log('-'.repeat(40));
      const monitoringSuccess = await this.monitoringTester.runMonitoringTests();

      overallSuccess = dashboardSuccess && monitoringSuccess;

      const duration = ((Date.now() - startTime) / 1000).toFixed(1);

      console.log('\n' + '='.repeat(60));
      console.log('🏁 FULL TEST SUITE RESULTS');
      console.log('='.repeat(60));
      console.log(`📊 Dashboard Tests: ${dashboardSuccess ? '✅ PASSED' : '❌ FAILED'}`);
      console.log(`🔌 Monitoring Tests: ${monitoringSuccess ? '✅ PASSED' : '❌ FAILED'}`);
      console.log(`⏱️  Total Duration: ${duration}s`);
      console.log('\n' + (overallSuccess ? '🎉 ALL E2E TESTS PASSED!' : '⚠️  SOME E2E TESTS FAILED'));
      console.log('='.repeat(60));

      return overallSuccess;

    } catch (error) {
      console.error('💥 E2E test suite failed with error:', error.message);
      return false;
    }
  }
}

// Run tests if called directly
if (require.main === module) {
  const e2eTester = new E2ETester();
  e2eTester.runFullTestSuite()
    .then(success => {
      process.exit(success ? 0 : 1);
    })
    .catch(error => {
      console.error('💥 Fatal error:', error);
      process.exit(1);
    });
}

module.exports = E2ETester;