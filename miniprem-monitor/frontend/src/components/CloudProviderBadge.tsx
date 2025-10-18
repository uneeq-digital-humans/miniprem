import React from 'react';

interface CloudProviderBadgeProps {
  provider: 'eks' | 'aks' | 'gke' | 'unknown';
  className?: string;
}

const CloudProviderBadge: React.FC<CloudProviderBadgeProps> = ({ provider, className = '' }) => {
  const config = {
    eks: {
      label: 'AWS EKS',
      bgColor: 'bg-orange-500',
      icon: '☁'
    },
    aks: {
      label: 'Azure AKS',
      bgColor: 'bg-blue-500',
      icon: '☁'
    },
    gke: {
      label: 'Google GKE',
      bgColor: 'bg-green-500',
      icon: '☁'
    },
    unknown: {
      label: 'Unknown',
      bgColor: 'bg-gray-500',
      icon: '?'
    }
  };

  const { label, bgColor, icon } = config[provider] || config.unknown;

  return (
    <span
      className={`inline-flex items-center px-3 py-1 rounded-full text-white text-sm font-medium ${bgColor} ${className}`}
      title={`Cloud Provider: ${label}`}
      data-testid={`cloud-provider-badge-${provider}`}
    >
      <span className="mr-1.5">{icon}</span>
      {label}
    </span>
  );
};

export default CloudProviderBadge;
