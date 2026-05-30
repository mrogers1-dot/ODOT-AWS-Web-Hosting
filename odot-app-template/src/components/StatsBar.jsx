import { useOhgoData } from '../hooks/useOhgoData';

export default function StatsBar() {
  const { data: incidents } = useOhgoData('incidents');
  const { data: construction } = useOhgoData('construction');
  const { data: cameras } = useOhgoData('cameras');
  const { data: weather } = useOhgoData('weather');

  const incidentCount = (incidents?.results || incidents || []).length;
  const constructionCount = (construction?.results || construction || []).length;
  const cameraCount = (cameras?.results || cameras || []).filter(c => c.smallImageUrl || c.largeImageUrl).length;
  const weatherCount = (weather?.results || weather || []).length;

  const stats = [
    { label: 'Active Incidents', value: incidentCount, icon: '🚨', color: 'from-red-500 to-red-600' },
    { label: 'Work Zones', value: constructionCount, icon: '🚧', color: 'from-orange-500 to-orange-600' },
    { label: 'Live Cameras', value: cameraCount, icon: '📷', color: 'from-blue-500 to-blue-600' },
    { label: 'Weather Sensors', value: weatherCount, icon: '🌤️', color: 'from-emerald-500 to-emerald-600' }
  ];

  return (
    <div className="bg-white dark:bg-gray-800/50 border-b border-gray-200 dark:border-gray-700/50 shadow-sm">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          {stats.map((stat) => (
            <div key={stat.label} className="flex items-center gap-3 group">
              <div className={`w-10 h-10 rounded-lg bg-gradient-to-br ${stat.color} flex items-center justify-center shadow-md group-hover:scale-110 transition-transform duration-200`}>
                <span className="text-lg">{stat.icon}</span>
              </div>
              <div>
                <p className="text-2xl font-bold text-gray-800 dark:text-white tabular-nums">
                  {stat.value || '—'}
                </p>
                <p className="text-xs text-gray-500 dark:text-gray-400">{stat.label}</p>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
