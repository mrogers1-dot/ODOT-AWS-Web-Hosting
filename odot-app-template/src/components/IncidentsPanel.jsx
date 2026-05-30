import { useOhgoData } from '../hooks/useOhgoData';
import PanelCard from './PanelCard';

const severityConfig = {
  closure: { class: 'bg-red-100 text-red-700 dark:bg-red-900/40 dark:text-red-300', dot: 'bg-red-500' },
  crash: { class: 'bg-orange-100 text-orange-700 dark:bg-orange-900/40 dark:text-orange-300', dot: 'bg-orange-500' },
  hazard: { class: 'bg-yellow-100 text-yellow-700 dark:bg-yellow-900/40 dark:text-yellow-300', dot: 'bg-yellow-500' },
  default: { class: 'bg-blue-100 text-blue-700 dark:bg-blue-900/40 dark:text-blue-300', dot: 'bg-blue-500' }
};

function getSeverity(incident) {
  const type = (incident.category || incident.type || '').toLowerCase();
  if (type.includes('closure') || type.includes('closed')) return severityConfig.closure;
  if (type.includes('crash') || type.includes('accident')) return severityConfig.crash;
  if (type.includes('hazard') || type.includes('debris')) return severityConfig.hazard;
  return severityConfig.default;
}

function timeAgo(dateStr) {
  if (!dateStr) return '';
  const diff = Date.now() - new Date(dateStr).getTime();
  const mins = Math.floor(diff / 60000);
  if (mins < 1) return 'Just now';
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  return `${Math.floor(hrs / 24)}d ago`;
}

export default function IncidentsPanel() {
  const { data, loading, error } = useOhgoData('incidents');

  const incidents = data?.results || data || [];
  const activeIncidents = Array.isArray(incidents) ? incidents.slice(0, 20) : [];

  return (
    <PanelCard title="Active Incidents" icon="🚨" count={activeIncidents.length} loading={loading} error={error}>
      {activeIncidents.length === 0 ? (
        <div className="text-center py-12">
          <div className="w-16 h-16 mx-auto rounded-full bg-green-50 dark:bg-green-900/20 flex items-center justify-center mb-4">
            <svg className="w-8 h-8 text-green-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
            </svg>
          </div>
          <p className="font-medium text-gray-600 dark:text-gray-300">All clear</p>
          <p className="text-sm text-gray-400 mt-1">No active incidents reported</p>
        </div>
      ) : (
        <div className="space-y-2.5">
          {activeIncidents.map((incident, i) => {
            const severity = getSeverity(incident);
            return (
              <div key={incident.id || i} className="p-3.5 rounded-xl bg-gray-50/80 dark:bg-gray-700/30 border border-gray-100 dark:border-gray-600/50 hover:border-odot-blue/30 transition-colors group">
                <div className="flex items-start justify-between gap-2">
                  <div className="flex items-center gap-2">
                    <div className={`w-2 h-2 rounded-full ${severity.dot} animate-pulse-slow`} />
                    <span className={`stat-badge ${severity.class}`}>
                      {incident.category || incident.type || 'Incident'}
                    </span>
                  </div>
                  <span className="text-xs text-gray-400 whitespace-nowrap font-medium">
                    {timeAgo(incident.startDate || incident.lastUpdated)}
                  </span>
                </div>
                <p className="text-sm font-semibold mt-2.5 text-gray-800 dark:text-gray-200 group-hover:text-odot-blue dark:group-hover:text-odot-blue transition-colors">
                  {incident.roadName || incident.location || 'Unknown location'}
                </p>
                <p className="text-xs text-gray-500 dark:text-gray-400 mt-1 line-clamp-2 leading-relaxed">
                  {incident.description || incident.direction || ''}
                </p>
              </div>
            );
          })}
        </div>
      )}
    </PanelCard>
  );
}
