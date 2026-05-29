# Dockerfile
#
# Multi-stage build template for ODOT web applications.
# Uses minimal base image and runs as non-root user (UID 1000) for security.
#
# Customize the build stage for your application runtime (Node.js, Python, .NET, Java, etc.)
# The production stage uses Alpine for minimal attack surface.
#
# Requirements: 7.2, 9.8

# =============================================================================
# Stage 1: Build
# Install dependencies and compile the application.
# =============================================================================
FROM node:20-alpine AS build

WORKDIR /app

# Copy dependency manifests first for better layer caching
COPY package*.json ./

# Install dependencies (production only for smaller image)
RUN npm ci --only=production

# Copy application source
COPY . .

# Build the application (if applicable)
# RUN npm run build

# =============================================================================
# Stage 2: Production
# Minimal runtime image with non-root user.
# =============================================================================
FROM node:20-alpine AS production

# Security: run as non-root user
RUN addgroup -g 1000 appgroup && \
    adduser -u 1000 -G appgroup -s /bin/sh -D appuser

WORKDIR /app

# Copy only production artifacts from build stage
COPY --from=build --chown=appuser:appgroup /app/node_modules ./node_modules
COPY --from=build --chown=appuser:appgroup /app .

# Switch to non-root user (UID 1000)
USER 1000

# Expose the application port (must match container_port in terraform.tfvars)
EXPOSE 8080

# Health check for ECS/ALB integration
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

# Start the application
CMD ["node", "server.js"]
