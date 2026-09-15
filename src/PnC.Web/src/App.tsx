import { BrowserRouter, Routes, Route, Navigate } from 'react-router'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import AppLayout from '@/layouts/AppLayout'
import HomePage from '@/pages/Home'
import ScreenPage from '@/pages/Screen'

const queryClient = new QueryClient({ defaultOptions: { queries: { retry: 1, staleTime: 30_000, refetchOnWindowFocus: false } } })

export default function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <BrowserRouter basename="/app">
        <Routes>
          <Route element={<AppLayout />}>
            <Route path="/" element={<HomePage />} />
            <Route path="/s/:key" element={<ScreenPage />} />
            <Route path="/s/:key/:id" element={<ScreenPage />} />
            <Route path="/settings" element={<Navigate to="/s/SETTINGS_BOOK" replace />} />
            <Route path="/requests" element={<Navigate to="/s/REQUEST_QUEUE" replace />} />
            <Route path="*" element={<Navigate to="/" replace />} />
          </Route>
        </Routes>
      </BrowserRouter>
    </QueryClientProvider>
  )
}
