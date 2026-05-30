import { useOhgoData } from '../hooks/useOhgoData';
import PanelCard from './PanelCard';

export default function ConstructionPanel() {
  const { data, loading, error } = useOhgoData('construction');

  const zones = data?.results || data || [];
  const activeZones = Array.isArray(zones) ? zones.slice(0, 15) : [];

  return (
    <PanelCard title="Construction Zones" icon="🚧" count={activeZones.length} loading={loading} error={error}>
      {activeZones.length === 0 ? (
        <div className="text-center py-12">
          <div className="w-16 h-16 mx-auto rounded-full bg-green-50 dark:bg-green-900/20 flex items-center justify-center mb-4">
            <span className="text-2xl">🛣️</span>
          </div>
          <p className="font-medium text-gray-600 dark:text-gray-300">Roads are clear</p>
          <p className="text-sm text-gray-400 mt-1">No active construction zones</p>
        </div>
      ) : (
        <div className="space-y-2.5">
          {activeZones.map((zone, i) => (
            <div key={zone.id || i} className="p-3.5 rounded-xl bg-gray-50/80 dark:bg-gray-700/30 border border-gray-100 dark:border-gray-600/50 hover:border-odot-gold/40 transition-colors group">
              <div className="flex items-center justify-between gap-2">
                <h3 className="text-sm font-bold text-gray-800 dark:text-gray-200 group-hover:text-odot-navy dark:group-hover:text-odot-gold transition-colors truncate">
                  {zone.routeName || zone.roadName || `Route ${zone.routeNumber || ''}`}
                </h3>
                <span className={`stat-badge shrink-0 ${
                  zone.isActive !== false
                    ? 'bg-green-100 text-green-700 dark:bg-green-900/40 dark:text-green-300'
                    : 'bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-400'
                }`}>
                  {zone.isActive !== false ? '● Active' : '○ Scheduled'}
                </span>
              </div>
              <p className="text-xs text-gray-600 dark:text-gray-300 mt-2 line-clamp-2 leading-relaxed">
                {zone.description || zone.workType || 'Road work in progress'}
              </p>
              <div className="flex items-center gap-3 mt-2.5">
                {(zone.startDate || zone.endDate) && (
                  <span className="text-xs text-gray-400 flex items-center gap-1">
                    <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
                    </svg>
                    {zone.startDate && new Date(zone.startDate).toLocaleDateString()}
                    {zone.endDate && ` — ${new Date(zone.endDate).toLocaleDateString()}`}
                  </span>
                )}
                {zone.laneImpact && (
                  <span className="text-xs text-orange-600 dark:text-orange-400 font-medium">
                    ⚠️ {zone.laneImpact}
                  </span>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </PanelCard>
  );
}
