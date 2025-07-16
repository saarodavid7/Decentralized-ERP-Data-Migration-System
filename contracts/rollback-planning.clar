;; Rollback Planning Contract
;; Plans and manages migration rollback procedures

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-INPUT (err u101))
(define-constant ERR-NOT-FOUND (err u102))
(define-constant ERR-ALREADY-EXISTS (err u103))
(define-constant ERR-INVALID-STATUS (err u104))

;; Data Variables
(define-data-var next-rollback-plan-id uint u1)
(define-data-var next-checkpoint-id uint u1)

;; Data Maps
(define-map rollback-plans
  { plan-id: uint }
  {
    name: (string-ascii 50),
    transfer-id: uint,
    plan-type: (string-ascii 20),
    status: (string-ascii 20),
    created-by: principal,
    approved-by: (optional principal),
    created-at: uint,
    approved-at: (optional uint),
    last-updated: uint
  }
)

(define-map rollback-checkpoints
  { checkpoint-id: uint }
  {
    plan-id: uint,
    name: (string-ascii 50),
    checkpoint-type: (string-ascii 20),
    data-snapshot: (string-ascii 200),
    created-at: uint,
    records-count: uint,
    file-size: uint,
    verification-hash: (string-ascii 64)
  }
)

(define-map rollback-procedures
  { plan-id: uint, step-index: uint }
  {
    step-name: (string-ascii 50),
    step-type: (string-ascii 20),
    description: (string-ascii 200),
    estimated-duration: uint,
    dependencies: (list 10 uint),
    rollback-command: (string-ascii 300)
  }
)

(define-map rollback-executions
  { plan-id: uint }
  {
    executed-by: principal,
    started-at: uint,
    completed-at: (optional uint),
    status: (string-ascii 20),
    steps-completed: uint,
    steps-total: uint,
    success-rate: uint
  }
)

(define-map plan-step-count
  { plan-id: uint }
  { count: uint }
)

;; Public Functions

;; Create rollback plan
(define-public (create-rollback-plan (name (string-ascii 50)) (transfer-id uint) (plan-type (string-ascii 20)))
  (let
    (
      (plan-id (var-get next-rollback-plan-id))
    )
    (asserts! (> (len name) u0) ERR-INVALID-INPUT)
    (asserts! (> transfer-id u0) ERR-INVALID-INPUT)
    (asserts! (or (is-eq plan-type "full") (or (is-eq plan-type "partial") (or (is-eq plan-type "incremental") (is-eq plan-type "emergency")))) ERR-INVALID-INPUT)

    (map-set rollback-plans
      { plan-id: plan-id }
      {
        name: name,
        transfer-id: transfer-id,
        plan-type: plan-type,
        status: "draft",
        created-by: tx-sender,
        approved-by: none,
        created-at: block-height,
        approved-at: none,
        last-updated: block-height
      }
    )

    (map-set plan-step-count
      { plan-id: plan-id }
      { count: u0 }
    )

    (var-set next-rollback-plan-id (+ plan-id u1))
    (ok plan-id)
  )
)

;; Create checkpoint
(define-public (create-checkpoint
  (plan-id uint)
  (name (string-ascii 50))
  (checkpoint-type (string-ascii 20))
  (data-snapshot (string-ascii 200))
  (records-count uint)
  (file-size uint)
  (verification-hash (string-ascii 64)))
  (let
    (
      (checkpoint-id (var-get next-checkpoint-id))
      (plan (unwrap! (map-get? rollback-plans { plan-id: plan-id }) ERR-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get created-by plan)) ERR-NOT-AUTHORIZED)
    (asserts! (> (len name) u0) ERR-INVALID-INPUT)
    (asserts! (or (is-eq checkpoint-type "pre-migration") (or (is-eq checkpoint-type "mid-migration") (or (is-eq checkpoint-type "post-migration") (is-eq checkpoint-type "emergency")))) ERR-INVALID-INPUT)
    (asserts! (> (len verification-hash) u0) ERR-INVALID-INPUT)

    (map-set rollback-checkpoints
      { checkpoint-id: checkpoint-id }
      {
        plan-id: plan-id,
        name: name,
        checkpoint-type: checkpoint-type,
        data-snapshot: data-snapshot,
        created-at: block-height,
        records-count: records-count,
        file-size: file-size,
        verification-hash: verification-hash
      }
    )

    (var-set next-checkpoint-id (+ checkpoint-id u1))
    (ok checkpoint-id)
  )
)

;; Add rollback procedure step
(define-public (add-rollback-step
  (plan-id uint)
  (step-name (string-ascii 50))
  (step-type (string-ascii 20))
  (description (string-ascii 200))
  (estimated-duration uint)
  (dependencies (list 10 uint))
  (rollback-command (string-ascii 300)))
  (let
    (
      (plan (unwrap! (map-get? rollback-plans { plan-id: plan-id }) ERR-NOT-FOUND))
      (step-count-data (unwrap! (map-get? plan-step-count { plan-id: plan-id }) ERR-NOT-FOUND))
      (step-index (get count step-count-data))
    )
    (asserts! (is-eq tx-sender (get created-by plan)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status plan) "draft") ERR-INVALID-STATUS)
    (asserts! (> (len step-name) u0) ERR-INVALID-INPUT)
    (asserts! (or (is-eq step-type "data-restore") (or (is-eq step-type "schema-revert") (or (is-eq step-type "config-reset") (is-eq step-type "cleanup")))) ERR-INVALID-INPUT)
    (asserts! (< step-index u100) ERR-INVALID-INPUT)

    (map-set rollback-procedures
      { plan-id: plan-id, step-index: step-index }
      {
        step-name: step-name,
        step-type: step-type,
        description: description,
        estimated-duration: estimated-duration,
        dependencies: dependencies,
        rollback-command: rollback-command
      }
    )

    (map-set plan-step-count
      { plan-id: plan-id }
      { count: (+ step-index u1) }
    )

    (map-set rollback-plans
      { plan-id: plan-id }
      (merge plan { last-updated: block-height })
    )

    (ok step-index)
  )
)

;; Approve rollback plan
(define-public (approve-rollback-plan (plan-id uint))
  (let
    (
      (plan (unwrap! (map-get? rollback-plans { plan-id: plan-id }) ERR-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status plan) "draft") ERR-INVALID-STATUS)

    (map-set rollback-plans
      { plan-id: plan-id }
      (merge plan {
        status: "approved",
        approved-by: (some tx-sender),
        approved-at: (some block-height),
        last-updated: block-height
      })
    )
    (ok true)
  )
)

;; Execute rollback plan
(define-public (execute-rollback-plan (plan-id uint))
  (let
    (
      (plan (unwrap! (map-get? rollback-plans { plan-id: plan-id }) ERR-NOT-FOUND))
      (step-count-data (unwrap! (map-get? plan-step-count { plan-id: plan-id }) ERR-NOT-FOUND))
      (steps-total (get count step-count-data))
    )
    (asserts! (is-eq (get status plan) "approved") ERR-INVALID-STATUS)
    (asserts! (> steps-total u0) ERR-INVALID-INPUT)
    (asserts! (is-none (map-get? rollback-executions { plan-id: plan-id })) ERR-ALREADY-EXISTS)

    (map-set rollback-executions
      { plan-id: plan-id }
      {
        executed-by: tx-sender,
        started-at: block-height,
        completed-at: none,
        status: "in-progress",
        steps-completed: u0,
        steps-total: steps-total,
        success-rate: u0
      }
    )

    (map-set rollback-plans
      { plan-id: plan-id }
      (merge plan { status: "executing", last-updated: block-height })
    )

    (ok true)
  )
)

;; Update rollback execution progress
(define-public (update-rollback-progress (plan-id uint) (steps-completed uint))
  (let
    (
      (execution (unwrap! (map-get? rollback-executions { plan-id: plan-id }) ERR-NOT-FOUND))
      (steps-total (get steps-total execution))
      (success-rate (if (> steps-total u0) (/ (* steps-completed u100) steps-total) u0))
    )
    (asserts! (is-eq tx-sender (get executed-by execution)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status execution) "in-progress") ERR-INVALID-STATUS)
    (asserts! (<= steps-completed steps-total) ERR-INVALID-INPUT)

    (map-set rollback-executions
      { plan-id: plan-id }
      (merge execution {
        steps-completed: steps-completed,
        success-rate: success-rate
      })
    )

    (ok true)
  )
)

;; Complete rollback execution
(define-public (complete-rollback-execution (plan-id uint))
  (let
    (
      (plan (unwrap! (map-get? rollback-plans { plan-id: plan-id }) ERR-NOT-FOUND))
      (execution (unwrap! (map-get? rollback-executions { plan-id: plan-id }) ERR-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get executed-by execution)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status execution) "in-progress") ERR-INVALID-STATUS)

    (map-set rollback-executions
      { plan-id: plan-id }
      (merge execution {
        status: "completed",
        completed-at: (some block-height),
        success-rate: u100
      })
    )

    (map-set rollback-plans
      { plan-id: plan-id }
      (merge plan { status: "executed", last-updated: block-height })
    )

    (ok true)
  )
)

;; Read-only Functions

;; Get rollback plan
(define-read-only (get-rollback-plan (plan-id uint))
  (map-get? rollback-plans { plan-id: plan-id })
)

;; Get rollback checkpoint
(define-read-only (get-rollback-checkpoint (checkpoint-id uint))
  (map-get? rollback-checkpoints { checkpoint-id: checkpoint-id })
)

;; Get rollback procedure step
(define-read-only (get-rollback-step (plan-id uint) (step-index uint))
  (map-get? rollback-procedures { plan-id: plan-id, step-index: step-index })
)

;; Get rollback execution
(define-read-only (get-rollback-execution (plan-id uint))
  (map-get? rollback-executions { plan-id: plan-id })
)

;; Get plan step count
(define-read-only (get-plan-step-count (plan-id uint))
  (map-get? plan-step-count { plan-id: plan-id })
)

;; Check if plan is ready for execution
(define-read-only (is-plan-ready-for-execution (plan-id uint))
  (match (map-get? rollback-plans { plan-id: plan-id })
    plan
      (and
        (is-eq (get status plan) "approved")
        (is-some (get approved-by plan))
      )
    false
  )
)

;; Get next rollback plan ID
(define-read-only (get-next-rollback-plan-id)
  (var-get next-rollback-plan-id)
)

;; Get next checkpoint ID
(define-read-only (get-next-checkpoint-id)
  (var-get next-checkpoint-id)
)
