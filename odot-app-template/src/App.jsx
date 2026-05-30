import { useState } from 'react';
import Header from './components/Header';
import StatsBar from './components/StatsBar';
import IncidentsPanel from './components/IncidentsPanel';
import ConstructionPanel from './components/ConstructionPanel';
import CamerasPanel from './components/CamerasPanel';
import WeatherPanel from './components/WeatherPanel';

export default function App() {
  const [darkMode, setDarkMode] = useState(false);

  return (
    <div className={darkMode ? 'dark' : ''}>
      <div className="min-h-screen bg-gradient-to-br from-gray-50 to-gray-100 dark:from-gray-900 dark:to-gray-950 transition-colors duration-300">
        <Header darkMode={darkMode} setDarkMode={setDarkMode} />
        <StatsBar />
        <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 animate-fade-in">
            <IncidentsPanel />
            <ConstructionPanel />
            <CamerasPanel />
            <WeatherPanel />
          </div>
          <footer className="mt-12 text-center text-xs text-gray-400 dark:text-gray-500 pb-8">
            <p>Data provided by OHGO Public API • Ohio Department of Transportation</p>
            <p className="mt-1">This is a demonstration application deployed on the ODOT AWS Web Hosting Platform</p>
          </footer>
        </main>
      </div>
    </div>
  );
}
