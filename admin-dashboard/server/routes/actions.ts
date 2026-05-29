// server/routes/actions.ts
//
// API routes for mutating ECS service operations.
// All routes enforce RBAC: Developers can mutate Dev/Test, Admins can mutate all.
// Rollback and Block/Unblock IP always require Admin regardless of stage.
//
// Requirements: 14.16, 14.20–14.28

import { Router, Request, Response } from 'express';
import { requireRole, requireStageAccess } from '../middleware/auth';
import { ECSClient, UpdateServiceCommand, StopTaskCommand, RegisterTaskDefinitionCommand, DescribeTaskDefinitionCommand, ListTasksCommand } from '@aws-sdk/client-ecs';
import { WAFV2Client, GetIPSetCommand, UpdateIPSetCommand } from '@aws-sdk/client-wafv2';

const router = Router();
const ecsClient = new ECSClient({ region: process.env.AWS_REGION || 'us-east-2' });
const wafClient = new WAFV2Client({ region: process.env.AWS_REGION || 'us-east-2' });

/**
 * POST /api/actions/:name/:stage/restart
 * Restarts the ECS service by forcing a new deployment.
 */
router.post('/:name/:stage/restart', requireStageAccess, async (req: Request, res: Response) => {
  try {
    const { name, stage } = req.params;
    const cluster = `WebHosting-${stage.charAt(0).toUpperCase() + stage.slice(1)}`;

    await ecsClient.send(new UpdateServiceCommand({
      cluster,
      service: name,
      forceNewDeployment: true,
    }));

    res.json({ success: true, action: 'restart', service: name, stage });
  } catch (error) {
    console.error('Error restarting service:', error);
    res.status(500).json({ error: 'Failed to restart service' });
  }
});

/**
 * POST /api/actions/:name/:stage/stop
 * Scales the service to 0 desired tasks (effectively stopping it).
 */
router.post('/:name/:stage/stop', requireStageAccess, async (req: Request, res: Response) => {
  try {
    const { name, stage } = req.params;
    const cluster = `WebHosting-${stage.charAt(0).toUpperCase() + stage.slice(1)}`;

    await ecsClient.send(new UpdateServiceCommand({
      cluster,
      service: name,
      desiredCount: 0,
    }));

    res.json({ success: true, action: 'stop', service: name, stage });
  } catch (error) {
    console.error('Error stopping service:', error);
    res.status(500).json({ error: 'Failed to stop service' });
  }
});

/**
 * POST /api/actions/:name/:stage/start
 * Scales the service back to 2 desired tasks (minimum HA count).
 */
router.post('/:name/:stage/start', requireStageAccess, async (req: Request, res: Response) => {
  try {
    const { name, stage } = req.params;
    const cluster = `WebHosting-${stage.charAt(0).toUpperCase() + stage.slice(1)}`;

    await ecsClient.send(new UpdateServiceCommand({
      cluster,
      service: name,
      desiredCount: 2,
    }));

    res.json({ success: true, action: 'start', service: name, stage });
  } catch (error) {
    console.error('Error starting service:', error);
    res.status(500).json({ error: 'Failed to start service' });
  }
});

/**
 * POST /api/actions/:name/:stage/scale
 * Scales the service to the specified desired count.
 */
router.post('/:name/:stage/scale', requireStageAccess, async (req: Request, res: Response) => {
  try {
    const { name, stage } = req.params;
    const { desiredCount } = req.body;
    const cluster = `WebHosting-${stage.charAt(0).toUpperCase() + stage.slice(1)}`;

    if (!desiredCount || desiredCount < 0 || desiredCount > 50) {
      res.status(400).json({ error: 'desiredCount must be between 0 and 50' });
      return;
    }

    await ecsClient.send(new UpdateServiceCommand({
      cluster,
      service: name,
      desiredCount,
    }));

    res.json({ success: true, action: 'scale', service: name, stage, desiredCount });
  } catch (error) {
    console.error('Error scaling service:', error);
    res.status(500).json({ error: 'Failed to scale service' });
  }
});

/**
 * POST /api/actions/:name/:stage/rollback
 * Rolls back to a previous task definition revision. Requires Admin role.
 */
router.post('/:name/:stage/rollback', requireRole('Admin'), async (req: Request, res: Response) => {
  try {
    const { name, stage } = req.params;
    const { taskDefinitionArn } = req.body;
    const cluster = `WebHosting-${stage.charAt(0).toUpperCase() + stage.slice(1)}`;

    if (!taskDefinitionArn) {
      res.status(400).json({ error: 'taskDefinitionArn is required' });
      return;
    }

    await ecsClient.send(new UpdateServiceCommand({
      cluster,
      service: name,
      taskDefinition: taskDefinitionArn,
      forceNewDeployment: true,
    }));

    res.json({ success: true, action: 'rollback', service: name, stage, taskDefinitionArn });
  } catch (error) {
    console.error('Error rolling back service:', error);
    res.status(500).json({ error: 'Failed to rollback service' });
  }
});

/**
 * POST /api/actions/waf/block-ip
 * Adds an IP address to the WAF block list. Requires Admin role.
 */
router.post('/waf/block-ip', requireRole('Admin'), async (req: Request, res: Response) => {
  try {
    const { ipAddress } = req.body;
    const ipSetId = process.env.WAF_IP_SET_ID || '';
    const ipSetName = process.env.WAF_IP_SET_NAME || 'odot-dashboard-blocked-ips';

    if (!ipAddress) {
      res.status(400).json({ error: 'ipAddress is required (CIDR format, e.g., 1.2.3.4/32)' });
      return;
    }

    // Get current IP set to obtain lock token
    const getResult = await wafClient.send(new GetIPSetCommand({
      Id: ipSetId,
      Name: ipSetName,
      Scope: 'REGIONAL',
    }));

    const currentAddresses = getResult.IPSet?.Addresses || [];
    const updatedAddresses = [...currentAddresses, ipAddress];

    await wafClient.send(new UpdateIPSetCommand({
      Id: ipSetId,
      Name: ipSetName,
      Scope: 'REGIONAL',
      Addresses: updatedAddresses,
      LockToken: getResult.LockToken,
    }));

    res.json({ success: true, action: 'block-ip', ipAddress });
  } catch (error) {
    console.error('Error blocking IP:', error);
    res.status(500).json({ error: 'Failed to block IP address' });
  }
});

/**
 * POST /api/actions/waf/unblock-ip
 * Removes an IP address from the WAF block list. Requires Admin role.
 */
router.post('/waf/unblock-ip', requireRole('Admin'), async (req: Request, res: Response) => {
  try {
    const { ipAddress } = req.body;
    const ipSetId = process.env.WAF_IP_SET_ID || '';
    const ipSetName = process.env.WAF_IP_SET_NAME || 'odot-dashboard-blocked-ips';

    if (!ipAddress) {
      res.status(400).json({ error: 'ipAddress is required' });
      return;
    }

    const getResult = await wafClient.send(new GetIPSetCommand({
      Id: ipSetId,
      Name: ipSetName,
      Scope: 'REGIONAL',
    }));

    const currentAddresses = getResult.IPSet?.Addresses || [];
    const updatedAddresses = currentAddresses.filter(addr => addr !== ipAddress);

    await wafClient.send(new UpdateIPSetCommand({
      Id: ipSetId,
      Name: ipSetName,
      Scope: 'REGIONAL',
      Addresses: updatedAddresses,
      LockToken: getResult.LockToken,
    }));

    res.json({ success: true, action: 'unblock-ip', ipAddress });
  } catch (error) {
    console.error('Error unblocking IP:', error);
    res.status(500).json({ error: 'Failed to unblock IP address' });
  }
});

export { router as actionsRouter };
