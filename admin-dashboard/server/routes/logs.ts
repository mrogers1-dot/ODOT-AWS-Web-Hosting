// server/routes/logs.ts
//
// API routes for CloudWatch log access.
// GET /api/logs/:name/:stage — get recent logs
// POST /api/logs/:name/:stage/search — search logs with query
//
// Requirements: 14.20

import { Router, Request, Response } from 'express';
import { CloudWatchLogsClient, FilterLogEventsCommand, StartQueryCommand, GetQueryResultsCommand } from '@aws-sdk/client-cloudwatch-logs';

const router = Router();
const logsClient = new CloudWatchLogsClient({ region: process.env.AWS_REGION || 'us-east-2' });

/**
 * GET /api/logs/:name/:stage
 * Returns recent log events for the specified application.
 */
router.get('/:name/:stage', async (req: Request, res: Response) => {
  try {
    const { name, stage } = req.params;
    const logGroupName = `/ecs/${name}/${stage}`;
    const limit = parseInt(req.query.limit as string) || 100;

    const result = await logsClient.send(new FilterLogEventsCommand({
      logGroupName,
      limit,
      interleaved: true,
    }));

    res.json({
      logGroup: logGroupName,
      events: (result.events || []).map(event => ({
        timestamp: event.timestamp,
        message: event.message,
        logStreamName: event.logStreamName,
      })),
    });
  } catch (error) {
    console.error('Error fetching logs:', error);
    res.status(500).json({ error: 'Failed to fetch logs' });
  }
});

/**
 * POST /api/logs/:name/:stage/search
 * Searches logs using CloudWatch Logs Insights query.
 */
router.post('/:name/:stage/search', async (req: Request, res: Response) => {
  try {
    const { name, stage } = req.params;
    const { query, startTime, endTime } = req.body;
    const logGroupName = `/ecs/${name}/${stage}`;

    const defaultEndTime = Math.floor(Date.now() / 1000);
    const defaultStartTime = defaultEndTime - 3600; // Last hour

    const startResult = await logsClient.send(new StartQueryCommand({
      logGroupName,
      queryString: query || 'fields @timestamp, @message | sort @timestamp desc | limit 100',
      startTime: startTime || defaultStartTime,
      endTime: endTime || defaultEndTime,
    }));

    // Poll for results (max 10 seconds)
    let results = null;
    for (let i = 0; i < 10; i++) {
      await new Promise(resolve => setTimeout(resolve, 1000));
      const queryResult = await logsClient.send(new GetQueryResultsCommand({
        queryId: startResult.queryId,
      }));

      if (queryResult.status === 'Complete') {
        results = queryResult.results;
        break;
      }
    }

    res.json({
      logGroup: logGroupName,
      queryId: startResult.queryId,
      results: results || [],
    });
  } catch (error) {
    console.error('Error searching logs:', error);
    res.status(500).json({ error: 'Failed to search logs' });
  }
});

export { router as logsRouter };
