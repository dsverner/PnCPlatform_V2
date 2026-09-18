import { BrowserRouter, Routes, Route, Navigate, useLocation } from 'react-router'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import AppLayout from '@/layouts/AppLayout'
import HomePage from '@/pages/Home'
import ScreenPage from '@/pages/Screen'

/** #189: one mounted screen per history entry. A push to the same route (the book at another location) would keep the
 * mounted screen and its state; keying the page by the entry's key mounts each entry fresh, so its own remembered state
 * (useEntryState) is what it shows — on the way forward and on Back alike. */
function EntryScreen() { return <ScreenPage key={useLocation().key} /> }

const queryClient = new QueryClient({ defaultOptions: { queries: { retry: 1, staleTime: 30_000, refetchOnWindowFocus: false } } })

export default function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <BrowserRouter basename="/app">
        <Routes>
          <Route element={<AppLayout />}>
            <Route path="/" element={<HomePage />} />
            <Route path="/s/:key" element={<EntryScreen />} />
            <Route path="/s/:key/:id" element={<EntryScreen />} />
            <Route path="/settings" element={<Navigate to="/s/SETTINGS_BOOK" replace />} />
            <Route path="/requests" element={<Navigate to="/s/REQUEST_QUEUE" replace />} />
            <Route path="*" element={<Navigate to="/" replace />} />
          </Route>
        </Routes>
      </BrowserRouter>
    </QueryClientProvider>
  )
}
