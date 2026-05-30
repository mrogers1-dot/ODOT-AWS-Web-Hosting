const express = require('express');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 8080;
const OHGO_API_KEY = process.env.OHGO_API_KEY || 'd0215db2-60e6-4e54-b0cd-04ecda3a5346';
const OHGO_BASE_URL = 'https://publicapi.ohgo.com/api/v1';

// Simple in-memory cache (60-second TTL)
const cache = new Map();
const CACHE_TTL = 60 * 1000;

function getCached(key) {
  const entry = cache.get(key);
  if (entry && Date.now() - entry.timestamp < CACHE_TTL) {
    return entry.data;
  }
  cache.delete(key);
  return null;
}

function setCache(key, data) {
  cache.set(key, { data, timestamp: Date.now() });
}

// OHGO API proxy helper
async function fetchOhgo(endpoint, query = '') {
  const cacheKey = `${endpoint}?${query}`;
  const cached = getCached(cacheKey);
  if (cached) return cached;

  const url = `${OHGO_BASE_URL}/${endpoint}${query ? '?' + query : ''}`;
  const response = await fetch(url, {
    headers: {
      'Authorization': `APIKEY ${OHGO_API_KEY}`,
      'Accept': 'application/json'
    }
  });

  if (!response.ok) {
    throw new Error(`OHGO API error: ${response.status} ${response.statusText}`);
  }

  const data = await response.json();
  setCache(cacheKey, data);
  return data;
}

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    uptime: process.uptime(),
    timestamp: new Date().toISOString()
  });
});

// API proxy routes
app.get('/api/incidents', async (req, res) => {
  try {
    const data = await fetchOhgo('incidents');
    res.json(data);
  } catch (err) {
    console.error('Error fetching incidents:', err.message);
    res.status(502).json({ error: 'Failed to fetch incidents' });
  }
});

app.get('/api/construction', async (req, res) => {
  try {
    const data = await fetchOhgo('construction');
    res.json(data);
  } catch (err) {
    console.error('Error fetching construction:', err.message);
    res.status(502).json({ error: 'Failed to fetch construction data' });
  }
});

app.get('/api/cameras', async (req, res) => {
  try {
    const data = await fetchOhgo('cameras');
    res.json(data);
  } catch (err) {
    console.error('Error fetching cameras:', err.message);
    res.status(502).json({ error: 'Failed to fetch camera data' });
  }
});

app.get('/api/weather', async (req, res) => {
  try {
    const data = await fetchOhgo('weather-sensor-sites');
    res.json(data);
  } catch (err) {
    console.error('Error fetching weather:', err.message);
    res.status(502).json({ error: 'Failed to fetch weather data' });
  }
});

// Serve static files from Vite build output
app.use(express.static(path.join(__dirname, 'dist')));

// SPA fallback — serve index.html for all non-API routes
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'dist', 'index.html'));
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`ODOT Traffic Dashboard running on port ${PORT}`);
  console.log(`Health check: http://localhost:${PORT}/health`);
});
