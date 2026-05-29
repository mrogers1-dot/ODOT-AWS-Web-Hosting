// server/index.ts
//
// Entry point for the ODOT Admin Dashboard backend API.
// Express app with Cognito JWT authentication, RBAC middleware,
// and audit logging for all mutating operations.
//
// Requirements: 14.1, 14.2, 14.3

import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import { authMiddleware } from './middleware/auth';
import { auditLogMiddleware } from './middleware/auditLog';
import { appsRouter } from './routes/apps';
import { actionsRouter } from './routes/actions';
import { logsRouter } from './routes/logs';
import { auditRouter } from './routes/audit';

const app = express();
const PORT = process.env.PORT || 3000;

// Security middleware
app.use(helmet());
app.use(cors({
  origin: process.env.CORS_ORIGIN || 'http://localhost:5173',
  credentials: true,
}));
app.use(express.json());

// Health check endpoint (no auth required)
app.get('/health', (_req, res) => {
  res.status(200).json({ status: 'healthy', timestamp: new Date().toISOString() });
});

// Authentication middleware for all /api routes
app.use('/api', authMiddleware);

// Audit logging for mutating operations
app.use('/api', auditLogMiddleware);

// API routes
app.use('/api/apps', appsRouter);
app.use('/api/actions', actionsRouter);
app.use('/api/logs', logsRouter);
app.use('/api/audit', auditRouter);

// Start server
if (process.env.NODE_ENV !== 'test') {
  app.listen(PORT, () => {
    console.log(`ODOT Admin Dashboard API listening on port ${PORT}`);
  });
}

export { app };
