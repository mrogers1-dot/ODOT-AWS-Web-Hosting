// src/api.ts
//
// API client for the Admin Dashboard.
// Wraps fetch with automatic Authorization header injection and 401 handling.

import { getAuthHeader, clearTokens, getLoginUrl } from './auth';

/**
 * Authenticated fetch wrapper.
 * Automatically attaches the Bearer token and handles 401 responses
 * by clearing the session and redirecting to login.
 */
export async function apiFetch(
  input: RequestInfo | URL,
  init?: RequestInit
): Promise<Response> {
  const authHeader = getAuthHeader();

  const headers = new Headers(init?.headers);
  if (authHeader) {
    headers.set('Authorization', authHeader.Authorization);
  }

  const response = await fetch(input, {
    ...init,
    headers,
  });

  if (response.status === 401) {
    clearTokens();
    window.location.href = getLoginUrl();
    // Return the response anyway in case caller wants to handle it
    return response;
  }

  return response;
}
