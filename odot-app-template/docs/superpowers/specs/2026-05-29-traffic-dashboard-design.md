# ODOT Traffic Dashboard — Design Spec

**Date:** 2026-05-29
**Status:** Approved
**Purpose:** Build a modern React dashboard that displays real-time Ohio traffic data from the OHGO public API, containerized and deployed to the ODOT AWS Web Hosting platform.

---

## Overview

A single-container web application that serves as the first real app deployed to the platform. It pulls live traffic data from ODOT's public OHGO API and displays it in a modern, responsive dashboard.

This proves the full platform pipeline works: Docker build → ECR push → ECS deploy → ALB serving → healthy app.

---

## Architecture

### Single Container (Express + React)

- **Backend:** Express.js on port 8080
  - Proxies OHGO API calls (keeps API key server-side)
  - Serves built React static files from `/dist`
  - `/health` endpoint for ECS/ALB health checks
  - In-memory cache (60-second TTL) for OHGO responses
- **Frontend:** React 18 + Vite + Tailwind CSS
  - Four data panels in a responsive grid
  - Auto-refreshes every 2 minutes
  - Dark/light mode toggle

### Data Flow

```
Browser → Express (/api/incidents)    → OHGO API (cached 60s) → JSON response
Browser → Express (/api/construction) → OHGO API (cached 60s) → JSON response
Browser → Express (/api/cameras)      → OHGO API (cached 60s) → JSON response
Browser → Express (/api/weather)      → OHGO API (cached 60s) → JSON response
```

### API Key Handling

- Passed as environment variable `OHGO_API_KEY`
- Set in Dockerfile as a build-time default for the demo
- Not treated as sensitive (OHGO API is free, public-domain data)

---

## UI Design

### Layout

- **Header:** ODOT branding, title "Ohio Traffic Dashboard", last-updated timestamp, dark/light toggle
- **Grid:** 2×2 on desktop (lg+), single column on mobile
- **Color scheme:** Ohio state colors — deep red (#CE1126), white, navy (#002D72), with gray accents
- **Typography:** Inter or system font stack
- **Style:** Tailwind utility classes, rounded cards with subtle shadows

### Panel 1: Active Incidents (top-left)

- Scrollable list of current incidents
- Each item shows: severity badge, type icon, location, description, time since start
- Severity colors: red (closure), orange (crash), yellow (hazard), blue (info)
- Empty state: "No active incidents" with a green checkmark

### Panel 2: Construction/Work Zones (top-right)

- List of active work zones
- Each item shows: route name, description, date range, lane impact
- Status pill: "Active Now" (green) or "Scheduled" (gray)
- Sorted by proximity to SW Ohio (default region)

### Panel 3: Traffic Cameras (bottom-left)

- Grid of camera thumbnail images (2×3 grid, scrollable)
- Camera location name below each thumbnail
- Click to expand full-size in a modal/lightbox
- Thumbnails refresh with data (every 2 min)

### Panel 4: Weather Conditions (bottom-right)

- Card-based display of weather sensor readings
- Shows: location, surface temp, air temp, visibility, precipitation
- Color-coded status: green (clear), yellow (caution), red (hazardous)
- Shows 4-6 sensor sites from SW Ohio region

---

## File Structure

```
odot-app-template/
├── server.js                 # Express: API proxy + static file serving + health check
├── package.json              # Dependencies for both server and build
├── Dockerfile                # Multi-stage: build React, serve with Express
├── .env.example              # Documents OHGO_API_KEY variable
├── vite.config.js            # Vite config with proxy for dev mode
├── tailwind.config.js        # Tailwind theme (ODOT colors)
├── postcss.config.js         # PostCSS for Tailwind
├── index.html                # Vite entry point
├── src/
│   ├── main.jsx              # React entry
│   ├── App.jsx               # Layout + panel grid
│   ├── components/
│   │   ├── Header.jsx        # Branding, title, refresh indicator, theme toggle
│   │   ├── IncidentsPanel.jsx
│   │   ├── ConstructionPanel.jsx
│   │   ├── CamerasPanel.jsx
│   │   ├── WeatherPanel.jsx
│   │   ├── PanelCard.jsx     # Reusable card wrapper
│   │   └── LoadingSpinner.jsx
│   ├── hooks/
│   │   └── useOhgoData.js    # Generic fetch hook with auto-refresh
│   └── index.css             # Tailwind base/components/utilities imports
└── terraform/                # Already exists — app infrastructure
```

---

## API Endpoints (Express Backend)

| Route | OHGO Endpoint | Notes |
|-------|---------------|-------|
| `GET /api/incidents` | `api/v1/incidents` | Filters to active only |
| `GET /api/construction` | `api/v1/construction` | Filters to active only |
| `GET /api/cameras` | `api/v1/cameras` | Returns thumbnail URLs |
| `GET /api/weather` | `api/v1/weather-sensor-sites` | Returns sensor readings |
| `GET /health` | — | Returns `{ status: "ok", uptime: ... }` |

All `/api/*` routes add the `Authorization` header with the OHGO API key before proxying.

---

## Constraints

- Must run on port 8080 (matches ECS task definition and ALB health check)
- Must respond to `/health` with 200 (ECS health check)
- Must run as non-root user (UID 1000) in container
- Read-only root filesystem compatible
- Container size target: < 200MB
- No external state (stateless — all data from OHGO API)

---

## Tech Stack

- **Runtime:** Node.js 20 (Alpine)
- **Backend:** Express 4
- **Frontend:** React 18, Vite 5, Tailwind CSS 3
- **HTTP client:** node-fetch or built-in fetch (Node 20+)
- **No database** — purely API-driven

---

## Out of Scope (for initial build)

- User authentication
- Persistent data storage
- Map visualization
- Push notifications
- Historical data / trends
- Region selector (hardcoded to SW Ohio for demo)
