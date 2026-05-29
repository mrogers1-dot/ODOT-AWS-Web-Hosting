// server/middleware/auth.ts
//
// JWT authentication middleware for the admin dashboard API.
// Validates tokens against the Cognito User Pool JWKS endpoint.
// Extracts the user's role from the custom:role claim for RBAC.
//
// Requirements: 14.1, 14.2, 14.3

import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import jwksClient from 'jwks-rsa';

// Extend Express Request to include user context
declare global {
  namespace Express {
    interface Request {
      user?: {
        sub: string;
        email: string;
        role: string;
        groups: string[];
      };
    }
  }
}

const COGNITO_USER_POOL_ID = process.env.COGNITO_USER_POOL_ID || '';
const COGNITO_REGION = process.env.AWS_REGION || 'us-east-2';
const JWKS_URI = `https://cognito-idp.${COGNITO_REGION}.amazonaws.com/${COGNITO_USER_POOL_ID}/.well-known/jwks.json`;

const client = jwksClient({
  jwksUri: JWKS_URI,
  cache: true,
  cacheMaxAge: 600000, // 10 minutes
});

function getKey(header: jwt.JwtHeader, callback: jwt.SigningKeyCallback): void {
  client.getSigningKey(header.kid, (err, key) => {
    if (err) {
      callback(err);
      return;
    }
    const signingKey = key?.getPublicKey();
    callback(null, signingKey);
  });
}

/**
 * Extracts the user role from the token claims.
 * Okta groups are mapped to custom:role in Cognito.
 * Returns 'Admin' if the user is in the admin group, otherwise 'Developer'.
 */
function extractRole(claims: Record<string, unknown>): string {
  const roleValue = claims['custom:role'] as string | undefined;
  if (!roleValue) return 'Developer';

  // Okta groups may be comma-separated or a JSON array
  const groups = roleValue.includes(',')
    ? roleValue.split(',').map(g => g.trim())
    : [roleValue.trim()];

  if (groups.some(g => g.toLowerCase().includes('admin'))) {
    return 'Admin';
  }
  return 'Developer';
}

/**
 * Authentication middleware.
 * Validates the Bearer token from the Authorization header against Cognito JWKS.
 * Populates req.user with sub, email, role, and groups.
 */
export function authMiddleware(req: Request, res: Response, next: NextFunction): void {
  const authHeader = req.headers.authorization;

  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    res.status(401).json({ error: 'Missing or invalid Authorization header' });
    return;
  }

  const token = authHeader.substring(7);

  jwt.verify(token, getKey, { algorithms: ['RS256'] }, (err, decoded) => {
    if (err) {
      res.status(401).json({ error: 'Invalid or expired token' });
      return;
    }

    const claims = decoded as Record<string, unknown>;
    req.user = {
      sub: claims.sub as string,
      email: (claims.email as string) || '',
      role: extractRole(claims),
      groups: ((claims['custom:role'] as string) || '').split(',').map(g => g.trim()),
    };

    next();
  });
}

/**
 * RBAC middleware factory.
 * Returns middleware that checks if the user has the required role for the action.
 * - Developer: can mutate Dev/Test resources only
 * - Admin: can mutate all resources, including Prod
 * - Rollback and Block/Unblock IP always require Admin
 */
export function requireRole(requiredRole: 'Admin' | 'Developer') {
  return (req: Request, res: Response, next: NextFunction): void => {
    if (!req.user) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    if (requiredRole === 'Admin' && req.user.role !== 'Admin') {
      res.status(403).json({ error: 'Admin role required for this action' });
      return;
    }

    next();
  };
}

/**
 * Stage-aware RBAC middleware.
 * Developers can only mutate Dev/Test. Admins can mutate all stages.
 */
export function requireStageAccess(req: Request, res: Response, next: NextFunction): void {
  if (!req.user) {
    res.status(401).json({ error: 'Authentication required' });
    return;
  }

  const stage = req.params.stage || req.body?.stage;

  if (stage === 'prod' && req.user.role !== 'Admin') {
    res.status(403).json({
      error: 'Admin role required for production operations',
      requiredRole: 'Admin',
      currentRole: req.user.role,
    });
    return;
  }

  next();
}
