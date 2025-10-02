import React, { useState, useEffect, useRef } from 'react';
import { X, Download, Pause, Play } from 'lucide-react';
import clsx from 'clsx';

interface LogViewerProps {
  isOpen: boolean;
  onClose: () => void;
  title: string;
  logs: string;
  loading?: boolean;
  autoScroll?: boolean;
  onToggleAutoScroll?: (enabled: boolean) => void;
}

export function LogViewer({
  isOpen,
  onClose,
  title,
  logs,
  loading,
  autoScroll = true,
  onToggleAutoScroll
}: LogViewerProps) {
  const [isAutoScroll, setIsAutoScroll] = useState(autoScroll);
  const logContainerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (isAutoScroll && logContainerRef.current) {
      logContainerRef.current.scrollTop = logContainerRef.current.scrollHeight;
    }
  }, [logs, isAutoScroll]);

  const handleToggleAutoScroll = () => {
    const newState = !isAutoScroll;
    setIsAutoScroll(newState);
    onToggleAutoScroll?.(newState);
  };

  const downloadLogs = () => {
    const blob = new Blob([logs], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${title.replace(/\s+/g, '_').toLowerCase()}_logs.txt`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  };

  const formatLogLine = (line: string, index: number) => {
    // Highlight different log levels
    const levelPatterns = [
      { pattern: /ERROR|FATAL|CRITICAL/gi, className: 'text-red-400' },
      { pattern: /WARN|WARNING/gi, className: 'text-yellow-400' },
      { pattern: /INFO/gi, className: 'text-blue-400' },
      { pattern: /DEBUG/gi, className: 'text-green-400' },
      { pattern: /\d{4}-\d{2}-\d{2}[T\s]\d{2}:\d{2}:\d{2}/g, className: 'text-gray-400' },
    ];

    let formattedLine = line;
    let className = 'text-gray-100';

    for (const { pattern, className: patternClass } of levelPatterns) {
      if (pattern.test(line)) {
        className = patternClass;
        break;
      }
    }

    return (
      <div key={index} className={clsx('font-mono text-xs leading-relaxed', className)}>
        {formattedLine || '\u00A0'}
      </div>
    );
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
      <div className="bg-white dark:bg-gray-800 rounded-lg shadow-xl max-w-6xl w-full max-h-[90vh] flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between p-4 border-b border-gray-200 dark:border-gray-700">
          <h3 className="text-lg font-semibold text-gray-900 dark:text-gray-100">{title} Logs</h3>
          <div className="flex items-center space-x-2">
            <button
              onClick={handleToggleAutoScroll}
              className={clsx(
                'flex items-center space-x-1 px-3 py-1 rounded text-sm transition-colors',
                isAutoScroll
                  ? 'bg-uneeq-primary text-white'
                  : 'bg-gray-200 dark:bg-gray-600 text-gray-700 dark:text-gray-300 hover:bg-gray-300 dark:hover:bg-gray-500'
              )}
              title={isAutoScroll ? 'Disable auto-scroll' : 'Enable auto-scroll'}
            >
              {isAutoScroll ? (
                <>
                  <Pause className="w-3 h-3" />
                  <span>Auto-scroll</span>
                </>
              ) : (
                <>
                  <Play className="w-3 h-3" />
                  <span>Manual</span>
                </>
              )}
            </button>

            <button
              onClick={downloadLogs}
              className="flex items-center space-x-1 px-3 py-1 rounded text-sm bg-gray-200 dark:bg-gray-600 text-gray-700 dark:text-gray-300 hover:bg-gray-300 dark:hover:bg-gray-500 transition-colors"
              title="Download logs"
              disabled={!logs}
            >
              <Download className="w-3 h-3" />
              <span>Download</span>
            </button>

            <button
              onClick={onClose}
              className="p-1 rounded hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors"
              title="Close"
            >
              <X className="w-5 h-5 text-gray-600 dark:text-gray-400" />
            </button>
          </div>
        </div>

        {/* Log Content */}
        <div className="flex-1 overflow-hidden">
          {loading ? (
            <div className="flex items-center justify-center h-64">
              <div className="flex items-center space-x-2 text-gray-500 dark:text-gray-400">
                <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-uneeq-primary"></div>
                <span>Loading logs...</span>
              </div>
            </div>
          ) : logs ? (
            <div
              ref={logContainerRef}
              className="log-container h-full p-4 overflow-auto"
              style={{ maxHeight: 'calc(90vh - 120px)' }}
            >
              {logs.split('\n').map((line, index) => formatLogLine(line, index))}
            </div>
          ) : (
            <div className="flex items-center justify-center h-64 text-gray-500 dark:text-gray-400">
              <div className="text-center">
                <div className="text-4xl mb-2">📝</div>
                <p>No logs available</p>
                <p className="text-sm">Logs may not be accessible or empty</p>
              </div>
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="p-3 border-t border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-700 text-xs text-gray-600 dark:text-gray-300">
          <div className="flex justify-between items-center">
            <span>
              {logs ? `${logs.split('\n').length} lines` : 'No logs'}
            </span>
            <span>
              Last updated: {new Date().toLocaleTimeString()}
            </span>
          </div>
        </div>
      </div>
    </div>
  );
}