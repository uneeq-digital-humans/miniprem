import React, { useEffect, useState } from 'react';
import { Moon, Sun } from 'lucide-react';

interface DarkModeToggleProps {
  className?: string;
}

export function DarkModeToggle({ className = '' }: DarkModeToggleProps) {
  const [isDark, setIsDark] = useState(false);

  // Initialize dark mode from localStorage or system preference
  useEffect(() => {
    const stored = localStorage.getItem('darkMode');
    if (stored) {
      const darkMode = JSON.parse(stored);
      setIsDark(darkMode);
      updateDarkMode(darkMode);
    } else {
      // Check system preference
      const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
      setIsDark(prefersDark);
      updateDarkMode(prefersDark);
    }
  }, []);

  const updateDarkMode = (dark: boolean) => {
    if (dark) {
      document.documentElement.classList.add('dark');
    } else {
      document.documentElement.classList.remove('dark');
    }
  };

  const toggleDarkMode = () => {
    const newMode = !isDark;
    setIsDark(newMode);
    localStorage.setItem('darkMode', JSON.stringify(newMode));
    updateDarkMode(newMode);
  };

  return (
    <button
      onClick={toggleDarkMode}
      className={`p-2 rounded-lg bg-white/10 hover:bg-white/20 transition-colors duration-200 ${className}`}
      title={isDark ? 'Switch to light mode' : 'Switch to dark mode'}
      data-testid="dark-mode-toggle"
    >
      {isDark ? (
        <Sun className="w-5 h-5 text-white" data-testid="sun-icon" />
      ) : (
        <Moon className="w-5 h-5 text-white" data-testid="moon-icon" />
      )}
    </button>
  );
}