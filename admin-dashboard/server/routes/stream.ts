// server/routes/stream.ts
//
// Server-Sent Events (SSE) endpoint for real-time dashboard updates.
// Pushes status-change events to connected clients when application
// status transitions (healthy/degraded/down).
//
// SSE is chosen over WebSockets because traffic is server→client only
// and SSE works cleanly through the ALB without upgrade negotiation.
//
// Requirements: 27.1, 27.2

import { Router, Request, Response } from 'express';
import { ECSClient, ListServicesCommand, DescribeServicesCommand } from '@aws-sdk/client-ecs';

const router = Router();
const ecsClient = new ECSClient({ region: process.env.AWS_REGION || 'us-east-2' });

// Connected SSE clients
const clients: Set<Response> = new Set();

// Last known status per service (for change detection)
const lastStatus: Map<string, string> = new Map();

const CLUSTERS = ['WebHosting-Dev', 'WebHosting-Test', 'WebHosting-Prod'];

/**
 * GET /api/stream
 * Server-Sent Events endpoint. Keeps the connection open and pushes
 * status-change events when application status transitions.
 */
router.get('/', (req: Request, res: Response) => {
  // Set SSE headers
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.setHeader('X-Accel-Buffering', 'no'); // Disable nginx buffering

  // Send initial connection event
  res.write(`data: ${JSON.stringify({ type: 'connected', timestamp: new Date().toISOString() })}\n\n`);

  // Add to connected clients
  clients.add(res);

  // Remove on disconnect
  req.on('close', () => {
    clients.delete(res);
  });
});

/**
 * Broadcasts a status-change event to all connected SSE clients.
 */
function broadcastStatusChange(serviceName: string, stage: string, oldStatus: string, newStatus: string): void {
  const event = {
    type: 'status-change',
    service: serviceName,
    stage,
    oldStatus,
    newStatus,
    timestamp: new Date().toISOString(),
  };

  const message = `data: ${JSON.stringify(event)}\n\n`;

  for (const client of clients) {
    client.write(message);
  }
}

/**
 * Determines service status from ECS service state.
 */
function determineStatus(desired: number, running: number): string {
  if (running === 0 && desired > 0) return 'down';
  if (running < desired) return 'degraded';
  return 'healthy';
}

/**
 * Polls ECS clusters for status changes and broadcasts to SSE clients.
 * Runs every 10 seconds.
 */
async function pollForChanges(): Promise<void> {
  if (clients.size === 0) return; // No clients connected, skip polling

  try {
    for (const cluster of CLUSTERS) {
      const stage = cluster.replace('WebHosting-', '').toLowerCase();

      const listResult = await ecsClient.send(new ListServicesCommand({
        cluster,
        maxResults: 100,
      }));

      if (!listResult.serviceArns || listResult.serviceArns.length === 0) continue;

      const describeResult = await ecsClient.send(new DescribeServicesCommand({
        cluster,
        services: listResult.serviceArns,
      }));

      for (const service of describeResult.services || []) {
        const key = `${service.serviceName}-${stage}`;
        const newStatus = determineStatus(
          service.desiredCount || 0,
          service.runningCount || 0
        );

        const oldStatus = lastStatus.get(key);
        if (oldStatus && oldStatus !== newStatus) {
          broadcastStatusChange(service.serviceName || '', stage, oldStatus, newStatus);
        }

        lastStatus.set(key, newStatus);
      }
    }
  } catch (error) {
    console.error('SSE poll error:', error);
  }
}

// Start polling every 10 seconds
setInterval(pollForChanges, 10_000);

export { router as streamRouter };
