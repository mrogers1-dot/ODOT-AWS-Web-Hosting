// server/routes/audit.ts
//
// API routes for viewing audit log entries.
// GET /api/audit/:name/:stage — get audit entries for an app
// GET /api/audit/user/:userId — get audit entries by user
//
// Requirements: 14.18

import { Router, Request, Response } from 'express';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, QueryCommand } from '@aws-sdk/lib-dynamodb';

const router = Router();
const dynamoClient = new DynamoDBClient({ region: process.env.AWS_REGION || 'us-east-2' });
const docClient = DynamoDBDocumentClient.from(dynamoClient);

const AUDIT_TABLE = process.env.AUDIT_TABLE_NAME || 'odot-dashboard-audit';

/**
 * GET /api/audit/:name/:stage
 * Returns audit log entries for a specific application and stage.
 */
router.get('/:name/:stage', async (req: Request, res: Response) => {
  try {
    const { name, stage } = req.params;
    const limit = parseInt(req.query.limit as string) || 50;

    const result = await docClient.send(new QueryCommand({
      TableName: AUDIT_TABLE,
      KeyConditionExpression: 'pk = :pk',
      ExpressionAttributeValues: {
        ':pk': `${name}#${stage}`,
      },
      ScanIndexForward: false, // Most recent first
      Limit: limit,
    }));

    res.json({
      app: name,
      stage,
      entries: result.Items || [],
    });
  } catch (error) {
    console.error('Error fetching audit logs:', error);
    res.status(500).json({ error: 'Failed to fetch audit logs' });
  }
});

/**
 * GET /api/audit/user/:userId
 * Returns audit log entries for a specific user (via GSI).
 */
router.get('/user/:userId', async (req: Request, res: Response) => {
  try {
    const { userId } = req.params;
    const limit = parseInt(req.query.limit as string) || 50;

    const result = await docClient.send(new QueryCommand({
      TableName: AUDIT_TABLE,
      IndexName: 'user-index',
      KeyConditionExpression: 'userId = :userId',
      ExpressionAttributeValues: {
        ':userId': userId,
      },
      ScanIndexForward: false,
      Limit: limit,
    }));

    res.json({
      userId,
      entries: result.Items || [],
    });
  } catch (error) {
    console.error('Error fetching user audit logs:', error);
    res.status(500).json({ error: 'Failed to fetch user audit logs' });
  }
});

export { router as auditRouter };
