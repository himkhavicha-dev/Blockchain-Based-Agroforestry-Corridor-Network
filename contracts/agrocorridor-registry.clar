;; AgroCorridorRegistry.clar
;; Core contract for registering and managing agroforestry corridors
;; Features include registration, updates, stakeholder management, versioning, status tracking, and more

;; Constants
(define-constant ERR-UNAUTHORIZED u100)
(define-constant ERR-ALREADY-REGISTERED u101)
(define-constant ERR-NOT-FOUND u102)
(define-constant ERR-INVALID-PARAM u103)
(define-constant ERR-PAUSED u104)
(define-constant ERR-INVALID-STAKEHOLDER u105)
(define-constant ERR-MAX-STAKEHOLDERS u106)
(define-constant ERR-MAX-TAGS u107)
(define-constant ERR-MAX-VERSIONS u108)
(define-constant MAX-STAKEHOLDERS u20)
(define-constant MAX-TAGS u15)
(define-constant MAX_VERSIONS u50)
(define-constant MAX_BOUNDARY_LEN u512)
(define-constant MAX_SPECIES_LEN u256)
(define-constant MAX_DESCRIPTION_LEN u1024)

;; Data Variables
(define-data-var contract-admin principal tx-sender)
(define-data-var paused bool false)
(define-data-var corridor-counter uint u0)

;; Data Maps
(define-map corridors
  { corridor-id: uint }
  {
    boundaries: (string-utf8 MAX_BOUNDARY_LEN),      ;; GeoJSON or description of boundaries
    species: (string-utf8 MAX_SPECIES_LEN),          ;; Tree-crop combinations
    regions: (list 10 principal),                    ;; Involved regions/principals
    owner: principal,                                ;; Creator/owner
    created-at: uint,
    updated-at: uint,
    description: (string-utf8 MAX_DESCRIPTION_LEN),  ;; Detailed agroforestry plan
    active: bool
  }
)

(define-map corridor-stakeholders
  { corridor-id: uint, stakeholder: principal }
  {
    role: (string-utf8 50),                          ;; e.g., "farmer", "ngo", "government"
    permissions: (list 5 (string-utf8 20)),          ;; e.g., "update", "monitor"
    added-at: uint
  }
)

(define-map corridor-versions
  { corridor-id: uint, version: uint }
  {
    changes: (string-utf8 500),                      ;; Description of changes
    timestamp: uint,
    updater: principal
  }
)

(define-map corridor-status
  { corridor-id: uint }
  {
    status: (string-utf8 20),                        ;; e.g., "planning", "active", "degraded"
    visibility: bool,                                ;; Public or private
    last-checked: uint
  }
)

(define-map corridor-tags
  { corridor-id: uint }
  {
    tags: (list MAX-TAGS (string-utf8 30))           ;; Categorization tags
  }
)

(define-map corridor-metrics
  { corridor-id: uint }
  {
    biodiversity-score: uint,                        ;; Arbitrary score 0-100
    carbon-sequestered: uint,                        ;; In tons
    area-covered: uint                               ;; In hectares
  }
)

;; Public Functions

(define-public (pause-contract)
  (begin
    (asserts! (is-eq tx-sender (var-get contract-admin)) (err ERR-UNAUTHORIZED))
    (var-set paused true)
    (ok true)
  )
)

(define-public (unpause-contract)
  (begin
    (asserts! (is-eq tx-sender (var-get contract-admin)) (err ERR-UNAUTHORIZED))
    (var-set paused false)
    (ok true)
  )
)

(define-public (set-admin (new-admin principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-admin)) (err ERR-UNAUTHORIZED))
    (var-set contract-admin new-admin)
    (ok true)
  )
)

(define-public (register-corridor 
  (boundaries (string-utf8 MAX_BOUNDARY_LEN)) 
  (species (string-utf8 MAX_SPECIES_LEN)) 
  (regions (list 10 principal)) 
  (description (string-utf8 MAX_DESCRIPTION_LEN)))
  (let
    (
      (id (+ (var-get corridor-counter) u1))
      (current-height block-height)
    )
    (asserts! (not (var-get paused)) (err ERR-PAUSED))
    (asserts! (> (len boundaries) u0) (err ERR-INVALID-PARAM))
    (asserts! (> (len species) u0) (err ERR-INVALID-PARAM))
    (asserts! (> (len regions) u0) (err ERR-INVALID-PARAM))
    (try! (map-set corridors
      { corridor-id: id }
      {
        boundaries: boundaries,
        species: species,
        regions: regions,
        owner: tx-sender,
        created-at: current-height,
        updated-at: current-height,
        description: description,
        active: true
      }
    ))
    (try! (map-set corridor-status
      { corridor-id: id }
      {
        status: u"planning",
        visibility: true,
        last-checked: current-height
      }
    ))
    (try! (map-set corridor-metrics
      { corridor-id: id }
      {
        biodiversity-score: u0,
        carbon-sequestered: u0,
        area-covered: u0
      }
    ))
    (var-set corridor-counter id)
    (print { event: "corridor-registered", id: id, owner: tx-sender })
    (ok id)
  )
)

(define-public (update-corridor 
  (id uint) 
  (new-boundaries (optional (string-utf8 MAX_BOUNDARY_LEN))) 
  (new-species (optional (string-utf8 MAX_SPECIES_LEN))) 
  (new-description (optional (string-utf8 MAX_DESCRIPTION_LEN))))
  (let
    (
      (corridor-opt (map-get? corridors { corridor-id: id }))
      (current-height block-height)
      (version-count (default-to u0 (map-get? corridor-version-count { corridor-id: id })))
    )
    (asserts! (not (var-get paused)) (err ERR-PAUSED))
    (asserts! (is-some corridor-opt) (err ERR-NOT-FOUND))
    (let ((corridor (unwrap! corridor-opt (err ERR-NOT-FOUND))))
      (asserts! (is-eq (get owner corridor) tx-sender) (err ERR-UNAUTHORIZED))
      (let
        (
          (updated-corridor (merge corridor {
            boundaries: (default-to (get boundaries corridor) new-boundaries),
            species: (default-to (get species corridor) new-species),
            description: (default-to (get description corridor) new-description),
            updated-at: current-height
          }))
        )
        (try! (map-set corridors { corridor-id: id } updated-corridor))
        (try! (map-set corridor-versions
          { corridor-id: id, version: (+ version-count u1) }
          {
            changes: "Updated boundaries, species, or description",
            timestamp: current-height,
            updater: tx-sender
          }
        ))
        (map-set corridor-version-count { corridor-id: id } (+ version-count u1))
        (print { event: "corridor-updated", id: id, updater: tx-sender })
        (ok true)
      )
    )
  )
)

(define-public (add-stakeholder (id uint) (stakeholder principal) (role (string-utf8 50)) (permissions (list 5 (string-utf8 20))))
  (let
    (
      (corridor-opt (map-get? corridors { corridor-id: id }))
      (current-height block-height)
      (stakeholder-count (len (get-stakeholders id)))
    )
    (asserts! (not (var-get paused)) (err ERR-PAUSED))
    (asserts! (is-some corridor-opt) (err ERR-NOT-FOUND))
    (let ((corridor (unwrap! corridor-opt (err ERR-NOT-FOUND))))
      (asserts! (is-eq (get owner corridor) tx-sender) (err ERR-UNAUTHORIZED))
      (asserts! (< stakeholder-count MAX-STAKEHOLDERS) (err ERR-MAX-STAKEHOLDERS))
      (asserts! (is-none (map-get? corridor-stakeholders { corridor-id: id, stakeholder: stakeholder })) (err ERR-ALREADY-REGISTERED))
      (try! (map-set corridor-stakeholders
        { corridor-id: id, stakeholder: stakeholder }
        {
          role: role,
          permissions: permissions,
          added-at: current-height
        }
      ))
      (print { event: "stakeholder-added", id: id, stakeholder: stakeholder })
      (ok true)
    )
  )
)

(define-public (remove-stakeholder (id uint) (stakeholder principal))
  (let
    (
      (corridor-opt (map-get? corridors { corridor-id: id }))
    )
    (asserts! (not (var-get paused)) (err ERR-PAUSED))
    (asserts! (is-some corridor-opt) (err ERR-NOT-FOUND))
    (let ((corridor (unwrap! corridor-opt (err ERR-NOT-FOUND))))
      (asserts! (is-eq (get owner corridor) tx-sender) (err ERR-UNAUTHORIZED))
      (asserts! (is-some (map-get? corridor-stakeholders { corridor-id: id, stakeholder: stakeholder })) (err ERR-NOT-FOUND))
      (map-delete corridor-stakeholders { corridor-id: id, stakeholder: stakeholder })
      (print { event: "stakeholder-removed", id: id, stakeholder: stakeholder })
      (ok true)
    )
  )
)

(define-public (update-status (id uint) (new-status (string-utf8 20)) (new-visibility bool))
  (let
    (
      (corridor-opt (map-get? corridors { corridor-id: id }))
      (current-height block-height)
    )
    (asserts! (not (var-get paused)) (err ERR-PAUSED))
    (asserts! (is-some corridor-opt) (err ERR-NOT-FOUND))
    (let ((corridor (unwrap! corridor-opt (err ERR-NOT-FOUND))))
      (asserts! (is-eq (get owner corridor) tx-sender) (err ERR-UNAUTHORIZED))
      (try! (map-set corridor-status
        { corridor-id: id }
        {
          status: new-status,
          visibility: new-visibility,
          last-checked: current-height
        }
      ))
      (print { event: "status-updated", id: id, status: new-status })
      (ok true)
    )
  )
)

(define-public (add-tags (id uint) (new-tags (list MAX-TAGS (string-utf8 30))))
  (let
    (
      (corridor-opt (map-get? corridors { corridor-id: id }))
    )
    (asserts! (not (var-get paused)) (err ERR-PAUSED))
    (asserts! (is-some corridor-opt) (err ERR-NOT-FOUND))
    (let ((corridor (unwrap! corridor-opt (err ERR-NOT-FOUND))))
      (asserts! (is-eq (get owner corridor) tx-sender) (err ERR-UNAUTHORIZED))
      (try! (map-set corridor-tags
        { corridor-id: id }
        { tags: new-tags }
      ))
      (ok true)
    )
  )
)

(define-public (update-metrics (id uint) (biodiversity uint) (carbon uint) (area uint))
  (let
    (
      (corridor-opt (map-get? corridors { corridor-id: id }))
    )
    (asserts! (not (var-get paused)) (err ERR-PAUSED))
    (asserts! (is-some corridor-opt) (err ERR-NOT-FOUND))
    (let ((corridor (unwrap! corridor-opt (err ERR-NOT-FOUND))))
      (asserts! (or (is-eq (get owner corridor) tx-sender) (has-permission id tx-sender "update-metrics")) (err ERR-UNAUTHORIZED))
      (try! (map-set corridor-metrics
        { corridor-id: id }
        {
          biodiversity-score: biodiversity,
          carbon-sequestered: carbon,
          area-covered: area
        }
      ))
      (print { event: "metrics-updated", id: id, biodiversity: biodiversity, carbon: carbon, area: area })
      (ok true)
    )
  )
)

(define-public (deactivate-corridor (id uint))
  (let
    (
      (corridor-opt (map-get? corridors { corridor-id: id }))
    )
    (asserts! (not (var-get paused)) (err ERR-PAUSED))
    (asserts! (is-some corridor-opt) (err ERR-NOT-FOUND))
    (let ((corridor (unwrap! corridor-opt (err ERR-NOT-FOUND))))
      (asserts! (is-eq (get owner corridor) tx-sender) (err ERR-UNAUTHORIZED))
      (try! (map-set corridors { corridor-id: id } (merge corridor { active: false })))
      (print { event: "corridor-deactivated", id: id })
      (ok true)
    )
  )
)

;; Read-Only Functions

(define-read-only (get-corridor-details (id uint))
  (map-get? corridors { corridor-id: id })
)

(define-read-only (get-corridor-status (id uint))
  (map-get? corridor-status { corridor-id: id })
)

(define-read-only (get-corridor-metrics (id uint))
  (map-get? corridor-metrics { corridor-id: id })
)

(define-read-only (get-corridor-tags (id uint))
  (map-get? corridor-tags { corridor-id: id })
)

(define-read-only (get-stakeholder (id uint) (stakeholder principal))
  (map-get? corridor-stakeholders { corridor-id: id, stakeholder: stakeholder })
)

(define-read-only (get-version (id uint) (version uint))
  (map-get? corridor-versions { corridor-id: id, version: version })
)

(define-read-only (is-owner (id uint) (account principal))
  (let ((corridor (map-get? corridors { corridor-id: id })))
    (if (is-some corridor)
      (is-eq (get owner (unwrap! corridor none)) account)
      false
    )
  )
)

(define-read-only (has-permission (id uint) (account principal) (perm (string-utf8 20)))
  (let ((sh (map-get? corridor-stakeholders { corridor-id: id, stakeholder: account })))
    (if (is-some sh)
      (is-some (index-of (get permissions (unwrap! sh none)) perm))
      false
    )
  )
)

(define-read-only (get-total-corridors)
  (var-get corridor-counter)
)

(define-read-only (is-paused)
  (var-get paused)
)

(define-read-only (get-admin)
  (var-get contract-admin)
)

;; Private Functions

(define-private (get-stakeholders (id uint))
  (filter is-some (map get-stakeholder-for-id (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10 u11 u12 u13 u14 u15 u16 u17 u18 u19 u20)))  ;; Simplified, in real would need better way
)

(define-private (get-stakeholder-for-id (index uint))
  (none)  ;; Placeholder for actual impl
)

;; Additional maps for version count
(define-map corridor-version-count { corridor-id: uint } uint)