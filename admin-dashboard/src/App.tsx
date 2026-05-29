// src/App.tsx
//
// Root component for the ODOT Admin Dashboard frontend.
// React + TypeScript + Tailwind CSS.
//
// Requirements: 14.5, 14.7

import React from 'react';

export function App() {
  return (
    <div className="min-h-screen bg-gray-50">
      <header className="bg-white shadow-sm border-b border-gray-200">
        <div className="max-w-7xl mx-auto px-4 py-4 flex items-center justify-between">
          <h1 className="text-xl font-semibold text-gray-900">
            ODOT Web Hosting Dashboard
          </h1>
          <nav className="flex gap-4">
            <button className="px-3 py-1.5 text-sm font-medium text-blue-600 bg-blue-50 rounded-md">
              Internal
            </button>
            <button className="px-3 py-1.5 text-sm font-medium text-gray-600 hover:bg-gray-100 rounded-md">
              External
            </button>
          </nav>
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
