export type CacheWindow = {
  // Start of the request that last read or wrote the cache; the TTL counts from here.
  startedAt: number
  // Coarse clock used to redraw the band; refreshed by the tick timer, not every ms.
  now: number
  // Model and effort that request ran under; a switch leaves the cached prefix behind.
  model?: string
  effort?: string | number
  // Set when compaction rewrote the conversation under the cache; cleared by the next request.
  rewritten?: boolean
}

export type CacheLastStep = {
  at: number
  isMiss: boolean
  // A full write the window predicted (first request, TTL lapsed, compaction, model or effort switch); never a miss.
  isColdWrite: boolean
  coldReason?: string
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
