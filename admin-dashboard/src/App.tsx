// src/App.tsx
//
// Root component for the ODOT Admin Dashboard frontend.
// React + TypeScript + Tailwind CSS.
//
// Includes auth gate: redirects to Cognito Hosted UI if not authenticated.
// Handles OAuth callback at /callback path.
//
// Requirements: 14.5, 14.7

import React, { useEffect, useState } from 'react';
import { isAuthenticated, getLoginUrl, getLogoutUrl, clearTokens } from './auth';
import { AuthCallback } from './components/AuthCallback';

export function App() {
  const [authChecked, setAuthChecked] = useState(false);
  const [authenticated, setAuthenticated] = useState(false);

  useEffect(() => {
    // Check if we're on the callback path
    if (window.location.pathname === '/callback') {
      setAuthChecked(true);
      return;
    }

    // Check authentication status
    if (isAuthenticated()) {
      setAuthenticated(true);
      setAuthChecked(true);
    } else {
      // Redirect to Cognito Hosted UI
      window.location.href = getLoginUrl();
    }
  }, []);

  // Render callback handler
  if (window.location.pathname === '/callback') {
    return <AuthCallback />;
  }

  // Show nothing while checking auth (prevents flash)
  if (!authChecked) {
    return null;
  }

  // Not authenticated — redirect is in progress
  if (!authenticated) {
    return null;
  }

  const handleLogout = () => {
    clearTokens();
    window.location.href = getLogoutUrl();
  };

  return (
    <div className="min-h-screen bg-gray-50">
      <header className="bg-white shadow-sm border-b border-gray-200">
        <div className="max-w-7xl mx-auto px-4 py-4 flex items-center justify-between">
          <h1 className="text-xl font-semibold text-gray-900">
            ODOT Web Hosting Dashboard
          </h1>
          <div className="flex items-center gap-4">
            <nav className="flex gap-4">
              <button className="px-3 py-1.5 text-sm font-medium text-blue-600 bg-blue-50 rounded-md">
                Internal
              </button>
              <button className="px-3 py-1.5 text-sm font-medium text-gray-600 hover:bg-gray-100 rounded-md">
                External
              </button>
            </nav>
            <button
              onClick={handleLogout}
              className="px-3 py-1.5 text-sm font-medium text-gray-600 hover:bg-gray-100 rounded-md border border-gray-300"
            >
              Logout
            </button>
          </div>
        </div>
      </header>
      <main className="max-w-7xl mx-auto px-4 py-8">
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {/* AppCard components will be rendered here */}
          <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
            <p className="text-gray-500 text-sm">Loading applications...</p>
          </div>
        </div>
      </main>
    </div>
  );
}

export default App;
