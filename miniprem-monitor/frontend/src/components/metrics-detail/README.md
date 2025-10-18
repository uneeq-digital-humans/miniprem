# MetricsChart Component

A reusable time-series chart component built with Recharts for displaying live system metrics in the MiniPrem Monitor.

## Features

- **Single or dual-line charts** - Display one or two metrics simultaneously
- **5-minute rolling window** - Optimized for real-time monitoring
- **Event annotations** - Mark container start/stop events with vertical reference lines
- **Dark mode support** - Seamless integration with MiniPrem Monitor's theme
- **Responsive design** - Adapts to container width
- **Smooth animations** - Monotone curve interpolation for visual clarity
- **Custom formatting** - Flexible value formatters for different metric types
- **Data summary** - Footer with data point count, current value, and average

## Installation

Recharts is already installed in the project:

```bash
npm install recharts
```

## Usage

### Basic CPU Usage Chart

```tsx
import { MetricsChart, MetricsDataPoint } from '@/components/metrics-detail'

const cpuData: MetricsDataPoint[] = [
  { timestamp: new Date('2025-01-17T10:00:00'), value: 45.2 },
  { timestamp: new Date('2025-01-17T10:00:05'), value: 52.8 },
  { timestamp: new Date('2025-01-17T10:00:10'), value: 48.3 }
]

<MetricsChart
  data={cpuData}
  yAxisLabel="CPU Usage"
  color="#3b82f6"
  lineLabel="CPU %"
/>
```

### Dual-Line Network Chart

```tsx
const networkData: MetricsDataPoint[] = [
  {
    timestamp: new Date('2025-01-17T10:00:00'),
    value: 125.5,    // Bytes sent
    value2: 342.1    // Bytes received
  },
  {
    timestamp: new Date('2025-01-17T10:00:05'),
    value: 198.2,
    value2: 425.7
  }
]

<MetricsChart
  data={networkData}
  yAxisLabel="Network I/O"
  yAxisDomain={[0, 500]}
  color="#10b981"
  color2="#f59e0b"
  lineLabel="Sent (MB/s)"
  lineLabel2="Received (MB/s)"
  formatValue={(v) => `${v.toFixed(1)} MB/s`}
/>
```

### Chart with Event Annotations

```tsx
const memoryData: MetricsDataPoint[] = [
  { timestamp: new Date('2025-01-17T10:00:00'), value: 62.5 },
  {
    timestamp: new Date('2025-01-17T10:00:15'),
    value: 78.3,
    event: {
      type: 'restart',
      label: 'Container restarted'
    }
  },
  { timestamp: new Date('2025-01-17T10:00:30'), value: 45.1 }
]

<MetricsChart
  data={memoryData}
  yAxisLabel="Memory Usage"
  color="#8b5cf6"
  lineLabel="Memory %"
/>
```

## Props API

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `data` | `MetricsDataPoint[]` | Required | Array of time-series data points |
| `yAxisLabel` | `string` | Required | Label for Y-axis (metric name) |
| `height` | `number` | `300` | Chart height in pixels |
| `yAxisDomain` | `[number, number]` | `[0, 100]` | Y-axis range [min, max] |
| `color` | `string` | `'#3b82f6'` | Primary line color (CSS color) |
| `color2` | `string` | `'#f59e0b'` | Secondary line color (CSS color) |
| `showGrid` | `boolean` | `true` | Show chart grid lines |
| `showLegend` | `boolean` | `true` | Show chart legend |
| `formatValue` | `(value: number) => string` | `toFixed(1) + '%'` | Custom value formatter |
| `lineLabel` | `string` | `'Value'` | Primary line label for legend |
| `lineLabel2` | `string` | `'Value 2'` | Secondary line label for legend |
| `className` | `string` | `''` | Additional CSS classes |

## Data Point Interface

```typescript
interface MetricsDataPoint {
  timestamp: Date              // Data point timestamp
  value: number               // Primary metric value
  value2?: number             // Secondary metric value (optional)
  event?: {                   // Event annotation (optional)
    type: string              // Event type (start, stop, restart, error, warning, info)
    label: string             // Event label to display
  }
}
```

## Event Types and Colors

Event annotations use color coding based on event type:

- `start` - Green (#10b981)
- `stop` - Red (#ef4444)
- `restart` - Yellow (#f59e0b)
- `error` - Red (#ef4444)
- `warning` - Yellow (#f59e0b)
- `info` - Blue (#3b82f6)
- Default - Gray (#6b7280)

## Empty State

The component automatically displays an empty state when no data is available:

```tsx
<MetricsChart
  data={[]}
  yAxisLabel="CPU Usage"
/>
// Renders: "No data available - Waiting for metrics..."
```

## Dark Mode

The component automatically adapts to MiniPrem Monitor's dark mode theme using Tailwind's `dark:` variants.

## Testing

The component includes data-testid attributes for Playwright testing:

- `data-testid="metrics-chart"` - Main container
- `data-testid="metrics-chart-tooltip"` - Tooltip element
- `data-testid="metrics-chart-legend"` - Legend element

## Integration with WebSocket Updates

Example of integrating with real-time WebSocket metrics:

```tsx
const [metricsHistory, setMetricsHistory] = useState<MetricsDataPoint[]>([])

useEffect(() => {
  const ws = new WebSocket('ws://localhost:8000/ws/metrics')

  ws.onmessage = (event) => {
    const metrics = JSON.parse(event.data)

    setMetricsHistory(prev => {
      const newData = [
        ...prev,
        {
          timestamp: new Date(),
          value: metrics.cpu_percent
        }
      ]

      // Keep only last 5 minutes (300 seconds / 5 second intervals = 60 points)
      return newData.slice(-60)
    })
  }

  return () => ws.close()
}, [])

return (
  <MetricsChart
    data={metricsHistory}
    yAxisLabel="CPU Usage"
    lineLabel="CPU %"
  />
)
```

## Performance Considerations

- **Animation disabled** - Uses `isAnimationActive={false}` for smooth real-time updates
- **Dots disabled** - Uses `dot={false}` for cleaner lines with many data points
- **Data point limit** - Recommended max 300 points (5 minutes at 1-second intervals)
- **Memoized data** - Uses `useMemo` for chart data transformation

## Accessibility

- Semantic HTML structure
- Color contrast compliant with WCAG 2.1 AA
- Keyboard-navigable tooltip on hover
- Screen reader compatible labels

## Related Components

- `SystemMetrics` - Overview cards for current metrics
- `MetricsCard` - Individual metric display cards
- `MetricsBadge` - Compact metric badges
- `InlineMetrics` - Inline metric displays
