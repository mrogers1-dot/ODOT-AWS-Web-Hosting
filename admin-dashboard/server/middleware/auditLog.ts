// server/middleware/auditLog.ts
//
// Audit logging middleware for the admin dashboard.
// Automatically logs all mutating operations (POST, PUT, PATCH, DELETE)
// to DynamoDB and publishes a notification to SNS.
//
// Requirements: 14.18, 14.19

import { Request, Response, NextFunction } from 'express';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, PutCommand } from '@aws-sdk/lib-dynamodb';
import { SNSClient, PublishCommand } from '@aws-sdk/client-sns';

const dynamoClient = new DynamoDBClient({ region: process.env.AWS_REGION || 'us-east-2' });
const docClient = DynamoDBDocumentClient.from(dynamoClient);
const snsClient = new SNSClient({ region: process.env.AWS_REGION || 'us-east-2' });

const AUDIT_TABLE = process.env.AUDIT_TABLE_NAME || 'odot-dashboard-audit';
const SNS_TOPIC_ARN = process.env.SNS_TOPIC_ARN || '';

// TTL: 90 days from now (in seconds)
const TTL_DAYS = 90;

/**
 * Audit logging middleware.
 * Intercepts mutating requests (POST, PUT, PATCH, DELETE) and logs them
 * to DynamoDB after the response is sent. Also publishes to SNS for
 * real-time notification.
 */
export function auditLogMiddleware(req: Request, res: Response, next: NextFunction): void {
  // Only audit mutating operations
  if (!['POST', 'PUT', 'PATCH', 'DELETE'].includes(req.method)) {
    next();
    return;
  }

  // Capture the original end method to log after response
  const originalEnd = res.end;
  const startTime = Date.now();

  res.end = function (...args: Parameters<typeof originalEnd>) {
    const duration = Date.now() - startTime;

    // Log asynchronously — don't block the response
    logAuditEntry({
      userId: req.user?.sub || 'unknown',
      email: req.user?.email || 'unknown',
      role: req.user?.role || 'unknown',
      action: `${req.method} ${req.originalUrl}`,
      body: sanitizeBody(req.body),
      statusCode: res.statusCode,
      duration,
      timestamp: new Date().toISOString(),
      appName: req.params.name || req.body?.appName || 'unknown',
      stage: req.params.stage || req.body?.stage || 'unknown',
    }).catch(err => {
      console.error('Failed to write audit log:', err);
    });

    return originalEnd.apply(res, args);
  } as typeof originalEnd;

  next();
}

interface AuditEntry {
  userId: string;
  email: string;
  role: string;
  action: string;
  body: Record<string, unknown>;
  statusCode: number;
  duration: number;
  timestamp: string;
  appName: string;
  stage: string;
}

/**
 * Writes an audit entry to DynamoDB and publishes to SNS.
 */
async function logAuditEntry(entry: AuditEntry): Promise<void> {
  const ttl = Math.floor(Date.now() / 1000) + (TTL_DAYS * 24 * 60 * 60);

  const item = {
    pk: `${entry.appName}#${entry.stage}`,
    sk: entry.timestamp,
    userId: entry.userId,
    email: entry.email,
    role: entry.role,
    action: entry.action,
    body: entry.body,
    statusCode: entry.statusCode,
    duration: entry.duration,
    ttl,
  };

  // Write to DynamoDB
  await docClient.send(new PutCommand({
    TableName: AUDIT_TABLE,
    Item: item,
  }));

  // Publish to SNS (if configured)
  if (SNS_TOPIC_ARN) {
    await snsClient.send(new PublishCommand({
      TopicArn: SNS_TOPIC_ARN,
      Subject: `Dashboard Action: ${entry.action}`,
      Message: JSON.stringify({
        user: entry.email,
        role: entry.role,
        action: entry.action,
        app: entry.appName,
        stage: entry.stage,
        status: entry.statusCode,
        timestamp: entry.timestamp,
      }, null, 2),
    }));
  }
}

/**
 * Removes sensitive fields from the request body before logging.
 */
function sanitizeBody(body: Record<string, unknown> | undefined): Record<string, unknown> {
  if (!body) return {};
  const sanitized = { ...body };
  // Remove any fields that might contain secrets
  delete sanitized.password;
  delete sanitized.secret;
  delete sanitized.token;
  return sanitized;
}
