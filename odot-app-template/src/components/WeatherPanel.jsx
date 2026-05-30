import { useOhgoData } from '../hooks/useOhgoData';
import PanelCard from './PanelCard';

function getConditionStyle(condition) {
  if (!condition) return { class: 'bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-300', icon: '❓' };
  const c = condition.toLowerCase();
  if (c.includes('dry') || c.includes('clear')) return { class: 'bg-green-100 text-green-700 dark:bg-green-900/40 dark:text-green-300', icon: '☀️' };
  if (c.includes('wet') || c.includes('rain') || c.includes('moist')) return { class: 'bg-yellow-100 text-yellow-700 dark:bg-yellow-900/40 dark:text-yellow-300', icon: '🌧️' };
  if (c.includes('snow') || c.includes('ice') || c.includes('frost')) return { class: 'bg-red-100 text-red-700 dark:bg-red-900/40 dark:text-red-300', icon: '❄️' };
  return { class: 'bg-blue-100 text-blue-700 dark:bg-blue-900/40 dark:text-blue-300', icon: '🌥️' };
}

function formatTemp(temp) {
  if (temp === null || temp === undefined) return '—';
  return `${Math.round(temp)}°`;
}

export default function WeatherPanel() {
  const { data, loading, error } = useOhgoData('weather');

  const sites = data?.results || data || [];
  const visibleSites = Array.isArray(sites) ? sites.slice(0, 8) : [];

  return (
    <PanelCard title="Road Weather" icon="🌤️" count={visibleSites.length} loading={loading} error={error}>
      {visibleSites.length === 0 ? (
        <div className="text-center py-12">
          <div className="w-16 h-16 mx-auto rounded-full bg-blue-50 dark:bg-blue-900/20 flex items-center justify-center mb-4">
            <span className="text-2xl">🌤️</span>
          </div>
          <p className="font-medium text-gray-600 dark:text-gray-300">No weather data</p>
          <p className="text-sm text-gray-400 mt-1">Sensor data is temporarily unavailable</p>
        </div>
      ) : (
        <div className="space-y-2.5">
          {visibleSites.map((site, i) => {
            const condition = getConditionStyle(site.surfaceCondition || site.roadCondition);
            return (
              <div key={site.id || i} className="p-3.5 rounded-xl bg-gray-50/80 dark:bg-gray-700/30 border border-gray-100 dark:border-gray-600/50 hover:border-emerald-300/50 transition-colors">
                <div className="flex items-center justify-between gap-2">
                  <span className="text-sm font-semibold text-gray-800 dark:text-gray-200 truncate">
                    {site.description || site.location || `Sensor ${i + 1}`}
                  </span>
                  <span className={`stat-badge ${condition.class}`}>
                    {condition.icon} {site.surfaceCondition || site.roadCondition || 'Unknown'}
                  </span>
                </div>
                <div className="mt-3 grid grid-cols-3 gap-3">
                  <div className="text-center p-2 rounded-lg bg-white dark:bg-gray-800/50">
                    <p className="text-[10px] uppercase tracking-wider text-gray-400 font-medium">Surface</p>
                    <p className="text-lg font-bold text-gray-700 dark:text-gray-200 mt-0.5">
                      {formatTemp(site.surfaceTemperature || site.surfaceTemp)}
                    </p>
                  </div>
                  <div className="text-center p-2 rounded-lg bg-white dark:bg-gray-800/50">
                    <p className="text-[10px] uppercase tracking-wider text-gray-400 font-medium">Air</p>
                    <p className="text-lg font-bold text-gray-700 dark:text-gray-200 mt-0.5">
                      {formatTemp(site.airTemperature || site.airTemp)}
                    </p>
                  </div>
                  <div className="text-center p-2 rounded-lg bg-white dark:bg-gray-800/50">
                    <p className="text-[10px] uppercase tracking-wider text-gray-400 font-medium">Visibility</p>
                    <p className="text-lg font-bold text-gray-700 dark:text-gray-200 mt-0.5">
                      {site.visibility ? `${site.visibility}mi` : '—'}
                    </p>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </PanelCard>
  );
}
