# Phase 11: Dashboard Upgrades — Real-Time Updates, Tamper-Evident Audit

## Verification Gate
All platform Go tests pass. Dashboard backend compiles. Audit archive bucket config validates. SSE endpoint is structurally present.

## Dependencies
Phase 10 must be complete (observability infrastructure in place before dashboard consumes it).

---

## Tasks

- [x] 36. Implement Server-Sent Events for real-time dashboard updates
  - [x] 36.1 **GREEN**: Create `admin-dashboard/server/routes/stream.ts`. Implement SSE endpoint at `GET /api/stream` that: sets `Content-Type: text/event-stream`, keeps the connection open, and pushes `data: {json}\n\n` events when app status changes. _Req: 27.1_
  - [x] 36.2 **GREEN**: Implement a server-side status poller (setInterval, 10s) that compares current ECS service states to the last-known state. On change, emit a `status-change` event to all connected SSE clients. _Req: 27.2_
  - [x] 36.3 **GREEN**: Update `admin-dashboard/src/hooks/useApps.ts` (or create `useSSE.ts`). Subscribe to `/api/stream` via `EventSource`. On `status-change` event, update the app list state. On disconnect, fall back to 30s polling and show a "reconnecting" indicator. _Req: 27.3, 27.4_
  - [x] 36.4 **GREEN**: Wire the SSE route into `server/index.ts` (no auth required for SSE — it's read-only status). Add CORS headers for SSE. _Req: 27.1_
  - [x] 36.5 **REFACTOR**: Add inline comments on SSE vs WebSocket rationale, reconnection strategy, and ALB idle timeout considerations (set to 120s for SSE). _Req: 12.5_

- [x] 37. Implement tamper-evident audit trail export to S3 with Object Lock
  - [x] 37.1 **RED**: Write property test `test/audit_archive_test.go` — Property 24: The audit archive bucket has Object Lock in COMPLIANCE mode with ≥365-day retention and no delete permission granted to any principal. Test should FAIL. _Validates: Req 28.1, 28.2, 28.4_
  - [x] 37.2 **GREEN**: Create `modules/admin-dashboard/audit-archive.tf`. Provision `aws_s3_bucket` with `object_lock_enabled = true`. Configure `aws_s3_bucket_object_lock_configuration` with default retention (COMPLIANCE, 365 days). Add `aws_s3_bucket_public_access_block`. Add bucket policy explicitly denying `s3:DeleteObject` and `s3:PutObjectRetention` (reduce retention) for all principals. Test from 37.1 should PASS. _Req: 28.1, 28.2, 28.4_
  - [x] 37.3 **GREEN**: Create `modules/admin-dashboard/audit-export.tf`. Provision an EventBridge scheduled rule (daily at 02:00 UTC) that triggers a Lambda function (or ECS task) to query DynamoDB for the previous day's audit items and write them as newline-delimited JSON to the archive bucket. _Req: 28.3_
  - [x] 37.4 **GREEN**: Create the export Lambda function code (`scripts/audit-export/index.ts` or `index.py`). Query DynamoDB with a date-range filter, format as NDJSON, upload to S3 with a key pattern `audit/{date}/audit-{timestamp}.json`. _Req: 28.3_
  - [x] 37.5 **GREEN**: Grant the export Lambda/task role `dynamodb:Query` on the audit table and `s3:PutObject` on the archive bucket. Do NOT grant `s3:DeleteObject`. _Req: 28.4_
  - [x] 37.6 **REFACTOR**: Add inline comments on Object Lock compliance mode vs governance mode, why 365-day retention, and the immutability guarantee for auditors. _Req: 12.5_

---

## Phase 11 Checkpoint (FINAL)

- [x] Run `go test ./...` — ALL platform tests pass (Phases 1–11)
- [x] Dashboard backend compiles with SSE route
- [x] Audit archive bucket config validates (Object Lock + no-delete policy)
- [x] All documentation updated (runbook, README, architecture diagrams)
- [x] Project is complete with all enhancements
