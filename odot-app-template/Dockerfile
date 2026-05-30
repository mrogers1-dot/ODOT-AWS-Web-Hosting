# Dockerfile — ODOT Traffic Dashboard
#
# Multi-stage build: Vite builds the React frontend, Express serves everything.
# Runs as non-root user (UID 1000) for ECS Fargate security compliance.

# =============================================================================
# Stage 1: Build the React frontend
# =============================================================================
FROM node:20-alpine AS build

WORKDIR /app

# Copy dependency manifests first for better layer caching
COPY package*.json ./

# Install ALL dependencies (including devDependencies for Vite build)
RUN npm ci

# Copy source files
COPY . .

# Build the React app
RUN npm run build

# =============================================================================
# Stage 2: Production runtime
# =============================================================================
FROM node:20-alpine AS production

WORKDIR /app

# Copy package files and install production dependencies only
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force

# Copy the Express server
COPY server.js ./

# Copy the built frontend from the build stage
COPY --from=build /app/dist ./dist

# Use the built-in node user (UID 1000) — no need to create one
USER node

# OHGO API key (public domain, not sensitive)
ENV OHGO_API_KEY=d0215db2-60e6-4e54-b0cd-04ecda3a5346
ENV PORT=8080
ENV NODE_ENV=production

# Expose the application port
EXPOSE 8080

# Health check for ECS/ALB
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

# Start the server
CMD ["node", "server.js"]
