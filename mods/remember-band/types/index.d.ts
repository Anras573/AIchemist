export type Handoff = {
  // Items under the note's `## Next` heading, in the note's order.
  next: string[]
  // When /remember last wrote the note, ms since the epoch.
  writtenMs: number
  // Set when the same note has already been loaded by an earlier session:
  // how many sessions have loaded it, and since when (Remember's own record).
  redelivered: { count: number; since: string } | null
}

declare module 'claude-code' {
  interface PluginState {
    'aichemist-remember-band': {
      handoff: Handoff | null
      isHidden: boolean
    }
  }
}
