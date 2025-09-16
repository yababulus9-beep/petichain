;; petition-manager
;; Core petition management contract for Petichain platform
;; Handles petition creation, validation, and status management

;; =============================================================================
;; CONSTANTS
;; =============================================================================

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_INVALID_PETITION (err u402))
(define-constant ERR_PETITION_NOT_FOUND (err u404))
(define-constant ERR_PETITION_EXPIRED (err u405))
(define-constant ERR_INVALID_PARAMS (err u400))
(define-constant ERR_ALREADY_SIGNED (err u409))

;; Maximum allowed values for validation
(define-constant MAX_TITLE_LENGTH u200)
(define-constant MAX_DESCRIPTION_LENGTH u1000)
(define-constant MIN_TARGET_SIGNATURES u1)
(define-constant MAX_TARGET_SIGNATURES u1000000)

;; Status constants
(define-constant STATUS_ACTIVE "active")
(define-constant STATUS_SUCCESSFUL "successful")
(define-constant STATUS_EXPIRED "expired")
(define-constant STATUS_CANCELLED "cancelled")

;; =============================================================================
;; DATA VARIABLES
;; =============================================================================

(define-data-var petition-count uint u0)
(define-data-var contract-initialized bool false)

;; =============================================================================
;; DATA MAPS
;; =============================================================================

;; Main petition storage
(define-map petitions 
    uint
    {
        id: uint,
        title: (string-ascii 200),
        description: (string-utf8 1000),
        creator: principal,
        target-signatures: uint,
        current-signatures: uint,
        deadline: uint,
        created-at: uint,
        status: (string-ascii 20)
    }
)

;; Track petition creators for analytics
(define-map creator-petitions principal (list 50 uint))

;; Track petition categories for organization
(define-map petition-categories uint (string-ascii 50))

;; Emergency admin controls
(define-map admin-permissions principal bool)

;; =============================================================================
;; INITIALIZATION FUNCTIONS
;; =============================================================================

;; Initialize contract with default settings
(define-public (initialize-contract)
    (begin
        (asserts! (not (var-get contract-initialized)) ERR_UNAUTHORIZED)
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (map-set admin-permissions CONTRACT_OWNER true)
        (var-set contract-initialized true)
        (ok true)
    )
)

;; =============================================================================
;; PUBLIC FUNCTIONS - PETITION MANAGEMENT
;; =============================================================================

;; Create a new petition with comprehensive validation
(define-public (create-petition 
    (title (string-ascii 200)) 
    (description (string-utf8 1000)) 
    (target-signatures uint) 
    (deadline uint)
    (category (string-ascii 50))
)
    (let 
        (
            (petition-id (+ (var-get petition-count) u1))
            (current-time (unwrap! (get-stacks-block-info? time u0) ERR_INVALID_PARAMS))
        )
        ;; Comprehensive input validation
        (asserts! (and 
            (> (len title) u0) 
            (<= (len title) MAX_TITLE_LENGTH)
        ) ERR_INVALID_PARAMS)
        (asserts! (and 
            (> (len description) u0) 
            (<= (len description) MAX_DESCRIPTION_LENGTH)
        ) ERR_INVALID_PARAMS)
        (asserts! (and 
            (>= target-signatures MIN_TARGET_SIGNATURES) 
            (<= target-signatures MAX_TARGET_SIGNATURES)
        ) ERR_INVALID_PARAMS)
        (asserts! (> deadline current-time) ERR_INVALID_PARAMS)
        
        ;; Create petition record
        (map-set petitions petition-id {
            id: petition-id,
            title: title,
            description: description,
            creator: tx-sender,
            target-signatures: target-signatures,
            current-signatures: u0,
            deadline: deadline,
            created-at: current-time,
            status: STATUS_ACTIVE
        })
        
        ;; Set category if provided
        (if (> (len category) u0)
            (map-set petition-categories petition-id category)
            true
        )
        
        ;; Update creator tracking
        (update-creator-petitions tx-sender petition-id)
        
        ;; Increment counter
        (var-set petition-count petition-id)
        
        (ok petition-id)
    )
)

;; Update petition signature count (called by signature validator)
(define-public (increment-signature-count (petition-id uint))
    (let 
        (
            (petition (unwrap! (get-petition-data petition-id) ERR_PETITION_NOT_FOUND))
            (new-count (+ (get current-signatures petition) u1))
        )
        ;; Validate petition exists and is active
        (asserts! (is-petition-active petition-id) ERR_PETITION_EXPIRED)
        
        ;; Update signature count
        (map-set petitions petition-id (merge petition {
            current-signatures: new-count,
            status: (if (>= new-count (get target-signatures petition))
                STATUS_SUCCESSFUL
                STATUS_ACTIVE
            )
        }))
        
        (ok new-count)
    )
)

;; Cancel petition (only by creator or admin)
(define-public (cancel-petition (petition-id uint))
    (let 
        (
            (petition (unwrap! (get-petition-data petition-id) ERR_PETITION_NOT_FOUND))
        )
        ;; Authorization check
        (asserts! (or 
            (is-eq tx-sender (get creator petition))
            (default-to false (map-get? admin-permissions tx-sender))
        ) ERR_UNAUTHORIZED)
        
        ;; Can only cancel active petitions
        (asserts! (is-eq (get status petition) STATUS_ACTIVE) ERR_INVALID_PETITION)
        
        ;; Update status
        (map-set petitions petition-id (merge petition {
            status: STATUS_CANCELLED
        }))
        
        (ok true)
    )
)

;; Update petition status based on deadline
(define-public (update-petition-status (petition-id uint))
    (let 
        (
            (petition (unwrap! (get-petition-data petition-id) ERR_PETITION_NOT_FOUND))
            (current-time (unwrap! (get-stacks-block-info? time u0) ERR_INVALID_PARAMS))
        )
        ;; Check if petition has expired
        (if (and 
            (is-eq (get status petition) STATUS_ACTIVE)
            (> current-time (get deadline petition))
        )
            (begin
                (map-set petitions petition-id (merge petition {
                    status: STATUS_EXPIRED
                }))
                (ok STATUS_EXPIRED)
            )
            (ok (get status petition))
        )
    )
)

;; =============================================================================
;; READ-ONLY FUNCTIONS - DATA RETRIEVAL
;; =============================================================================

;; Get petition details by ID
(define-read-only (get-petition (petition-id uint))
    (map-get? petitions petition-id)
)

;; Get total petition count
(define-read-only (get-petition-count)
    (var-get petition-count)
)

;; Check if petition is active and accepting signatures
(define-read-only (is-petition-active (petition-id uint))
    (match (get-petition petition-id)
        petition (let 
            (
                (current-time (unwrap! (get-stacks-block-info? time u0) false))
            )
            (and 
                (is-eq (get status petition) STATUS_ACTIVE)
                (< current-time (get deadline petition))
            )
        )
        false
    )
)

;; Get petition category
(define-read-only (get-petition-category (petition-id uint))
    (map-get? petition-categories petition-id)
)

;; Get petitions created by a specific user
(define-read-only (get-creator-petitions (creator principal))
    (default-to (list) (map-get? creator-petitions creator))
)

;; Check petition progress (percentage completion)
(define-read-only (get-petition-progress (petition-id uint))
    (match (get-petition petition-id)
        petition (let 
            (
                (current (get current-signatures petition))
                (target (get target-signatures petition))
                (percentage (if (> target u0) (/ (* current u100) target) u0))
            )
            (if (> percentage u100) u100 percentage)
        )
        u0
    )
)

;; Get petition statistics
(define-read-only (get-petition-stats (petition-id uint))
    (match (get-petition petition-id)
        petition (let 
            (
                (current-time (unwrap! (get-stacks-block-info? time u0) none))
                (time-remaining (if (> (get deadline petition) current-time)
                    (some (- (get deadline petition) current-time))
                    none
                ))
            )
            (some {
                petition-id: petition-id,
                current-signatures: (get current-signatures petition),
                target-signatures: (get target-signatures petition),
                progress-percentage: (get-petition-progress petition-id),
                time-remaining: time-remaining,
                status: (get status petition),
                is-successful: (>= (get current-signatures petition) (get target-signatures petition))
            })
        )
        none
    )
)

;; =============================================================================
;; PRIVATE HELPER FUNCTIONS
;; =============================================================================

;; Internal function to get petition data safely
(define-private (get-petition-data (petition-id uint))
    (map-get? petitions petition-id)
)

;; Update creator petition tracking
(define-private (update-creator-petitions (creator principal) (petition-id uint))
    (let 
        (
            (current-list (default-to (list) (map-get? creator-petitions creator)))
        )
        (map-set creator-petitions creator 
            (unwrap! (as-max-len? (append current-list petition-id) u50) false)
        )
    )
)

;; Validate petition status
(define-private (is-valid-status (status (string-ascii 20)))
    (or 
        (is-eq status STATUS_ACTIVE)
        (is-eq status STATUS_SUCCESSFUL)
        (is-eq status STATUS_EXPIRED)
        (is-eq status STATUS_CANCELLED)
    )
)
