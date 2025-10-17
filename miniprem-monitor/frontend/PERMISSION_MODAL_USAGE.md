# PermissionModal Usage Example

## Integration Example

```tsx
import { useState } from 'react';
import { PermissionModal } from '@/components/PermissionModal';

function FullMetricsModal() {
  const [showPermissionModal, setShowPermissionModal] = useState(false);
  const [selectedContainer, setSelectedContainer] = useState<string>('');
  const [metricsData, setMetricsData] = useState<any>(null);

  const handleSendToSupport = async (email: string) => {
    // Send metrics via API
    const response = await fetch('/api/metrics/send-to-support', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        containerName: selectedContainer,
        email: email,
        metrics: metricsData,
        timestamp: new Date().toISOString()
      })
    });

    if (!response.ok) {
      throw new Error('Failed to send metrics to support');
    }

    return response.json();
  };

  return (
    <>
      {/* Trigger button in your UI */}
      <button onClick={() => setShowPermissionModal(true)}>
        Send to Support
      </button>

      {/* Permission Modal */}
      <PermissionModal
        isOpen={showPermissionModal}
        onClose={() => setShowPermissionModal(false)}
        onConfirm={handleSendToSupport}
        containerName={selectedContainer}
        metricsPreview={{
          gpu_percent: metricsData?.gpu_percent,
          cpu_percent: metricsData?.cpu_percent,
          memory_percent: metricsData?.memory_percent
        }}
      />
    </>
  );
}
```

## Props Interface

```typescript
interface PermissionModalProps {
  isOpen: boolean;              // Controls modal visibility
  onClose: () => void;          // Called when user cancels or closes
  onConfirm: (email: string) => Promise<void>;  // Called when user confirms with email
  containerName: string;        // Name of container being reported
  metricsPreview?: {           // Optional metrics preview
    gpu_percent?: number;
    cpu_percent?: number;
    memory_percent?: number;
  };
}
```

## Features

✅ **Email Validation**
- Required field
- RFC 5322 compliant regex validation
- Real-time validation feedback
- HTML5 autocomplete support

✅ **Loading States**
- Disabled inputs during submission
- Spinner animation
- Button text changes to "Sending..."
- Prevents double-submission

✅ **Success Handling**
- Green success message
- Auto-closes after 2 seconds
- Visual checkmark confirmation

✅ **Error Handling**
- Error message display
- Dismissible error banner
- Allows retry without closing modal
- Preserves email input on error

✅ **Accessibility**
- Keyboard navigation (Tab/Shift+Tab)
- Escape key to close
- Enter key to submit
- Focus trap within modal
- ARIA labels for screen readers
- Proper semantic HTML

✅ **Responsive Design**
- Mobile-friendly layout
- Max-width constraint (lg)
- Centered positioning
- Touch-friendly buttons

✅ **Dark Mode Support**
- All elements styled for dark mode
- Uses Tailwind dark: variant
- Consistent with existing modals

## Data-testid Attributes for Testing

```typescript
// Modal container
data-testid="permission-modal"

// Header elements
data-testid="permission-icon"
data-testid="permission-title"
data-testid="close-permission-modal"

// Content
data-testid="permission-description"
data-testid="data-list"
data-testid="metrics-preview"
data-testid="warning-message"

// Form
data-testid="email-input"
data-testid="email-validation-error"

// State messages
data-testid="permission-error"
data-testid="permission-success"

// Actions
data-testid="permission-cancel"
data-testid="permission-confirm-button"
```

## Example Playwright Test

```typescript
import { test, expect } from '@playwright/test';

test.describe('PermissionModal', () => {
  test('should validate email and send metrics', async ({ page }) => {
    await page.goto('/');
    
    // Open modal (adjust selector based on your trigger)
    await page.click('[data-testid="send-to-support-button"]');
    
    // Modal should be visible
    await expect(page.locator('[data-testid="permission-modal"]')).toBeVisible();
    
    // Confirm button should be disabled initially
    await expect(page.locator('[data-testid="permission-confirm-button"]')).toBeDisabled();
    
    // Enter invalid email
    await page.fill('[data-testid="email-input"]', 'invalid-email');
    await page.locator('[data-testid="email-input"]').blur();
    await expect(page.locator('[data-testid="email-validation-error"]')).toBeVisible();
    
    // Enter valid email
    await page.fill('[data-testid="email-input"]', 'test@example.com');
    await expect(page.locator('[data-testid="permission-confirm-button"]')).toBeEnabled();
    
    // Submit
    await page.click('[data-testid="permission-confirm-button"]');
    
    // Success message should appear
    await expect(page.locator('[data-testid="permission-success"]')).toBeVisible();
    
    // Modal should auto-close after 2 seconds
    await page.waitForTimeout(2500);
    await expect(page.locator('[data-testid="permission-modal"]')).not.toBeVisible();
  });
  
  test('should handle escape key to close', async ({ page }) => {
    await page.goto('/');
    await page.click('[data-testid="send-to-support-button"]');
    
    await expect(page.locator('[data-testid="permission-modal"]')).toBeVisible();
    
    // Press Escape
    await page.keyboard.press('Escape');
    
    await expect(page.locator('[data-testid="permission-modal"]')).not.toBeVisible();
  });
});
```

## Styling Notes

- Uses existing CSS classes from `globals.css`:
  - `.card` - Modal card styling
  - `.btn-secondary` - Cancel button
  - `.input-field` - Email input styling
  - `.border-surface` - Consistent borders
  - Dark mode utilities (text-primary, text-secondary, etc.)

- Custom gradient for confirm button matches AwsSsoModal:
  - `from-[#FF6B35] to-[#00A9CE]`

- Icons from lucide-react:
  - Shield (main icon)
  - Database (data section)
  - Clock (timestamp)
  - Mail (email input)
  - Send (confirm button)
  - AlertCircle (warnings/errors)
  - CheckCircle (success)
  - Loader2 (loading state)
