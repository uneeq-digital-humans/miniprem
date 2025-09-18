import type { Metadata, Viewport } from 'next';
import '../styles/globals.css';

export const metadata: Metadata = {
  title: 'MiniPrem Monitor | Real-time Docker & Kubernetes Monitoring',
  description: 'Real-time monitoring dashboard for Docker containers and Kubernetes pods with UneeQ branding',
  icons: {
    icon: 'https://cdn.uneeq.io/hosted-experience/assets/favicon.png',
    shortcut: 'https://cdn.uneeq.io/hosted-experience/assets/favicon.png',
    apple: 'https://cdn.uneeq.io/hosted-experience/assets/favicon.png',
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
          href="https://fonts.googleapis.com/css2?family=Manrope:wght@400;600;700&display=swap"
          rel="stylesheet"
        />
      </head>
      <body className="font-manrope antialiased">
        <div className="min-h-screen bg-gray-50 dark:bg-gray-900 transition-colors">
          {children}
        </div>
      </body>
    </html>
  );
}