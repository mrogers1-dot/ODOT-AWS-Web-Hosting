export default function PanelCard({ title, icon, count, children, loading, error }) {
  return (
    <div className="glass-card rounded-2xl shadow-lg hover:shadow-xl transition-all duration-300 overflow-hidden flex flex-col animate-slide-up">
      {/* Panel header */}
      <div className="px-6 py-4 border-b border-gray-100 dark:border-gray-700/50 flex items-center justify-between bg-gradient-to-r from-transparent to-gray-50/50 dark:to-gray-700/20">
        <div className="flex items-center gap-3">
          <div className="w-9 h-9 rounded-lg bg-odot-lightBlue dark:bg-odot-blue/20 flex items-center justify-center">
            <span className="text-xl">{icon}</span>
          </div>
          <h2 className="text-lg font-bold text-gray-800 dark:text-gray-100">{title}</h2>
        </div>
        {count !== undefined && (
          <span className="stat-badge bg-odot-navy/10 text-odot-navy dark:bg-odot-blue/20 dark:text-odot-blue">
            {count} active
          </span>
        )}
      </div>

      {/* Panel content */}
      <div className="p-5 flex-1 overflow-y-auto max-h-[420px]">
        {loading && <LoadingState />}
        {error && <ErrorState message={error} />}
        {!loading && !error && children}
      </div>
    </div>
  );
}

function LoadingState() {
  return (
    <div className="flex flex-col items-center justify-center py-16 gap-3">
      <div className="relative">
        <div className="w-10 h-10 rounded-full border-3 border-gray-200 dark:border-gray-700" />
        <div className="absolute inset-0 w-10 h-10 rounded-full border-3 border-t-odot-blue animate-spin" />
      </div>
      <p className="text-sm text-gray-400">Loading data...</p>
    </div>
  );
}

function ErrorState({ message }) {
  return (
    <div className="text-center py-12">
      <div className="w-16 h-16 mx-auto rounded-full bg-red-50 dark:bg-red-900/20 flex items-center justify-center mb-4">
        <svg className="w-8 h-8 text-red-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.34 16.5c-.77.833.192 2.5 1.732 2.5z" />
        </svg>
      </div>
      <p className="text-sm font-medium text-gray-600 dark:text-gray-300">Unable to load data</p>
      <p className="text-xs text-gray-400 mt-1">{message}</p>
    </div>
  );
}
