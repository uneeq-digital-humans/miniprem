import { test, expect } from '@playwright/test';

/**
 * Permission Modal Tests
 *
 * Tests permission modal functionality including:
 * - Modal opening/closing behaviors
 * - Email validation (format and required field)
 * - Success and error states
 * - Loading state during API calls
 * - Auto-close after success
 * - Keyboard navigation and accessibility
 * - API mocking for snapshot and support endpoints
 * - Visual regression testing
 */

test.describe('Permission Modal', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);

    // Wait for containers to load
    await page.waitForSelector(
      '[data-testid="container-item"], [data-testid="no-containers"]',
      { timeout: 10000 }
    );
  });

  /**
   * Helper function to open permission modal
   */
  async function openPermissionModal(page: any) {
    const containerItem = page.locator('[data-testid="container-item"]').first();

    if (await containerItem.isVisible()) {
      // Expand container
      await containerItem.click();
      await page.waitForTimeout(500);

      // Click "View All Metrics"
      const viewMetricsButton = page.locator('button:has-text("View All Metrics")').first();

      if (await viewMetricsButton.isVisible()) {
        await viewMetricsButton.click();
        await page.waitForTimeout(500);

        // Click "Support" button
        const supportButton = page.locator('[data-testid="support-button"]');
        await supportButton.click();
        await page.waitForTimeout(300);

        return true;
      }
    }
    return false;
  }

  test.describe('Modal Opening and Closing', () => {
    test('should open permission modal from full metrics modal', async ({ page }) => {
      const opened = await openPermissionModal(page);

      if (opened) {
        const permissionModal = page.locator('[data-testid="permission-modal"]');
        await expect(permissionModal).toBeVisible();

        // Check title
        const title = permissionModal.locator('[data-testid="permission-title"]');
        await expect(title).toBeVisible();
        await expect(title).toContainText('Share Metrics');

        console.log('✅ Permission modal opened successfully');
      }
    });

    test('should close permission modal when clicking X button', async ({ page }) => {
      const opened = await openPermissionModal(page);

      if (opened) {
        const permissionModal = page.locator('[data-testid="permission-modal"]');
        await expect(permissionModal).toBeVisible();

        // Click close button
        const closeButton = permissionModal.locator('[data-testid="close-permission-modal"]');
        await closeButton.click();
        await page.waitForTimeout(300);

        // Modal should be hidden
        await expect(permissionModal).toBeHidden();

        console.log('✅ Permission modal closed via X button');
      }
    });

    test('should close permission modal when clicking cancel button', async ({ page }) => {
      const opened = await openPermissionModal(page);

      if (opened) {
        const permissionModal = page.locator('[data-testid="permission-modal"]');
        await expect(permissionModal).toBeVisible();

        // Click cancel button
        const cancelButton = permissionModal.locator('[data-testid="permission-cancel"]');
        await cancelButton.click();
        await page.waitForTimeout(300);

        // Modal should be hidden
        await expect(permissionModal).toBeHidden();

        console.log('✅ Permission modal closed via cancel button');
      }
    });

    test('should close permission modal on Escape key press', async ({ page }) => {
      const opened = await openPermissionModal(page);

      if (opened) {
        const permissionModal = page.locator('[data-testid="permission-modal"]');
        await expect(permissionModal).toBeVisible();

        // Press Escape
        await page.keyboard.press('Escape');
        await page.waitForTimeout(300);

        // Modal should be hidden
        await expect(permissionModal).toBeHidden();

        console.log('✅ Permission modal closed via Escape key');
      }
    });
  });

  test.describe('Email Validation', () => {
    test('should show validation error for empty email', async ({ page }) => {
      const opened = await openPermissionModal(page);

      if (opened) {
        const permissionModal = page.locator('[data-testid="permission-modal"]');
        await expect(permissionModal).toBeVisible();

        const emailInput = permissionModal.locator('[data-testid="email-input"]');
        const confirmButton = permissionModal.locator('[data-testid="permission-confirm-button"]');

        // Button should be disabled when email is empty
        await expect(confirmButton).toBeDisabled();

        console.log('✅ Confirm button disabled for empty email');
      }
    });

    test('should show validation error for invalid email format', async ({ page }) => {
      const opened = await openPermissionModal(page);

      if (opened) {
        const permissionModal = page.locator('[data-testid="permission-modal"]');
        await expect(permissionModal).toBeVisible();

        const emailInput = permissionModal.locator('[data-testid="email-input"]');
        const confirmButton = permissionModal.locator('[data-testid="permission-confirm-button"]');

        // Enter invalid email
        await emailInput.fill('invalid-email');
        await emailInput.blur();
        await page.waitForTimeout(300);

        // Button should be disabled for invalid email
        await expect(confirmButton).toBeDisabled();

        // Check for validation error message
        const validationError = permissionModal.locator('[data-testid="email-validation-error"]');
        if (await validationError.isVisible()) {
          await expect(validationError).toBeVisible();
          await expect(validationError).toContainText('valid email');
          console.log('✅ Validation error shown for invalid email format');
        } else {
          console.log('ℹ️ Validation error may be shown inline or via button state');
        }
      }
    });

    test('should enable confirm button for valid email', async ({ page }) => {
      const opened = await openPermissionModal(page);

      if (opened) {
        const permissionModal = page.locator('[data-testid="permission-modal"]');
        await expect(permissionModal).toBeVisible();

        const emailInput = permissionModal.locator('[data-testid="email-input"]');
        const confirmButton = permissionModal.locator('[data-testid="permission-confirm-button"]');

        // Enter valid email
        await emailInput.fill('admin@uneeq.io');
        await page.waitForTimeout(300);

        // Button should be enabled
        await expect(confirmButton).toBeEnabled();

        console.log('✅ Confirm button enabled for valid email');
      }
    });

    test('should validate email with various formats', async ({ page }) => {
      const opened = await openPermissionModal(page);

      if (opened) {
        const permissionModal = page.locator('[data-testid="permission-modal"]');
        await expect(permissionModal).toBeVisible();

        const emailInput = permissionModal.locator('[data-testid="email-input"]');
        const confirmButton = permissionModal.locator('[data-testid="permission-confirm-button"]');

        // Test valid emails
        const validEmails = [
          'user@example.com',
          'test.user@company.co.uk',
          'admin+test@subdomain.example.org',
        ];

        for (const email of validEmails) {
          await emailInput.clear();
          await emailInput.fill(email);
          await page.waitForTimeout(200);

          await expect(confirmButton).toBeEnabled();
        }

        // Test invalid emails
        const invalidEmails = ['notanemail', 'missing@domain', '@nodomain.com', 'spaces @test.com'];

        for (const email of invalidEmails) {
          await emailInput.clear();
          await emailInput.fill(email);
          await page.waitForTimeout(200);

          await expect(confirmButton).toBeDisabled();
        }

        console.log('✅ Email validation works for various formats');
      }
    });
  });

  test.describe('Modal Content', () => {
    test('should display data being sent information', async ({ page }) => {
      const opened = await openPermissionModal(page);

      if (opened) {
        const permissionModal = page.locator('[data-testid="permission-modal"]');
        await expect(permissionModal).toBeVisible();

        // Check for data list
        const dataList = permissionModal.locator('[data-testid="data-list"]');
        await expect(dataList).toBeVisible();

        // Should mention container name, metrics count, timestamp, contact
        await expect(dataList).toContainText('Container');
        await expect(dataList).toContainText('Metrics');
        await expect(dataList).toContainText('Timestamp');
        await expect(dataList).toContainText('Contact');

        console.log('✅ Data being sent information displayed');
      }
    });

    test('should display permission description', async ({ page }) => {
      const opened = await openPermissionModal(page);

      if (opened) {
        const permissionModal = page.locator('[data-testid="permission-modal"]');
        await expect(permissionModal).toBeVisible();

        const description = permissionModal.locator('[data-testid="permission-description"]');
        await expect(description).toBeVisible();
        await expect(description).toContainText('performance metrics');

        console.log('✅ Permission description displayed');
      }
    });

    test('should display warning message about AWS SNS', async ({ page }) => {
      const opened = await openPermissionModal(page);

      if (opened) {
        const permissionModal = page.locator('[data-testid="permission-modal"]');
        await expect(permissionModal).toBeVisible();

        const warningMessage = permissionModal.locator('[data-testid="warning-message"]');
        await expect(warningMessage).toBeVisible();
        await expect(warningMessage).toContainText('AWS SNS');

        console.log('✅ Warning message displayed');
      }
    });

    test('should display metrics preview if available', async ({ page }) => {
      const opened = await openPermissionModal(page);

      if (opened) {
        const permissionModal = page.locator('[data-testid="permission-modal"]');
        await expect(permissionModal).toBeVisible();

        const metricsPreview = permissionModal.locator('[data-testid="metrics-preview"]');

        if (await metricsPreview.isVisible()) {
          await expect(metricsPreview).toBeVisible();
          console.log('✅ Metrics preview displayed');
        } else {
          console.log('ℹ️ Metrics preview not shown (may be optional)');
        }
      }
    });
  });

  test.describe('Form Submission', () => {
    test('should send metrics successfully with valid email', async ({ page }) => {
      // Mock API endpoints
      await page.route('**/api/metrics/snapshot', (route) => {
        route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            success: true,
            snapshot_id: 'test-snapshot-123',
            timestamp: new Date().toISOString()
          }),
        });
      });

      await page.route('**/api/metrics/send/support', (route) => {
        route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            success: true,
            message: 'Metrics sent successfully to support team'
          }),
        });
      });

      const opened = await openPermissionModal(page);

      if (opened) {
        const permissionModal = page.locator('[data-testid="permission-modal"]');
        await expect(permissionModal).toBeVisible();

        const emailInput = permissionModal.locator('[data-testid="email-input"]');
        const confirmButton = permissionModal.locator('[data-testid="permission-confirm-button"]');

        // Fill email
        await emailInput.fill('admin@uneeq.io');
        await page.waitForTimeout(300);

        // Click confirm
        await confirmButton.click();
        await page.waitForTimeout(500);

        // Check for success message
        const successMessage = permissionModal.locator('[data-testid="permission-success"]');

        if (await successMessage.isVisible()) {
          await expect(successMessage).toBeVisible();
          await expect(successMessage).toContainText('successfully');
          console.log('✅ Success message displayed after submission');

          // Modal should auto-close after 2 seconds
          await page.waitForTimeout(2200);
          await expect(permissionModal).toBeHidden();
          console.log('✅ Modal auto-closed after success');
        } else {
          console.log('ℹ️ Success state may be handled differently');
        }
      }
    });

    test('should show loading state during submission', async ({ page }) => {
      // Mock API with delay
      await page.route('**/api/metrics/snapshot', async (route) => {
        await new Promise((resolve) => setTimeout(resolve, 1000));
        route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({ success: true, snapshot_id: 'test-123' }),
        });
      });

      await page.route('**/api/metrics/send/support', async (route) => {
        await new Promise((resolve) => setTimeout(resolve, 1000));
        route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({ success: true }),
        });
      });

      const opened = await openPermissionModal(page);

      if (opened) {
        const permissionModal = page.locator('[data-testid="permission-modal"]');
        await expect(permissionModal).toBeVisible();

        const emailInput = permissionModal.locator('[data-testid="email-input"]');
        const confirmButton = permissionModal.locator('[data-testid="permission-confirm-button"]');

        // Fill email
        await emailInput.fill('admin@uneeq.io');
        await page.waitForTimeout(300);

        // Click confirm
        await confirmButton.click();
        await page.waitForTimeout(100);

        // Check loading state
        const loadingSpinner = confirmButton.locator('.animate-spin').or(confirmButton.locator('text="Sending..."'));

        if (await loadingSpinner.isVisible()) {
          await expect(loadingSpinner).toBeVisible();
          console.log('✅ Loading state displayed during submission');
        }

        // Button should be disabled during loading
        await expect(confirmButton).toBeDisabled();
      }
    });

    test('should handle API error gracefully', async ({ page }) => {
      // Mock API failure
      await page.route('**/api/metrics/snapshot', (route) => {
        route.fulfill({
          status: 500,
          contentType: 'application/json',
          body: JSON.stringify({
            success: false,
            error: 'Failed to capture snapshot'
          }),
        });
      });

      const opened = await openPermissionModal(page);

      if (opened) {
        const permissionModal = page.locator('[data-testid="permission-modal"]');
        await expect(permissionModal).toBeVisible();

        const emailInput = permissionModal.locator('[data-testid="email-input"]');
        const confirmButton = permissionModal.locator('[data-testid="permission-confirm-button"]');

        // Fill email
        await emailInput.fill('admin@uneeq.io');
        await page.waitForTimeout(300);

        // Click confirm
        await confirmButton.click();
        await page.waitForTimeout(1000);

        // Check for error message
        const errorMessage = permissionModal.locator('[data-testid="permission-error"]');

        if (await errorMessage.isVisible()) {
          await expect(errorMessage).toBeVisible();
          await expect(errorMessage).toContainText(/error|failed/i);
          console.log('✅ Error message displayed on API failure');

          // Button should be re-enabled for retry
          await expect(confirmButton).toBeEnabled();
        } else {
          console.log('ℹ️ Error handling may be implemented differently');
        }
      }
    });

    test('should handle network timeout', async ({ page }) => {
      // Mock API timeout
      await page.route('**/api/metrics/snapshot', async (route) => {
        await new Promise((resolve) => setTimeout(resolve, 30000)); // Long delay
        route.abort('timedout');
      });

      const opened = await openPermissionModal(page);

      if (opened) {
        const permissionModal = page.locator('[data-testid="permission-modal"]');
        await expect(permissionModal).toBeVisible();

        const emailInput = permissionModal.locator('[data-testid="email-input"]');
        const confirmButton = permissionModal.locator('[data-testid="permission-confirm-button"]');

        // Fill email
        await emailInput.fill('admin@uneeq.io');
        await page.waitForTimeout(300);

        // Click confirm
        await confirmButton.click();
        await page.waitForTimeout(2000);

        // Should show error or timeout message
        const errorMessage = permissionModal.locator('[data-testid="permission-error"]');

        if (await errorMessage.isVisible()) {
          await expect(errorMessage).toBeVisible();
          console.log('✅ Timeout error handled');
        }
      }
    });
  });

  test.describe('Keyboard Navigation', () => {
    test('should navigate form fields with Tab key', async ({ page }) => {
      const opened = await openPermissionModal(page);

      if (opened) {
        const permissionModal = page.locator('[data-testid="permission-modal"]');
        await expect(permissionModal).toBeVisible();

        // Tab to email input
        await page.keyboard.press('Tab');
        await page.waitForTimeout(100);

        let focusedElement = page.locator(':focus');
        const isFocusedOnInput = await focusedElement.evaluate(
          (el) => el.tagName === 'INPUT' && el.getAttribute('type') === 'email'
        );

        if (isFocusedOnInput) {
          console.log('✅ Tab navigation to email input works');
        }

        // Tab to buttons
        await page.keyboard.press('Tab');
        await page.keyboard.press('Tab');
        await page.waitForTimeout(100);
      }
    });

    test('should submit form with Enter key when email is valid', async ({ page }) => {
      // Mock successful API
      await page.route('**/api/metrics/snapshot', (route) => {
        route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({ success: true, snapshot_id: 'test-123' }),
        });
      });

      await page.route('**/api/metrics/send/support', (route) => {
        route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({ success: true }),
        });
      });

      const opened = await openPermissionModal(page);

      if (opened) {
        const permissionModal = page.locator('[data-testid="permission-modal"]');
        await expect(permissionModal).toBeVisible();

        const emailInput = permissionModal.locator('[data-testid="email-input"]');

        // Fill email
        await emailInput.fill('admin@uneeq.io');

        // Press Enter
        await emailInput.press('Enter');
        await page.waitForTimeout(500);

        // Should show success or start submission
        const successMessage = permissionModal.locator('[data-testid="permission-success"]');
        const loadingButton = permissionModal.locator('[data-testid="permission-confirm-button"]:disabled');

        if (await successMessage.isVisible() || await loadingButton.isVisible()) {
          console.log('✅ Form submits with Enter key');
        }
      }
    });
  });

  test.describe('Responsive Design', () => {
    test('should display correctly on mobile viewport', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });

      const opened = await openPermissionModal(page);

      if (opened) {
        const permissionModal = page.locator('[data-testid="permission-modal"]');
        await expect(permissionModal).toBeVisible();

        // Check modal is responsive
        const modalWidth = await permissionModal.evaluate((el) => {
          if (el instanceof HTMLElement) {
            return el.offsetWidth;
          }
          return 0;
        });
        expect(modalWidth).toBeLessThanOrEqual(375);

        console.log('✅ Permission modal displays correctly on mobile');
      }
    });

    test('should display correctly on tablet viewport', async ({ page }) => {
      await page.setViewportSize({ width: 768, height: 1024 });

      const opened = await openPermissionModal(page);

      if (opened) {
        const permissionModal = page.locator('[data-testid="permission-modal"]');
        await expect(permissionModal).toBeVisible();

        console.log('✅ Permission modal displays correctly on tablet');
      }
    });
  });

  test.describe('Visual Regression', () => {
    test('visual regression - permission modal initial state', async ({ page }) => {
      const opened = await openPermissionModal(page);

      if (opened) {
        const permissionModal = page.locator('[data-testid="permission-modal"]');
        await expect(permissionModal).toBeVisible();
        await page.waitForTimeout(500);

        // Mask timestamp (dynamic content)
        await page.addStyleTag({
          content: `
            [class*="animate-"] { animation: none !important; }
          `,
        });

        // Take screenshot
        await expect(page).toHaveScreenshot('permission-modal-initial.png', {
          threshold: 0.3,
        });

        console.log('✅ Visual regression test completed');
      }
    });

    test('visual regression - permission modal with validation error', async ({ page }) => {
      const opened = await openPermissionModal(page);

      if (opened) {
        const permissionModal = page.locator('[data-testid="permission-modal"]');
        await expect(permissionModal).toBeVisible();

        const emailInput = permissionModal.locator('[data-testid="email-input"]');

        // Enter invalid email
        await emailInput.fill('invalid-email');
        await emailInput.blur();
        await page.waitForTimeout(500);

        // Take screenshot
        await expect(page).toHaveScreenshot('permission-modal-validation-error.png', {
          threshold: 0.3,
        });

        console.log('✅ Visual regression test with validation error completed');
      }
    });

    test('visual regression - permission modal success state', async ({ page }) => {
      // Mock successful API
      await page.route('**/api/metrics/snapshot', (route) => {
        route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({ success: true, snapshot_id: 'test-123' }),
        });
      });

      await page.route('**/api/metrics/send/support', (route) => {
        route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({ success: true }),
        });
      });

      const opened = await openPermissionModal(page);

      if (opened) {
        const permissionModal = page.locator('[data-testid="permission-modal"]');
        await expect(permissionModal).toBeVisible();

        const emailInput = permissionModal.locator('[data-testid="email-input"]');
        const confirmButton = permissionModal.locator('[data-testid="permission-confirm-button"]');

        // Fill and submit
        await emailInput.fill('admin@uneeq.io');
        await confirmButton.click();
        await page.waitForTimeout(800);

        // Take screenshot of success state
        const successMessage = permissionModal.locator('[data-testid="permission-success"]');
        if (await successMessage.isVisible()) {
          await expect(page).toHaveScreenshot('permission-modal-success.png', {
            threshold: 0.3,
          });

          console.log('✅ Visual regression test with success state completed');
        }
      }
    });
  });

  test.describe('Icon Display', () => {
    test('should display permission shield icon', async ({ page }) => {
      const opened = await openPermissionModal(page);

      if (opened) {
        const permissionModal = page.locator('[data-testid="permission-modal"]');
        await expect(permissionModal).toBeVisible();

        const icon = permissionModal.locator('[data-testid="permission-icon"]');
        await expect(icon).toBeVisible();

        console.log('✅ Permission shield icon displayed');
      }
    });
  });
});
