// Pure helpers for the PR review pane: no `$`, so tests call them directly.
// Inputs are what `gh pr view --json ...` and `gh api graphql` print, using
// the same fields and the same Copilot login as skills/pr-review-loop.

import type { CheckSummary, LoopState, PrSnapshot, Thread } from '../types'

export const COPILOT_LOGIN = 'copilot-pull-request-reviewer'

export const PR_VIEW_FIELDS = [
  'number',
  'title',
  'url',
  'headRefName',
  'headRefOid',
  'isDraft',
  'reviews',
  'statusCheckRollup',
].join(',')

// One request for what pr-review-loop reads in Steps 1 and 2: the head
// commit's time and the review threads (first comment only). The skill reads
// Commit.pushedDate, which GitHub deprecated and now answers null for, so the
// pane uses committedDate instead (earlier than the push for an amended or
// rebased commit, so a review of an older push can read as current).
export const THREADS_QUERY = `
query($owner: String!, $repo: String!, $pr: Int!, $oid: GitObjectID!) {
  repository(owner: $owner, name: $repo) {
    object(oid: $oid) {
      ... on Commit { committedDate }
    }
    pullRequest(number: $pr) {
      reviewThreads(first: 100) {
        nodes {
          isResolved
          comments(first: 1) {
            nodes { author { login } body path line url }
          }
        }
      }
    }
  }
}`

type PrView = {
  number: number
  title: string
  url: string
  headRefName: string
  headRefOid: string
  isDraft?: boolean
  reviews?: { author?: { login?: string } | null; submittedAt?: string | null }[]
  statusCheckRollup?: RollupItem[] | null
}

type RollupItem = {
  __typename?: string
  name?: string
  context?: string
  status?: string
  conclusion?: string | null
  state?: string
}

type ThreadsResponse = {
  data?: {
    repository?: {
      object?: { committedDate?: string | null } | null
      pullRequest?: {
        reviewThreads?: {
          nodes?: {
            isResolved: boolean
            comments?: {
              nodes?: {
                author?: { login?: string } | null
                body?: string
                path?: string
                line?: number | null
                url?: string
              }[]
            }
          }[]
        }
      } | null
    } | null
  }
}

// owner/repo of the PR itself (the base repository), read off its URL so a
// PR from a fork still queries the repository its threads live on.
export function repoFromUrl(url: string): { owner: string; repo: string } | undefined {
  const match = /^https:\/\/[^/]+\/([^/]+)\/([^/]+)\/pull\/\d+/.exec(url)

  return match ? { owner: match[1]!, repo: match[2]! } : undefined
}

const FAILED = new Set(['FAILURE', 'TIMED_OUT', 'CANCELLED', 'ACTION_REQUIRED', 'STARTUP_FAILURE', 'ERROR'])
const PENDING = new Set(['PENDING', 'EXPECTED', 'QUEUED', 'IN_PROGRESS', 'WAITING', 'REQUESTED'])

export function summarizeChecks(rollup: readonly RollupItem[] | null | undefined): CheckSummary {
  const summary: CheckSummary = { passed: 0, failed: 0, pending: 0, failedNames: [] }

  for (const item of rollup ?? []) {
    const name = item.name ?? item.context ?? 'check'
    // CheckRun: status + conclusion. StatusContext: state.
    const outcome =
      item.__typename === 'StatusContext' || item.state !== undefined
        ? item.state ?? 'PENDING'
        : item.status !== 'COMPLETED'
          ? item.status ?? 'PENDING'
          : item.conclusion ?? 'PENDING'

    if (FAILED.has(outcome)) {
      summary.failed += 1
      summary.failedNames.push(name)
    } else if (PENDING.has(outcome)) {
      summary.pending += 1
    } else {
      summary.passed += 1
    }
  }

  return summary
}

// The pr-review-loop state machine (Step 3), with the head commit's time in
// place of its push time.
export function loopState(
  lastReviewMs: number | undefined,
  headMs: number | undefined,
  unresolvedCopilot: number,
): LoopState {
  if (lastReviewMs === undefined || headMs === undefined || lastReviewMs <= headMs) {
    return 'WAITING'
  }

  return unresolvedCopilot === 0 ? 'DONE' : 'REVIEWING'
}

function firstLine(text: string, max = 120): string {
  const line = text.trim().split('\n').find(l => l.trim() !== '')?.trim() ?? ''

  return line.length <= max ? line : `${line.slice(0, max - 1)}…`
}

export function parseSnapshot(prViewJson: string, threadsJson: string, fetchedAtMs: number): PrSnapshot {
  const pr = JSON.parse(prViewJson) as PrView
  const graph = JSON.parse(threadsJson) as ThreadsResponse
  const repository = graph.data?.repository

  const copilotReviews = (pr.reviews ?? [])
    .filter(r => r.author?.login === COPILOT_LOGIN && r.submittedAt)
    .map(r => Date.parse(r.submittedAt!))
    .filter(Number.isFinite)
  const lastReviewMs = copilotReviews.length > 0 ? Math.max(...copilotReviews) : undefined

  const committedDate = repository?.object?.committedDate
  const parsedHead = committedDate ? Date.parse(committedDate) : Number.NaN
  const headMs = Number.isFinite(parsedHead) ? parsedHead : undefined

  const threads: Thread[] = (repository?.pullRequest?.reviewThreads?.nodes ?? [])
    .filter(node => !node.isResolved)
    .map(node => node.comments?.nodes?.[0])
    .filter((c): c is NonNullable<typeof c> => c !== undefined)
    .map(c => ({
      author: c.author?.login ?? 'unknown',
      isCopilot: c.author?.login === COPILOT_LOGIN,
      location: c.path ? (c.line ? `${c.path}:${c.line}` : c.path) : '',
      summary: firstLine(c.body ?? ''),
      url: c.url ?? '',
    }))

  const unresolvedCopilot = threads.filter(t => t.isCopilot).length

  return {
    number: pr.number,
    title: pr.title,
    url: pr.url,
    branch: pr.headRefName,
    isDraft: pr.isDraft === true,
    state: loopState(lastReviewMs, headMs, unresolvedCopilot),
    lastReviewMs,
    headMs,
    checks: summarizeChecks(pr.statusCheckRollup),
    threads,
    fetchedAtMs,
  }
}

export function formatAgo(thenMs: number | undefined, nowMs: number): string {
  if (thenMs === undefined) {
    return 'never'
  }

  const minutes = Math.floor(Math.max(0, nowMs - thenMs) / 60_000)
  if (minutes < 1) {
    return 'just now'
  }
  if (minutes < 60) {
    return `${minutes}m ago`
  }

  const hours = Math.floor(minutes / 60)

  return hours < 48 ? `${hours}h ago` : `${Math.floor(hours / 24)}d ago`
}

// First line of gh's stderr, for the pane's error row.
export function describeGhError(stderr: string): string {
  const line = firstLine(stderr, 160)
  if (/no pull requests found/i.test(line)) {
    return 'No open PR for this branch. Push it and open a PR, or run /pr-pane <number>.'
  }

  return line || 'gh failed with no message.'
}
