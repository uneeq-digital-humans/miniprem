/**
 * Example integration of FullMetricsModal component
 *
 * This file demonstrates how to use the FullMetricsModal in your application.
 * It shows the required props, state management, and event handlers.
 *
 * @example Basic Usage in a Container List Component
 */

import React, { useState } from 'react';
import { FullMetricsModal } from '../components/FullMetricsModal';
import { PrometheusMetrics } from '../types/monitor';
import { BarChart3 } from 'lucide-react';

// Example: Integration in a Container Row Component
export function ContainerRowExample() {
  const [isMetricsModalOpen, setIsMetricsModalOpen] = useState(false);

  // Example metrics data (normally fetched from your backend)
  const exampleMetrics: PrometheusMetrics = {
    // Session metrics
    session_total: 1542,
    session_successful: 1487,
    session_failed: 55,
    frames_rendered: 2847392,

    // Performance metrics
    response_time_p50: 145.3,
    response_time_p90: 287.6,
    response_time_p99: 542.1,
    nlp_response_time_p50: 98.4,
    a2f_response_time_p50: 67.2,

    // Frame timing
    gpu_frame_time_avg: 15.8,
    render_frame_time_avg: 12.3,
    game_frame_time_avg: 9.7,
    frame_time_avg: 16.2,

    // System metrics
    gpu_percent: 72.5,
    cpu_percent: 45.2,
    memory_percent: 68.9,
    power_watts: 185.3,
  };

  const containerName = 'renny-production-01';
  const timestamp = new Date().toISOString();

  const handleCaptureSnapshot = () => {
    console.log('Capturing metrics snapshot...', exampleMetrics);
    // Implement snapshot logic:
    // - Download JSON file
    // - Copy to clipboard
    // - Save to localStorage
    // - Send to analytics

    const snapshot = {
      container: containerName,
      timestamp: new Date().toISOString(),
      metrics: exampleMetrics,
    };

    const blob = new Blob([JSON.stringify(snapshot, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `metrics-snapshot-${containerName}-${Date.now()}.json`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  };

  const handleSendToSupport = () => {
    console.log('Sending metrics to support...', exampleMetrics);
    // Implement support integration:
    // - Open email client with pre-filled data
    // - Send to support API endpoint
    // - Create support ticket via API
    // - Copy diagnostic info to clipboard

    const diagnosticData = {
      container: containerName,
      timestamp: new Date().toISOString(),
      metrics: exampleMetrics,
      userAgent: navigator.userAgent,
      screen: {
        width: window.screen.width,
        height: window.screen.height,
      },
    };

    // Example: Copy to clipboard
    navigator.clipboard.writeText(JSON.stringify(diagnosticData, null, 2))
      .then(() => {
        alert('Diagnostic data copied to clipboard! Please paste in support ticket.');
      })
      .catch((err) => {
        console.error('Failed to copy:', err);
      });
  };

  return (
    <div className="p-4">
      {/* Example: Button to open metrics modal */}
      <button
        onClick={() => setIsMetricsModalOpen(true)}
        className="flex items-center gap-2 px-4 py-2 bg-blue-500 hover:bg-blue-600 text-white rounded-lg transition-colors"
        data-testid="open-metrics-button"
      >
        <BarChart3 className="w-4 h-4" />
        <span>View All Metrics</span>
      </button>

      {/* Render the modal when open */}
      {isMetricsModalOpen && (
        <FullMetricsModal
          containerName={containerName}
          metrics={exampleMetrics}
          onClose={() => setIsMetricsModalOpen(false)}
          onCaptureSnapshot={handleCaptureSnapshot}
          onSendToSupport={handleSendToSupport}
          timestamp={timestamp}
        />
      )}
    </div>
  );
}

// Example: Integration with WebSocket real-time updates
export function ContainerWithRealtimeMetrics() {
  const [isMetricsModalOpen, setIsMetricsModalOpen] = useState(false);
  const [metrics, setMetrics] = useState<PrometheusMetrics>({});
  const [lastUpdate, setLastUpdate] = useState<string>(new Date().toISOString());

  // Simulate WebSocket updates (replace with actual WebSocket logic)
  React.useEffect(() => {
    const interval = setInterval(() => {
      // Simulate incoming metrics from WebSocket
      setMetrics({
        session_total: Math.floor(Math.random() * 2000),
        response_time_p50: Math.random() * 500,
        gpu_frame_time_avg: Math.random() * 30,
        gpu_percent: Math.random() * 100,
        cpu_percent: Math.random() * 100,
        memory_percent: Math.random() * 100,
      });
      setLastUpdate(new Date().toISOString());
    }, 2000);

    return () => clearInterval(interval);
  }, []);

  return (
    <div className="p-4">
      <button
        onClick={() => setIsMetricsModalOpen(true)}
        className="flex items-center gap-2 px-4 py-2 bg-gradient-uneeq text-white rounded-lg"
      >
        <BarChart3 className="w-4 h-4" />
        <span>Real-time Metrics</span>
      </button>

      {isMetricsModalOpen && (
        <FullMetricsModal
          containerName="renny-realtime"
          metrics={metrics}
          onClose={() => setIsMetricsModalOpen(false)}
          onCaptureSnapshot={() => console.log('Snapshot:', metrics)}
          onSendToSupport={() => console.log('Support:', metrics)}
          timestamp={lastUpdate}
        />
      )}
    </div>
  );
}

// Example: Integration in existing container monitoring component
export function ExistingContainerListIntegration() {
  const [selectedContainer, setSelectedContainer] = useState<{
    name: string;
    metrics: PrometheusMetrics;
  } | null>(null);

  const containers = [
    { name: 'renny-01', metrics: { session_total: 100, gpu_percent: 45 } },
    { name: 'renny-02', metrics: { session_total: 200, gpu_percent: 67 } },
    { name: 'renny-03', metrics: { session_total: 150, gpu_percent: 52 } },
  ];

  return (
    <div className="space-y-2">
      {containers.map((container) => (
        <div
          key={container.name}
          className="flex items-center justify-between p-4 bg-white dark:bg-gray-800 rounded-lg"
        >
          <span className="font-medium">{container.name}</span>
          <button
            onClick={() => setSelectedContainer(container)}
            className="px-3 py-1 bg-blue-500 text-white rounded hover:bg-blue-600"
          >
            View Metrics
          </button>
        </div>
      ))}

      {selectedContainer && (
        <FullMetricsModal
          containerName={selectedContainer.name}
          metrics={selectedContainer.metrics}
          onClose={() => setSelectedContainer(null)}
          onCaptureSnapshot={() => {
            console.log('Snapshot for', selectedContainer.name);
          }}
          onSendToSupport={() => {
            console.log('Support for', selectedContainer.name);
          }}
        />
      )}
    </div>
  );
}
