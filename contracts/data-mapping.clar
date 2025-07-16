;; Data Mapping Contract
;; Maps migration data between different ERP systems

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-INPUT (err u101))
(define-constant ERR-NOT-FOUND (err u102))
(define-constant ERR-ALREADY-EXISTS (err u103))

;; Data Variables
(define-data-var next-mapping-id uint u1)

;; Data Maps
(define-map data-mappings
  { mapping-id: uint }
  {
    name: (string-ascii 50),
    source-system: (string-ascii 30),
    target-system: (string-ascii 30),
    created-by: principal,
    active: bool,
    created-at: uint,
    last-updated: uint
  }
)

(define-map field-mappings
  { mapping-id: uint, field-index: uint }
  {
    source-field: (string-ascii 50),
    target-field: (string-ascii 50),
    data-type: (string-ascii 20),
    transformation-rule: (string-ascii 100),
    required: bool,
    default-value: (optional (string-ascii 100))
  }
)

(define-map mapping-field-count
  { mapping-id: uint }
  { count: uint }
)

;; Public Functions

;; Create a new data mapping
(define-public (create-mapping (name (string-ascii 50)) (source-system (string-ascii 30)) (target-system (string-ascii 30)))
  (let
    (
      (mapping-id (var-get next-mapping-id))
    )
    (asserts! (> (len name) u0) ERR-INVALID-INPUT)
    (asserts! (> (len source-system) u0) ERR-INVALID-INPUT)
    (asserts! (> (len target-system) u0) ERR-INVALID-INPUT)

    (map-set data-mappings
      { mapping-id: mapping-id }
      {
        name: name,
        source-system: source-system,
        target-system: target-system,
        created-by: tx-sender,
        active: true,
        created-at: block-height,
        last-updated: block-height
      }
    )

    (map-set mapping-field-count
      { mapping-id: mapping-id }
      { count: u0 }
    )

    (var-set next-mapping-id (+ mapping-id u1))
    (ok mapping-id)
  )
)

;; Add field mapping
(define-public (add-field-mapping
  (mapping-id uint)
  (source-field (string-ascii 50))
  (target-field (string-ascii 50))
  (data-type (string-ascii 20))
  (transformation-rule (string-ascii 100))
  (required bool)
  (default-value (optional (string-ascii 100))))
  (let
    (
      (mapping (unwrap! (map-get? data-mappings { mapping-id: mapping-id }) ERR-NOT-FOUND))
      (field-count-data (unwrap! (map-get? mapping-field-count { mapping-id: mapping-id }) ERR-NOT-FOUND))
      (field-index (get count field-count-data))
    )
    (asserts! (is-eq tx-sender (get created-by mapping)) ERR-NOT-AUTHORIZED)
    (asserts! (> (len source-field) u0) ERR-INVALID-INPUT)
    (asserts! (> (len target-field) u0) ERR-INVALID-INPUT)
    (asserts! (< field-index u100) ERR-INVALID-INPUT)

    (map-set field-mappings
      { mapping-id: mapping-id, field-index: field-index }
      {
        source-field: source-field,
        target-field: target-field,
        data-type: data-type,
        transformation-rule: transformation-rule,
        required: required,
        default-value: default-value
      }
    )

    (map-set mapping-field-count
      { mapping-id: mapping-id }
      { count: (+ field-index u1) }
    )

    (map-set data-mappings
      { mapping-id: mapping-id }
      (merge mapping { last-updated: block-height })
    )

    (ok field-index)
  )
)

;; Update field mapping
(define-public (update-field-mapping
  (mapping-id uint)
  (field-index uint)
  (source-field (string-ascii 50))
  (target-field (string-ascii 50))
  (data-type (string-ascii 20))
  (transformation-rule (string-ascii 100))
  (required bool)
  (default-value (optional (string-ascii 100))))
  (let
    (
      (mapping (unwrap! (map-get? data-mappings { mapping-id: mapping-id }) ERR-NOT-FOUND))
      (field-mapping (unwrap! (map-get? field-mappings { mapping-id: mapping-id, field-index: field-index }) ERR-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get created-by mapping)) ERR-NOT-AUTHORIZED)
    (asserts! (> (len source-field) u0) ERR-INVALID-INPUT)
    (asserts! (> (len target-field) u0) ERR-INVALID-INPUT)

    (map-set field-mappings
      { mapping-id: mapping-id, field-index: field-index }
      {
        source-field: source-field,
        target-field: target-field,
        data-type: data-type,
        transformation-rule: transformation-rule,
        required: required,
        default-value: default-value
      }
    )

    (map-set data-mappings
      { mapping-id: mapping-id }
      (merge mapping { last-updated: block-height })
    )

    (ok true)
  )
)

;; Deactivate mapping
(define-public (deactivate-mapping (mapping-id uint))
  (let
    (
      (mapping (unwrap! (map-get? data-mappings { mapping-id: mapping-id }) ERR-NOT-FOUND))
    )
    (asserts! (or (is-eq tx-sender CONTRACT-OWNER) (is-eq tx-sender (get created-by mapping))) ERR-NOT-AUTHORIZED)

    (map-set data-mappings
      { mapping-id: mapping-id }
      (merge mapping { active: false, last-updated: block-height })
    )
    (ok true)
  )
)

;; Read-only Functions

;; Get data mapping
(define-read-only (get-mapping (mapping-id uint))
  (map-get? data-mappings { mapping-id: mapping-id })
)

;; Get field mapping
(define-read-only (get-field-mapping (mapping-id uint) (field-index uint))
  (map-get? field-mappings { mapping-id: mapping-id, field-index: field-index })
)

;; Get field count for mapping
(define-read-only (get-field-count (mapping-id uint))
  (map-get? mapping-field-count { mapping-id: mapping-id })
)

;; Check if mapping is compatible
(define-read-only (is-mapping-compatible (mapping-id uint) (source (string-ascii 30)) (target (string-ascii 30)))
  (match (map-get? data-mappings { mapping-id: mapping-id })
    mapping
      (and
        (get active mapping)
        (is-eq (get source-system mapping) source)
        (is-eq (get target-system mapping) target)
      )
    false
  )
)

;; Get next mapping ID
(define-read-only (get-next-mapping-id)
  (var-get next-mapping-id)
)
