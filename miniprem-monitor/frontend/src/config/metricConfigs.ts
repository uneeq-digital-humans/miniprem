import { MetricConfig } from '../types/monitor';
import {
  TrendingUp,
  CheckCircle2,
  XCircle,
  Film,
  Zap,
  Timer,
  MessageSquare,
  Smile,
  Activity,
  Paintbrush,
  Dices,
  BarChart3,
  Cpu,
  MemoryStick,
  Gauge,
} from 'lucide-react';

/**
 * Available metrics configuration for user selection.
 * Defines display properties, Lucide icons, units, and categories for all metrics.
 */
export const METRIC_CONFIGS: Record<string, MetricConfig> = {
  // Session Metrics
  session_total: {
    key: 'session_total',
    label: 'Total Sessions',
    icon: TrendingUp,
    unit: '',
    category: 'session',
    description: 'Total number of sessions started',
  },
  session_successful: {
    key: 'session_successful',
    label: 'Successful Sessions',
    icon: CheckCircle2,
    unit: '',
    category: 'session',
    description: 'Number of successfully completed sessions',
  },
  session_failed: {
    key: 'session_failed',
    label: 'Failed Sessions',
    icon: XCircle,
    unit: '',
    category: 'session',
    description: 'Number of failed sessions',
  },
  frames_rendered: {
    key: 'frames_rendered',
    label: 'Frames Rendered',
    icon: Film,
    unit: '',
    category: 'session',
    description: 'Total number of frames rendered',
  },

  // Performance Metrics (Response Times)
  response_time_p50: {
    key: 'response_time_p50',
    label: 'Response Time (p50)',
    icon: Zap,
    unit: 'ms',
    category: 'performance',
    description: 'Median response time (50th percentile)',
    thresholds: { warning: 200, critical: 500 },
  },
  response_time_p90: {
    key: 'response_time_p90',
    label: 'Response Time (p90)',
    icon: Timer,
    unit: 'ms',
    category: 'performance',
    description: '90th percentile response time',
    thresholds: { warning: 400, critical: 1000 },
  },
  response_time_p99: {
    key: 'response_time_p99',
    label: 'Response Time (p99)',
    icon: Timer,
    unit: 'ms',
    category: 'performance',
    description: '99th percentile response time',
    thresholds: { warning: 600, critical: 1500 },
  },
  nlp_response_time_p50: {
    key: 'nlp_response_time_p50',
    label: 'NLP Response Time',
    icon: MessageSquare,
    unit: 'ms',
    category: 'performance',
    description: 'Natural Language Processing response time (p50)',
    thresholds: { warning: 150, critical: 400 },
  },
  a2f_response_time_p50: {
    key: 'a2f_response_time_p50',
    label: 'A2F Response Time',
    icon: Smile,
    unit: 'ms',
    category: 'performance',
    description: 'Audio-to-Face response time (p50)',
    thresholds: { warning: 100, critical: 300 },
  },

  // Frame Timing Metrics
  gpu_frame_time_avg: {
    key: 'gpu_frame_time_avg',
    label: 'GPU Frame Time',
    icon: Activity,
    unit: 'ms',
    category: 'timing',
    description: 'Average GPU frame processing time',
    thresholds: { warning: 20, critical: 33 }, // 50fps = 20ms, 30fps = 33ms
  },
  render_frame_time_avg: {
    key: 'render_frame_time_avg',
    label: 'Render Time',
    icon: Paintbrush,
    unit: 'ms',
    category: 'timing',
    description: 'Average render thread frame time',
    thresholds: { warning: 20, critical: 33 },
  },
  game_frame_time_avg: {
    key: 'game_frame_time_avg',
    label: 'Game Thread Time',
    icon: Dices,
    unit: 'ms',
    category: 'timing',
    description: 'Average game thread frame time',
    thresholds: { warning: 20, critical: 33 },
  },
  frame_time_avg: {
    key: 'frame_time_avg',
    label: 'Total Frame Time',
    icon: BarChart3,
    unit: 'ms',
    category: 'timing',
    description: 'Average total frame time',
    thresholds: { warning: 20, critical: 33 },
  },

  // Standard System Metrics
  gpu_percent: {
    key: 'gpu_percent',
    label: 'GPU Usage',
    icon: Activity,
    unit: '%',
    category: 'system',
    description: 'GPU utilization percentage',
    thresholds: { warning: 60, critical: 80 },
  },
  cpu_percent: {
    key: 'cpu_percent',
    label: 'CPU Usage',
    icon: Cpu,
    unit: '%',
    category: 'system',
    description: 'CPU utilization percentage',
    thresholds: { warning: 60, critical: 80 },
  },
  memory_percent: {
    key: 'memory_percent',
    label: 'Memory Usage',
    icon: MemoryStick,
    unit: '%',
    category: 'system',
    description: 'Memory utilization percentage',
    thresholds: { warning: 60, critical: 80 },
  },
  power_watts: {
    key: 'power_watts',
    label: 'Power Draw',
    icon: Gauge,
    unit: 'W',
    category: 'system',
    description: 'Power consumption in watts',
    thresholds: { warning: 150, critical: 250 },
  },
};

/**
 * Default metric preferences (3 slots).
 * These are shown when user hasn't customized their selection.
 */
export const DEFAULT_METRIC_PREFERENCES: [string, string, string] = [
  'session_total',
  'response_time_p50',
  'gpu_frame_time_avg',
];

/**
 * Get metric configuration by key.
 */
export function getMetricConfig(key: string): MetricConfig | undefined {
  return METRIC_CONFIGS[key];
}

/**
 * Get all metrics grouped by category.
 */
export function getMetricsByCategory() {
  return {
    session: Object.values(METRIC_CONFIGS).filter(m => m.category === 'session'),
    performance: Object.values(METRIC_CONFIGS).filter(m => m.category === 'performance'),
    timing: Object.values(METRIC_CONFIGS).filter(m => m.category === 'timing'),
    system: Object.values(METRIC_CONFIGS).filter(m => m.category === 'system'),
  };
}
