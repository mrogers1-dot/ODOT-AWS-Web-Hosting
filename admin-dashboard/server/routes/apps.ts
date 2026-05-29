// server/routes/apps.ts
//
// API routes for listing and describing ECS applications.
// GET /api/apps — list all apps with status
// GET /api/apps/:name/:stage — get detailed app info
//
// Requirements: 14.7, 14.8, 14.9

import { Router, Request, Response } from 'express';
import { ECSClient, ListServicesCommand, DescribeServicesCommand } from '@aws-sdk/client-ecs';

const router = Router();
const ecsClient = new ECSClient({ region: process.env.AWS_REGION || 'us-east-2' });

const CLUSTERS = ['WebHosting-Dev', 'WebHosting-Test', 'WebHosting-Prod'];

/**
 * GET /api/apps
 * Lists all ECS services across all clusters with their current status.
 */
router.get('/', async (_req: Request, res: Response) => {
  try {
    const apps: Array<{
      name: string;
      stage: string;
      status: string;
      desiredCount: number;
      runningCount: number;
      cluster: string;
    }> = [];

    for (const cluster of CLUSTERS) {
      const listResult = await ecsClient.send(new ListServicesCommand({
        cluster,
        maxResults: 100,
      }));

      if (listResult.serviceArns && listResult.serviceArns.length > 0) {
        const describeResult = await ecsClient.send(new DescribeServicesCommand({
          cluster,
          services: listResult.serviceArns,
        }));

        for (const service of describeResult.services || []) {
          const stage = cluster.replace('WebHosting-', '').toLowerCase();
          apps.push({
            name: service.serviceName || 'unknown',
            stage,
            status: service.status || 'UNKNOWN',
            desiredCount: service.desiredCount || 0,
            runningCount: service.runningCount || 0,
            cluster,
          });
        }
      }
    }

    res.json({ apps });
  } catch (error) {
    console.error('Error listing apps:', error);
    res.status(500).json({ error: 'Failed to list applications' });
  }
});

/**
 * GET /api/apps/:name/:stage
 * Gets detailed information about a specific application service.
 */
router.get('/:name/:stage', async (req: Request, res: Response) => {
  try {
    const { name, stage } = req.params;
    const cluster = `WebHosting-${stage.charAt(0).toUpperCase() + stage.slice(1)}`;

    const result = await ecsClient.send(new DescribeServicesCommand({
      cluster,
      services: [name],
    }));

    if (!result.services || result.services.length === 0) {
      res.status(404).json({ error: `Service ${name} not found in ${cluster}` });
      return;
    }

    const service = result.services[0];
    res.json({
      name: service.serviceName,
      stage,
      cluster,
      status: service.status,
      desiredCount: service.desiredCount,
      runningCount: service.runningCount,
      pendingCount: service.pendingCount,
      taskDefinition: service.taskDefinition,
      deployments: service.deployments,
      events: service.events?.slice(0, 10),
    });
  } catch (error) {
    console.error('Error describing app:', error);
    res.status(500).json({ error: 'Failed to describe application' });
  }
});

export { router as appsRouter };
