// src/components/AuthCallback.tsx
//
// Handles the OAuth2 callback from Cognito Hosted UI.
// Extracts the authorization code from the URL and exchanges it for tokens.

import React, { useEffect, useState } from 'react';
import { exchangeCodeForTokens, getLoginUrl } from '../auth';

export function AuthCallback() {
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const code = params.get('code');
    const errorParam = params.get('error');
    const errorDescription = params.get('error_description');

    if (errorParam) {
      setError(`${errorParam}: ${errorDescription || 'Unknown error'}`);
      return;
    }

    if (!code) {
      setError('No authorization code received');
      return;
    }

    exchangeCodeForTokens(code)
      .then(() => {
        // Clear the code from the URL and redirect to dashboard
        window.location.href = '/';
      })
      .catch((err) => {
        setError(err.message || 'Token exchange failed');
      });
  }, []);

  if (error) {
    return (
      <div className="min-h-screen bg-gray-50 flex items-center justify-center">
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-8 max-w-md w-full">
          <h2 className="text-lg font-semibold text-red-600 mb-2">
            Authentication Error
          </h2>
          <p className="text-gray-600 text-sm mb-4">{error}</p>
          <a
            href={getLoginUrl()}
            className="inline-block px-4 py-2 text-sm font-medium text-white bg-blue-600 rounded-md hover:bg-blue-700"
          >
            Try Again
          </a>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gray-50 flex items-center justify-center">
      <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-8">
        <p className="text-gray-500 text-sm">Completing login...</p>
      </div>
    </div>
  );
}

export default AuthCallback;
