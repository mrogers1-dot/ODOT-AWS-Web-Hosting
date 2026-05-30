export default function Header({ darkMode, setDarkMode }) {
  return (
    <header className="relative overflow-hidden">
      {/* Top bar — Ohio state government banner */}
      <div className="bg-odot-darkNavy text-gray-400 text-xs py-1.5 px-4">
        <div className="max-w-7xl mx-auto flex items-center justify-between">
          <span>An official State of Ohio application</span>
          <span className="hidden sm:inline">Ohio Department of Transportation</span>
        </div>
      </div>

      {/* Main header */}
      <div className="bg-ohio-gradient relative">
        {/* Subtle geometric pattern overlay */}
        <div className="absolute inset-0 opacity-5">
          <div className="absolute top-0 right-0 w-96 h-96 bg-gradient-radial from-white/20 to-transparent rounded-full -translate-y-1/2 translate-x-1/3" />
          <div className="absolute bottom-0 left-0 w-64 h-64 bg-gradient-radial from-odot-blue/30 to-transparent rounded-full translate-y-1/2 -translate-x-1/3" />
        </div>

        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6 relative z-10">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-5">
              {/* ODOT Logo mark */}
              <div className="relative">
                <div className="w-14 h-14 bg-odot-red rounded-xl flex items-center justify-center shadow-lg shadow-odot-red/30 rotate-3 hover:rotate-0 transition-transform duration-300">
                  <span className="font-extrabold text-white text-lg -rotate-3 hover:rotate-0 transition-transform">ODOT</span>
                </div>
              </div>
              <div>
                <h1 className="text-2xl sm:text-3xl font-bold text-white tracking-tight">
                  Ohio Traffic Dashboard
                </h1>
                <p className="text-sm text-gray-300 mt-0.5 flex items-center gap-2">
                  <span className="live-dot" />
                  Real-time data powered by OHGO
                </p>
              </div>
            </div>

            <div className="flex items-center gap-3">
              {/* Refresh indicator */}
              <div className="hidden md:flex items-center gap-2 text-xs text-gray-400 bg-white/5 rounded-lg px-3 py-2 border border-white/10">
                <svg className="w-3.5 h-3.5 animate-spin-slow" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
                </svg>
                <span>Auto-refresh 2m</span>
              </div>

              {/* Dark mode toggle */}
              <button
                onClick={() => setDarkMode(!darkMode)}
                className="p-2.5 rounded-xl bg-white/10 hover:bg-white/20 border border-white/10 transition-all duration-200 hover:scale-105 active:scale-95"
                aria-label="Toggle dark mode"
              >
                {darkMode ? (
                  <svg className="w-5 h-5 text-odot-gold" fill="currentColor" viewBox="0 0 20 20">
                    <path fillRule="evenodd" d="M10 2a1 1 0 011 1v1a1 1 0 11-2 0V3a1 1 0 011-1zm4 8a4 4 0 11-8 0 4 4 0 018 0zm-.464 4.95l.707.707a1 1 0 001.414-1.414l-.707-.707a1 1 0 00-1.414 1.414zm2.12-10.607a1 1 0 010 1.414l-.706.707a1 1 0 11-1.414-1.414l.707-.707a1 1 0 011.414 0zM17 11a1 1 0 100-2h-1a1 1 0 100 2h1zm-7 4a1 1 0 011 1v1a1 1 0 11-2 0v-1a1 1 0 011-1zM5.05 6.464A1 1 0 106.465 5.05l-.708-.707a1 1 0 00-1.414 1.414l.707.707zm1.414 8.486l-.707.707a1 1 0 01-1.414-1.414l.707-.707a1 1 0 011.414 1.414zM4 11a1 1 0 100-2H3a1 1 0 000 2h1z" clipRule="evenodd" />
                  </svg>
                ) : (
                  <svg className="w-5 h-5 text-gray-300" fill="currentColor" viewBox="0 0 20 20">
                    <path d="M17.293 13.293A8 8 0 016.707 2.707a8.001 8.001 0 1010.586 10.586z" />
                  </svg>
                )}
              </button>
            </div>
          </div>
        </div>

        {/* Bottom accent line */}
        <div className="h-1 bg-gradient-to-r from-odot-red via-odot-gold to-odot-blue" />
      </div>
    </header>
  );
}
