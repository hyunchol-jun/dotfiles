export type CacheWindow = {
  // Start of the request that last read or wrote the cache; the TTL counts from here.
  startedAt: number
  // Coarse clock used to redraw the band; refreshed by the tick timer, not every ms.
  now: number
}

export type CacheLastStep = {
  at: number
  isMiss: boolean
  read: number
  written: number
  uncached: number
  model: string
}

declare module 'claude-code' {
  interface PluginState {
    'cache-clock': { window: CacheWindow | null; last: CacheLastStep | null }
  }
}
