import type { Metadata, Viewport } from 'next';
import '../styles/globals.css';

export const metadata: Metadata = {
  title: 'MiniPrem Monitor | Real-time Docker & Kubernetes Monitoring',
  description: 'Real-time monitoring dashboard for Docker containers and Kubernetes pods with UneeQ branding',
  icons: {
    icon: '/assets/logos/logo-stacked-color.png',
    shortcut: '/assets/logos/logo-stacked-color.png',
    apple: '/assets/logos/logo-stacked-color.png',
  },
};

export const viewport: Viewport = {
  width: 'device-width',
  initialScale: 1,
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="" />
        <link
          href="https://fonts.googleapis.com/css2?family=Manrope:wght@400;600;700&family=Inter:wght@400;500;600;700&display=swap"
          rel="stylesheet"
        />
      </head>
      <body className="font-inter antialiased">
        <div className="min-h-screen bg-gray-50 dark:bg-gray-900 transition-colors">
          {children}
        </div>
      </body>
    </html>
  );
}
