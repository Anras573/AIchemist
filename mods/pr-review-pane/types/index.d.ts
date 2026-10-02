export type LoopState = 'WAITING' | 'REVIEWING' | 'DONE'

export type CheckSummary = {
  passed: number
  failed: number
  pending: number
  failedNames: string[]
}

export type Thread = {
  author: string
  isCopilot: boolean
  location: string
  summary: string
  url: string
}

export type PrSnapshot = {
  number: number
  title: string
  url: string
  branch: string
  isDraft: boolean
  state: LoopState
  lastReviewMs?: number
  reviewedOid?: string
  headOid: string
  checks: CheckSummary
  threads: Thread[]
  fetchedAtMs: number
}

declare module 'claude-code' {
  interface PluginState {
    'aichemist-pr-review-pane': {
      snapshot: PrSnapshot | null
      error: string | null
      isLoading: boolean
      prNumber: number | null
    }
  }
}
