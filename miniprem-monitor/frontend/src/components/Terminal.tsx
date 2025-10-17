'use client';

import React, { useEffect, useRef, useState } from 'react';
import { X, Maximize2, Minimize2, RotateCcw, Copy, Download } from 'lucide-react';
import clsx from 'clsx';
import '@xterm/xterm/css/xterm.css';

interface TerminalProps {
  isOpen: boolean;
  onClose: () => void;
  title?: string;
  websocketUrl?: string;
  initialCommand?: string;
}

export function Terminal({
  isOpen,
  onClose,
  title = 'Terminal',
  websocketUrl,
  initialCommand
}: TerminalProps) {
  const terminalRef = useRef<HTMLDivElement>(null);
  const xtermRef = useRef<any | null>(null);
  const fitAddonRef = useRef<any | null>(null);
  const wsRef = useRef<WebSocket | null>(null);
  const [isMaximized, setIsMaximized] = useState(false);
  const [isConnected, setIsConnected] = useState(false);
  const [commandHistory, setCommandHistory] = useState<string[]>([]);
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  // Auto-detect WebSocket URL - connect directly to backend port 8000
  const getWebSocketUrl = (): string => {
    if (typeof window === 'undefined') return '';

    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const hostname = window.location.hostname; // just hostname, no port
    // Terminal WebSocket must connect directly to backend port 8000
    return `${protocol}//${hostname}:8000/ws/terminal`;
  };

  useEffect(() => {
    if (!isOpen || !terminalRef.current || !mounted) return;

    // Dynamically import xterm modules (client-side only)
    const initTerminal = async () => {
      const { Terminal: XTerm } = await import('@xterm/xterm');
      const { FitAddon } = await import('@xterm/addon-fit');
      const { WebLinksAddon } = await import('@xterm/addon-web-links');

      // Initialize xterm.js
      const term = new XTerm({
      cursorBlink: true,
      fontSize: 14,
      fontFamily: '"Fira Code", "Cascadia Code", "Courier New", monospace',
      theme: {
        background: '#1e1e1e',
        foreground: '#d4d4d4',
        cursor: '#00A9CE',
        cursorAccent: '#1e1e1e',
        black: '#000000',
        red: '#cd3131',
        green: '#0dbc79',
        yellow: '#e5e510',
        blue: '#2472c8',
        magenta: '#bc3fbc',
        cyan: '#11a8cd',
        white: '#e5e5e5',
        brightBlack: '#666666',
        brightRed: '#f14c4c',
        brightGreen: '#23d18b',
        brightYellow: '#f5f543',
        brightBlue: '#3b8eea',
        brightMagenta: '#d670d6',
        brightCyan: '#29b8db',
        brightWhite: '#ffffff'
      },
      scrollback: 1000,
      convertEol: true,
      allowTransparency: false
    });

    // Add fit addon for responsive sizing
    const fitAddon = new FitAddon();
    term.loadAddon(fitAddon);
    fitAddonRef.current = fitAddon;

    // Add web links addon
    const webLinksAddon = new WebLinksAddon();
    term.loadAddon(webLinksAddon);

      // Open terminal in container
      if (!terminalRef.current) return;
      term.open(terminalRef.current);
      fitAddon.fit();

    xtermRef.current = term;

    // Welcome message
    term.writeln('\x1b[1;32m╔══════════════════════════════════════════╗\x1b[0m');
    term.writeln('\x1b[1;32m║  MiniPrem Monitor - Interactive Shell   ║\x1b[0m');
    term.writeln('\x1b[1;32m╚══════════════════════════════════════════╝\x1b[0m');
    term.writeln('');
    term.writeln('\x1b[0;36mConnecting to backend WebSocket...\x1b[0m');
    term.writeln('');

    // Connect to WebSocket
    const wsUrl = websocketUrl || getWebSocketUrl();
    connectWebSocket(term, wsUrl);

    // Handle resize
    const handleResize = () => {
      if (fitAddonRef.current && terminalRef.current) {
        setTimeout(() => fitAddonRef.current?.fit(), 100);
      }
    };

    window.addEventListener('resize', handleResize);

      // Cleanup
      return () => {
        window.removeEventListener('resize', handleResize);
        if (wsRef.current) {
          wsRef.current.close();
        }
        term.dispose();
      };
    };

    initTerminal();
  }, [isOpen, websocketUrl, initialCommand, mounted]);

  const connectWebSocket = (term: any, url: string) => {
    try {
      const ws = new WebSocket(url);
      wsRef.current = ws;

      ws.onopen = () => {
        setIsConnected(true);
        term.writeln('\x1b[1;32m✓ Connected to backend\x1b[0m');
        term.writeln('');
        term.write('\x1b[1;34m$ \x1b[0m');
      };

      ws.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data);

          if (data.type === 'output') {
            term.write(data.content);
          } else if (data.type === 'error') {
            term.writeln(`\x1b[1;31mError: ${data.message}\x1b[0m`);
          } else if (data.type === 'command_complete') {
            term.writeln('');
            term.write('\x1b[1;34m$ \x1b[0m');
          }
        } catch (e) {
          // Plain text output
          term.write(event.data);
        }
      };

      ws.onerror = (error) => {
        setIsConnected(false);
        term.writeln('\x1b[1;31m✗ WebSocket connection error\x1b[0m');
        console.error('WebSocket error:', error);
      };

      ws.onclose = () => {
        setIsConnected(false);
        term.writeln('');
        term.writeln('\x1b[0;33m⚠ Connection closed\x1b[0m');
      };

      // Handle terminal input - send each character directly to subprocess
      term.onData((data: string) => {
        // Send input directly to subprocess (character-by-character)
        if (ws.readyState === WebSocket.OPEN) {
          ws.send(JSON.stringify({
            type: 'input',
            data: data
          }));
        }
      });

    } catch (error) {
      term.writeln(`\x1b[1;31m✗ Failed to connect: ${error}\x1b[0m`);
      console.error('WebSocket connection error:', error);
    }
  };


  const handleClear = () => {
    xtermRef.current?.clear();
  };

  const handleCopyOutput = () => {
    if (xtermRef.current) {
      const selection = xtermRef.current.getSelection();
      if (selection) {
        navigator.clipboard.writeText(selection);
      }
    }
  };

  const handleDownloadLog = () => {
    if (xtermRef.current) {
      const buffer = (xtermRef.current as any)._core.buffer.active;
      let output = '';

      for (let i = 0; i < buffer.length; i++) {
        const line = buffer.getLine(i);
        if (line) {
          output += line.translateToString(true) + '\n';
        }
      }

      const blob = new Blob([output], { type: 'text/plain' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `terminal-log-${Date.now()}.txt`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
    }
  };

  const toggleMaximize = () => {
    setIsMaximized(!isMaximized);
    setTimeout(() => {
      if (fitAddonRef.current) {
        fitAddonRef.current.fit();
      }
    }, 100);
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      {/* Backdrop */}
      <div
        className="absolute inset-0 bg-black/70 backdrop-blur-sm"
        onClick={onClose}
      />

      {/* Terminal Window */}
      <div
        className={clsx(
          'relative bg-[#1e1e1e] rounded-lg shadow-2xl transition-all duration-200',
          isMaximized ? 'w-full h-full rounded-none' : 'w-[90%] h-[80%] max-w-6xl'
        )}
        data-testid="terminal-window"
      >
        {/* Title Bar */}
        <div className="flex items-center justify-between px-4 py-3 bg-[#2d2d2d] rounded-t-lg border-b border-[#3e3e3e]">
          <div className="flex items-center space-x-3">
            <div className="flex space-x-2">
              <button
                onClick={onClose}
                className="w-3 h-3 rounded-full bg-[#ff5f56] hover:bg-[#ff3b30] transition-colors"
                data-testid="terminal-close"
              />
              <button
                onClick={toggleMaximize}
                className="w-3 h-3 rounded-full bg-[#ffbd2e] hover:bg-[#ff9500] transition-colors"
                data-testid="terminal-maximize"
              />
              <button
                className="w-3 h-3 rounded-full bg-[#27c93f] hover:bg-[#28cd41] transition-colors"
                data-testid="terminal-minimize"
              />
            </div>
            <span className="text-sm font-medium text-gray-300" data-testid="terminal-title">
              {title}
            </span>
            {isConnected && (
              <span className="flex items-center space-x-1 text-xs text-green-400">
                <span className="w-2 h-2 rounded-full bg-green-400 animate-pulse" />
                <span>Connected</span>
              </span>
            )}
          </div>

          <div className="flex items-center space-x-2">
            <button
              onClick={handleClear}
              className="p-1.5 hover:bg-[#3e3e3e] rounded transition-colors"
              title="Clear terminal"
              data-testid="terminal-clear"
            >
              <RotateCcw className="w-4 h-4 text-gray-400" />
            </button>
            <button
              onClick={handleCopyOutput}
              className="p-1.5 hover:bg-[#3e3e3e] rounded transition-colors"
              title="Copy selection"
              data-testid="terminal-copy"
            >
              <Copy className="w-4 h-4 text-gray-400" />
            </button>
            <button
              onClick={handleDownloadLog}
              className="p-1.5 hover:bg-[#3e3e3e] rounded transition-colors"
              title="Download log"
              data-testid="terminal-download"
            >
              <Download className="w-4 h-4 text-gray-400" />
            </button>
            <button
              onClick={toggleMaximize}
              className="p-1.5 hover:bg-[#3e3e3e] rounded transition-colors"
              title="Toggle fullscreen"
              data-testid="terminal-fullscreen"
            >
              {isMaximized ? (
                <Minimize2 className="w-4 h-4 text-gray-400" />
              ) : (
                <Maximize2 className="w-4 h-4 text-gray-400" />
              )}
            </button>
            <button
              onClick={onClose}
              className="p-1.5 hover:bg-[#3e3e3e] rounded transition-colors"
              title="Close"
            >
              <X className="w-4 h-4 text-gray-400" />
            </button>
          </div>
        </div>

        {/* Terminal Container */}
        <div
          ref={terminalRef}
          className="w-full h-[calc(100%-49px)] p-2"
          data-testid="terminal-container"
        />
      </div>
    </div>
  );
}
