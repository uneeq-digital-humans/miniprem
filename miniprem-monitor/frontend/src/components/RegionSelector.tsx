import React, { useState, useRef, useEffect } from 'react';
import { ChevronDown, MapPin } from 'lucide-react';
import clsx from 'clsx';

export interface RegionSelectorProps {
  currentRegion: string;
  availableRegions: string[];
  onRegionSelect: (region: string) => void;
  loading?: boolean;
  compact?: boolean;
}

export function RegionSelector({
  currentRegion,
  availableRegions,
  onRegionSelect,
  loading = false,
  compact = false
}: RegionSelectorProps) {
  const [isOpen, setIsOpen] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  // Close dropdown when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setIsOpen(false);
      }
    };

    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  return (
    <div className="relative" ref={dropdownRef}>
      {/* Current region display */}
      <button
        onClick={() => setIsOpen(!isOpen)}
        className={clsx(
          'flex items-center space-x-2 px-3 py-1 rounded-full bg-white dark:bg-gray-700 shadow-sm border border-gray-200 dark:border-gray-600 hover:bg-gray-50 dark:hover:bg-gray-600 transition-colors',
          isOpen && 'ring-2 ring-uneeq-primary ring-opacity-20',
          compact ? 'text-xs' : 'text-sm'
        )}
        disabled={loading}
        data-testid="region-selector"
      >
        <MapPin className="w-3 h-3 text-uneeq-primary" />
        <span className="font-medium text-primary">
          {currentRegion}
        </span>
        <ChevronDown className={clsx(
          'w-4 h-4 text-muted transition-transform',
          isOpen && 'transform rotate-180'
        )} />
      </button>

      {/* Dropdown menu */}
      {isOpen && (
        <div className="absolute top-full left-0 mt-2 w-48 bg-white dark:bg-gray-800 rounded-lg shadow-lg border border-gray-200 dark:border-gray-700 z-50">
          {/* Header */}
          <div className="px-4 py-3 border-b border-gray-200 dark:border-gray-700">
            <h3 className="text-sm font-semibold text-primary flex items-center space-x-2">
              <MapPin className="w-4 h-4 text-uneeq-primary" />
              <span>AWS Region</span>
            </h3>
          </div>

          {/* Region list */}
          <div className="py-2">
            {availableRegions.map((region) => {
              const isSelected = currentRegion === region;

              return (
                <button
                  key={region}
                  onClick={() => {
                    onRegionSelect(region);
                    setIsOpen(false);
                  }}
                  className={clsx(
                    'w-full px-4 py-2 text-left hover:bg-gray-50 dark:hover:bg-gray-700 transition-colors',
                    isSelected && 'bg-blue-50 dark:bg-blue-900/20'
                  )}
                  data-testid={`region-option-${region}`}
                >
                  <div className="flex items-center justify-between">
                    <span className="font-medium text-primary">
                      {region}
                    </span>
                    {isSelected && (
                      <div className="w-2 h-2 bg-uneeq-primary rounded-full" />
                    )}
                  </div>
                </button>
              );
            })}
          </div>
        </div>
      )}

      {/* Loading overlay */}
      {loading && (
        <div className="absolute inset-0 bg-white/50 dark:bg-gray-800/50 rounded-full flex items-center justify-center">
          <div className="w-4 h-4 border-2 border-uneeq-primary border-t-transparent rounded-full animate-spin" />
        </div>
      )}
    </div>
  );
}