import { useState } from 'react';
import { useOhgoData } from '../hooks/useOhgoData';
import PanelCard from './PanelCard';

export default function CamerasPanel() {
  const { data, loading, error } = useOhgoData('cameras');
  const [selectedCamera, setSelectedCamera] = useState(null);

  const cameras = data?.results || data || [];
  const visibleCameras = Array.isArray(cameras)
    ? cameras.filter(c => c.smallImageUrl || c.largeImageUrl).slice(0, 12)
    : [];

  return (
    <PanelCard title="Traffic Cameras" icon="📷" count={visibleCameras.length} loading={loading} error={error}>
      {visibleCameras.length === 0 ? (
        <div className="text-center py-12">
          <div className="w-16 h-16 mx-auto rounded-full bg-gray-100 dark:bg-gray-700 flex items-center justify-center mb-4">
            <span className="text-2xl">📷</span>
          </div>
          <p className="font-medium text-gray-600 dark:text-gray-300">No feeds available</p>
          <p className="text-sm text-gray-400 mt-1">Camera feeds are temporarily unavailable</p>
        </div>
      ) : (
        <>
          <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
            {visibleCameras.map((camera, i) => (
              <button
                key={camera.id || i}
                onClick={() => setSelectedCamera(camera)}
                className="group relative rounded-xl overflow-hidden border-2 border-gray-200 dark:border-gray-600 hover:border-odot-blue dark:hover:border-odot-blue transition-all duration-200 hover:scale-[1.02] hover:shadow-lg"
              >
                <div className="relative">
                  <img
                    src={camera.smallImageUrl || camera.largeImageUrl}
                    alt={camera.description || camera.location || 'Traffic camera'}
                    className="w-full h-24 object-cover bg-gray-200 dark:bg-gray-700"
                    loading="lazy"
                  />
                  {/* Hover overlay */}
                  <div className="absolute inset-0 bg-odot-navy/0 group-hover:bg-odot-navy/40 transition-colors flex items-center justify-center">
                    <svg className="w-6 h-6 text-white opacity-0 group-hover:opacity-100 transition-opacity" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0zM10 7v3m0 0v3m0-3h3m-3 0H7" />
                    </svg>
                  </div>
                  {/* Live indicator */}
                  <div className="absolute top-1.5 right-1.5 flex items-center gap-1 bg-black/60 rounded-full px-1.5 py-0.5">
                    <div className="w-1.5 h-1.5 rounded-full bg-red-500 animate-pulse" />
                    <span className="text-[9px] text-white font-medium">LIVE</span>
                  </div>
                </div>
                <p className="text-[11px] text-gray-600 dark:text-gray-300 p-2 truncate font-medium">
                  {camera.description || camera.location || `Camera ${i + 1}`}
                </p>
              </button>
            ))}
          </div>

          {/* Lightbox modal */}
          {selectedCamera && (
            <div
              className="fixed inset-0 z-50 bg-black/90 backdrop-blur-sm flex items-center justify-center p-4 animate-fade-in"
              onClick={() => setSelectedCamera(null)}
            >
              <div className="max-w-4xl w-full animate-slide-up" onClick={e => e.stopPropagation()}>
                <div className="relative rounded-2xl overflow-hidden shadow-2xl">
                  <img
                    src={selectedCamera.largeImageUrl || selectedCamera.smallImageUrl}
                    alt={selectedCamera.description || 'Traffic camera'}
                    className="w-full"
                  />
                  <div className="absolute top-4 right-4">
                    <button
                      onClick={() => setSelectedCamera(null)}
                      className="w-10 h-10 rounded-full bg-black/50 hover:bg-black/70 flex items-center justify-center transition-colors"
                    >
                      <svg className="w-5 h-5 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                      </svg>
                    </button>
                  </div>
                  <div className="absolute bottom-0 inset-x-0 bg-gradient-to-t from-black/80 to-transparent p-6">
                    <p className="text-white font-semibold text-lg">
                      {selectedCamera.description || selectedCamera.location}
                    </p>
                    <div className="flex items-center gap-2 mt-1">
                      <div className="w-2 h-2 rounded-full bg-red-500 animate-pulse" />
                      <span className="text-white/70 text-sm">Live Feed</span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          )}
        </>
      )}
    </PanelCard>
  );
}
