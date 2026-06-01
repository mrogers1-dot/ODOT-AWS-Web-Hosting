// src/auth.ts
//
// Authentication utilities for the Admin Dashboard.
// Handles Cognito Hosted UI OAuth2 authorization code flow:
//   - Redirect to login
//   - Exchange auth code for tokens
//   - Token storage (sessionStorage)
//   - Auth header injection
//   - Logout
//
// Works with both POC (Cognito local users) and production (Okta federation)
// since both use the same Cognito token endpoint.

export interface AuthConfig {
  domain: string;
  clientId: string;
  redirectUri: string;
  logoutUri: string;
}

export interface TokenSet {
  id_token: string;
  access_token: string;
  refresh_token?: string;
  expires_at: number; // Unix timestamp (ms)
}

const STORAGE_KEY = 'odot_dashboard_tokens';

/**
 * Reads auth configuration from Vite environment variables.
 */
export function getAuthConfig(): AuthConfig {
  return {
    domain: import.meta.env.VITE_COGNITO_DOMAIN || '',
    clientId: import.meta.env.VITE_COGNITO_CLIENT_ID || '',
    redirectUri: import.meta.env.VITE_COGNITO_REDIRECT_URI || `${window.location.origin}/callback`,
    logoutUri: import.meta.env.VITE_COGNITO_LOGOUT_URI || window.location.origin,
  };
}

/**
 * Constructs the Cognito Hosted UI login URL.
 */
export function getLoginUrl(): string {
  const config = getAuthConfig();
  const params = new URLSearchParams({
    response_type: 'code',
    client_id: config.clientId,
    redirect_uri: config.redirectUri,
    scope: 'openid profile email',
  });
  return `https://${config.domain}/oauth2/authorize?${params.toString()}`;
}

/**
 * Constructs the Cognito logout URL.
 */
export function getLogoutUrl(): string {
  const config = getAuthConfig();
  const params = new URLSearchParams({
    client_id: config.clientId,
    logout_uri: config.logoutUri,
  });
  return `https://${config.domain}/logout?${params.toString()}`;
}

/**
 * Exchanges an authorization code for tokens via the Cognito token endpoint.
 */
export async function exchangeCodeForTokens(code: string): Promise<TokenSet> {
  const config = getAuthConfig();
  const tokenUrl = `https://${config.domain}/oauth2/token`;

  const body = new URLSearchParams({
    grant_type: 'authorization_code',
    client_id: config.clientId,
    redirect_uri: config.redirectUri,
    code,
  });

  const response = await fetch(tokenUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: body.toString(),
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`Token exchange failed: ${response.status} ${error}`);
  }

  const data = await response.json();

  const tokenSet: TokenSet = {
    id_token: data.id_token,
    access_token: data.access_token,
    refresh_token: data.refresh_token,
    expires_at: Date.now() + (data.expires_in * 1000),
  };

  storeTokens(tokenSet);
  return tokenSet;
}

/**
 * Retrieves stored tokens from sessionStorage.
 */
export function getStoredTokens(): TokenSet | null {
  const raw = sessionStorage.getItem(STORAGE_KEY);
  if (!raw) return null;

  try {
    return JSON.parse(raw) as TokenSet;
  } catch {
    return null;
  }
}

/**
 * Stores tokens in sessionStorage.
 */
export function storeTokens(tokens: TokenSet): void {
  sessionStorage.setItem(STORAGE_KEY, JSON.stringify(tokens));
}

/**
 * Clears stored tokens.
 */
export function clearTokens(): void {
  sessionStorage.removeItem(STORAGE_KEY);
}

/**
 * Checks if the user has a valid (non-expired) token.
 */
export function isAuthenticated(): boolean {
  const tokens = getStoredTokens();
  if (!tokens) return false;
  return Date.now() < tokens.expires_at;
}

/**
 * Returns the Authorization header value, or null if not authenticated.
 */
export function getAuthHeader(): { Authorization: string } | null {
  const tokens = getStoredTokens();
  if (!tokens || Date.now() >= tokens.expires_at) return null;
  return { Authorization: `Bearer ${tokens.id_token}` };
}
