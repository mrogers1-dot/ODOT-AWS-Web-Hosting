# Dockerfile — ODOT Admin Dashboard
#
# Multi-stage build: frontend (Vite/React) + backend (Express/TypeScript)
# Production image runs as non-root user on port 3000.
#
# Requirements: 14.5, 14.6

# =============================================================================
# Stage 1: Install dependencies
# =============================================================================
FROM node:20-alpine AS deps

WORKDIR /app
COPY package*.json ./
RUN npm ci

# =============================================================================
# Stage 2: Build frontend and backend
# =============================================================================
FROM node:20-alpine AS build

WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Build TypeScript backend
RUN npx tsc --outDir dist

# Build React frontend (if vite config exists)
RUN if [ -f "vite.config.ts" ]; then npx vite build; fi

# =============================================================================
# Stage 3: Production image
# =============================================================================
FROM node:20-alpine AS production

# Security: create non-root user
RUN addgroup -g 1000 appgroup && \
    adduser -u 1000 -G appgroup -s /bin/sh -D appuser

WORKDIR /app

# Copy production dependencies only
COPY --from=deps --chown=appuser:appgroup /app/node_modules ./node_modules

# Copy compiled backend
COPY --from=build --chown=appuser:appgroup /app/dist ./dist

# Copy frontend build output (if exists)
COPY --from=build --chown=appuser:appgroup /app/dist/public ./dist/public

# Copy package.json for metadata
COPY --from=build --chown=appuser:appgroup /app/package.json ./

# Switch to non-root user
USER 1000

# Expose dashboard port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

# Start the server
CMD ["node", "dist/server/index.js"]
