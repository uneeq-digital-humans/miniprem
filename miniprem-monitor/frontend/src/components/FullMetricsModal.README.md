# FullMetricsModal Component

Comprehensive metrics dashboard modal displaying all 22 Prometheus metrics with real-time updates.

## 📁 File Location

`/Users/tyler/Software_Development/miniprem-2025/miniprem-monitor/frontend/src/components/FullMetricsModal.tsx`

## 🎯 Features

### Core Functionality
- ✅ Full-screen modal overlay with gradient header
- ✅ All 22 Prometheus metrics displayed and organized
- ✅ Real-time update indicator with timestamp
- ✅ Color-coded metric cards (green/yellow/red based on thresholds)
- ✅ Snapshot export functionality
- ✅ Send to support integration
- ✅ Responsive grid layout (1/2/4 columns)
- ✅ Smooth animations with framer-motion
- ✅ Dark mode support

### Metric Categories (4 sections)

#### 📊 Session Metrics (4 metrics)
- Total Sessions
- Successful Sessions
- Failed Sessions
- Frames Rendered

#### ⚡ Performance Metrics (5 metrics)
- Response Time (p50, p90, p99)
- NLP Response Time
- A2F Response Time

#### ⏱️ Frame Timing (4 metrics)
- GPU Frame Time
- Render Time
- Game Thread Time
- Total Frame Time

#### 💻 System Metrics (4 metrics)
- GPU Usage
- CPU Usage
- Memory Usage
- Power Draw

## 📦 Props Interface

```typescript
interface FullMetricsModalProps {
  containerName: string;              // Display name of container
  metrics: PrometheusMetrics;        // Full metrics object
  onClose: () => void;               // Close modal handler
  onCaptureSnapshot: () => void;     // Snapshot capture handler
  onSendToSupport: () => void;       // Support send handler
  timestamp?: string;                // Last update timestamp (ISO format)
}
```

## 🎨 Styling Features

### Color Coding Logic
Metrics are color-coded based on threshold values:
- **Green** (`text-green-500`): Value below warning threshold (healthy)
- **Yellow** (`text-yellow-500`): Value between warning and critical (warning)
- **Red** (`text-red-500`): Value above critical threshold (critical)
- **Gray** (`text-gray-400`): Null/undefined values (N/A)
- **Blue** (`text-blue-500`): No thresholds defined (informational)

### Responsive Grid
- **Mobile** (< 640px): 1 column
- **Tablet** (640px - 1024px): 2 columns
- **Desktop** (> 1024px): 4 columns

### Dark Mode
All colors have `dark:` variants for seamless dark mode support.

## 🧪 Data Test IDs for Playwright Testing

The component includes comprehensive test IDs for automated testing:

```typescript
// Modal structure
data-testid="full-metrics-modal"          // Root container
data-testid="metrics-modal-backdrop"      // Backdrop overlay
data-testid="metrics-modal-content"       // Modal content

// Header actions
data-testid="snapshot-button"             // Snapshot button
data-testid="support-button"              // Support button
data-testid="close-button"                // Close X button
data-testid="footer-close-button"         // Footer close button

// Live indicator
data-testid="live-indicator"              // Real-time update indicator

// Category sections
data-testid="section-session-metrics"     // Session section
data-testid="section-performance-metrics" // Performance section
data-testid="section-frame-timing"        // Timing section
data-testid="section-system-metrics"      // System section

// Individual metric cards
data-testid="metric-card-{metricKey}"     // e.g., "metric-card-session_total"
```

## 🔧 Usage Examples

### Basic Integration

```tsx
import { FullMetricsModal } from '@/components/FullMetricsModal';
import { PrometheusMetrics } from '@/types/monitor';

function MyComponent() {
  const [isOpen, setIsOpen] = useState(false);
  const metrics: PrometheusMetrics = {
    session_total: 1542,
    response_time_p50: 145.3,
    gpu_percent: 72.5,
    // ... other metrics
  };

  return (
    <>
      <button onClick={() => setIsOpen(true)}>View Metrics</button>

      {isOpen && (
        <FullMetricsModal
          containerName="renny-production-01"
          metrics={metrics}
          onClose={() => setIsOpen(false)}
          onCaptureSnapshot={() => console.log('Snapshot')}
          onSendToSupport={() => console.log('Support')}
          timestamp={new Date().toISOString()}
        />
      )}
    </>
  );
}
```

### With Real-time WebSocket Updates

```tsx
function RealtimeMetrics() {
  const [metrics, setMetrics] = useState<PrometheusMetrics>({});
  const [lastUpdate, setLastUpdate] = useState<string>('');

  useEffect(() => {
    const ws = new WebSocket('ws://localhost:8000/ws');

    ws.onmessage = (event) => {
      const data = JSON.parse(event.data);
      if (data.type === 'metrics_update') {
        setMetrics(data.metrics);
        setLastUpdate(new Date().toISOString());
      }
    };

    return () => ws.close();
  }, []);

  return (
    <FullMetricsModal
      containerName="renny-realtime"
      metrics={metrics}
      timestamp={lastUpdate}
      {...handlers}
    />
  );
}
```

### With Snapshot Download

```tsx
const handleCaptureSnapshot = () => {
  const snapshot = {
    container: containerName,
    timestamp: new Date().toISOString(),
    metrics: metrics,
  };

  const blob = new Blob([JSON.stringify(snapshot, null, 2)], {
    type: 'application/json'
  });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `metrics-snapshot-${containerName}-${Date.now()}.json`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
};
```

### With Support Integration

```tsx
const handleSendToSupport = async () => {
  const diagnosticData = {
    container: containerName,
    timestamp: new Date().toISOString(),
    metrics: metrics,
    userAgent: navigator.userAgent,
  };

  // Option 1: Copy to clipboard
  await navigator.clipboard.writeText(JSON.stringify(diagnosticData, null, 2));
  alert('Diagnostic data copied! Paste in support ticket.');

  // Option 2: Send to support API
  await fetch('/api/support/tickets', {
    method: 'POST',
    body: JSON.stringify(diagnosticData),
    headers: { 'Content-Type': 'application/json' },
  });
};
```

## 📚 Dependencies

### Required
- `react` ^18.2.0
- `lucide-react` ^0.294.0 (icons)
- `clsx` ^2.0.0 (class utilities)
- `framer-motion` ^12.0.0+ (animations) **← NEW DEPENDENCY ADDED**
- `tailwindcss` ^3.3.6 (styling)

### Internal Dependencies
- `@/types/monitor` - PrometheusMetrics interface
- `@/config/metricConfigs` - Metric configurations and utilities

## 🎭 Animation Behavior

### Modal Enter/Exit
- **Duration**: 200ms
- **Enter**: Fade in + scale up + slide down
- **Exit**: Fade out + scale down + slide up

### Metric Cards
- **Stagger**: Each card animates independently
- **Effect**: Fade in + slide up (10px)
- **Duration**: 200ms per card

## 🧩 Component Architecture

### Internal Sub-Components

#### MetricCard
Reusable card component for individual metrics:
- Icon with color coding
- Label text
- Value with unit
- Background color based on threshold
- Tooltip with description

### Helper Functions

#### getColorClass()
Determines text color based on metric value and thresholds.

#### getCardBgClass()
Determines background color for metric card.

#### formatValue()
Formats metric values with appropriate precision:
- Milliseconds: 2 decimals if < 10, else 1 decimal
- Percentages/Watts: 0 decimals (integer)
- Counts: Rounded integer

#### timeSinceUpdate()
Calculates human-readable time since last update:
- < 60s: "Xs ago"
- < 3600s: "Xm ago"
- >= 3600s: "Xh ago"

## 🔍 Type Safety

All types are strictly enforced:
- Props interface exported for external use
- PrometheusMetrics type ensures metric shape
- MetricConfig type ensures configuration consistency
- No explicit `any` types used

## 🎨 Design Tokens

### Brand Colors
- Gradient header: `bg-gradient-uneeq` (defined in Tailwind config)
- Primary action: Blue 500
- Success: Green 500
- Warning: Yellow 500
- Error: Red 500

### Spacing
- Modal padding: 1.5rem (6 Tailwind units)
- Card gap: 0.75rem (3 Tailwind units)
- Section gap: 1.5rem (6 Tailwind units)

## 📊 Performance Considerations

- Metrics grouped by category using `useMemo` for optimization
- Time calculation memoized to prevent unnecessary re-renders
- Animation duration kept short (200ms) for responsiveness
- Grid layout uses CSS Grid for efficient rendering

## 🐛 Error Handling

- Null/undefined metrics display as "N/A"
- Missing metric configs gracefully skipped
- Invalid timestamps default to "N/A"
- Missing timestamp prop handled with optional chaining

## 🧪 Testing Recommendations

### Unit Tests
Test individual helper functions:
- `getColorClass()` with various thresholds
- `formatValue()` with different units
- `timeSinceUpdate()` with various timestamps

### Integration Tests
Test component rendering:
- All 22 metrics display correctly
- Color coding based on thresholds
- Responsive grid layout
- Dark mode variants

### E2E Tests (Playwright)
Test user interactions:
- Modal opens/closes
- Snapshot button triggers download
- Support button executes handler
- All metric cards render with correct data
- Real-time updates reflect in UI

## 📝 Example Test

```typescript
// Playwright test example
test('displays all metrics categories', async ({ page }) => {
  await page.goto('/');

  // Open modal
  await page.getByTestId('open-metrics-button').click();

  // Verify sections
  await expect(page.getByTestId('section-session-metrics')).toBeVisible();
  await expect(page.getByTestId('section-performance-metrics')).toBeVisible();
  await expect(page.getByTestId('section-frame-timing')).toBeVisible();
  await expect(page.getByTestId('section-system-metrics')).toBeVisible();

  // Verify specific metric
  await expect(page.getByTestId('metric-card-session_total')).toBeVisible();

  // Test actions
  await page.getByTestId('snapshot-button').click();
  await page.getByTestId('close-button').click();
  await expect(page.getByTestId('full-metrics-modal')).not.toBeVisible();
});
```

## 🔗 Related Files

- **Component**: `/src/components/FullMetricsModal.tsx`
- **Examples**: `/src/examples/FullMetricsModalExample.tsx`
- **Types**: `/src/types/monitor.ts`
- **Configs**: `/src/config/metricConfigs.ts`
- **Inline Version**: `/src/components/InlineMetrics.tsx`

## 📄 License

Part of MiniPrem Monitor application.
