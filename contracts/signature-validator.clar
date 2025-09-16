;; signature-validator
;; Digital signature verification and storage contract for Petichain platform
;; Handles signature validation, anti-duplicate enforcement, and signer tracking

;; =============================================================================
;; CONSTANTS
;; =============================================================================

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_INVALID_SIGNATURE (err u402))
(define-constant ERR_PETITION_NOT_FOUND (err u404))
(define-constant ERR_ALREADY_SIGNED (err u409))
(define-constant ERR_PETITION_INACTIVE (err u410))
(define-constant ERR_INVALID_PARAMS (err u400))
(define-constant ERR_SIGNATURE_EXPIRED (err u411))

;; Signature validation constants
(define-constant SIGNATURE_LENGTH u65)
(define-constant MAX_SIGNATURES_PER_PETITION u1000000)
(define-constant SIGNATURE_VALIDITY_PERIOD u86400) ;; 24 hours in seconds

;; Message prefix for signature verification
(define-constant MESSAGE_PREFIX "PETICHAIN_SIGNATURE:")

;; =============================================================================
;; DATA VARIABLES
;; =============================================================================

(define-data-var total-signatures uint u0)
(define-data-var contract-initialized bool false)

;; =============================================================================
;; DATA MAPS
;; =============================================================================

;; Store signature records with verification data
(define-map signatures
    {petition-id: uint, signer: principal}
    {
        signature: (buff 65),
        signed-at: uint,
        verified: bool,
        signature-hash: (buff 32),
        block-height: uint
    }
)

;; Track signature counts per petition for quick lookups
(define-map petition-signature-counts uint uint)

;; Store signer lists per petition (up to 1000 signers per petition)
(define-map petition-signers uint (list 1000 principal))

;; Individual signature verification status
(define-map signature-verification-status
    {petition-id: uint, signer: principal}
    bool
)

;; Signature metadata for analytics
(define-map signature-metadata
    {petition-id: uint, signer: principal}
    {
        ip-hash: (optional (buff 32)),
        user-agent-hash: (optional (buff 32)),
        timestamp: uint,
        verification-method: (string-ascii 20)
    }
)

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
;; PUBLIC FUNCTIONS - SIGNATURE OPERATIONS
;; =============================================================================

;; Sign a petition with verified digital signature
(define-public (sign-petition 
    (petition-id uint) 
    (signature (buff 65))
    (verification-method (string-ascii 20))
)
    (let 
        (
            (signer tx-sender)
            (current-time (unwrap! (get-stacks-block-info? time u0) ERR_INVALID_PARAMS))
            (current-height current-time) ;; Use timestamp as block reference
            (signature-key {petition-id: petition-id, signer: signer})
        )
        ;; Validate inputs
        (asserts! (is-eq (len signature) SIGNATURE_LENGTH) ERR_INVALID_SIGNATURE)
        (asserts! (> petition-id u0) ERR_INVALID_PARAMS)
        
        ;; Check if already signed
        (asserts! (is-none (map-get? signatures signature-key)) ERR_ALREADY_SIGNED)
        
        ;; Verify petition exists and is active (would call petition contract)
        (asserts! (is-petition-valid petition-id) ERR_PETITION_NOT_FOUND)
        
        ;; Verify signature authenticity
        (let 
            (
                (message-hash (generate-message-hash petition-id signer current-time))
                (is-valid (verify-signature signature message-hash signer))
            )
            
            ;; Store signature record
            (map-set signatures signature-key {
                signature: signature,
                signed-at: current-time,
                verified: is-valid,
                signature-hash: (sha256 signature),
                block-height: current-height
            })
            
            ;; Set verification status
            (map-set signature-verification-status signature-key is-valid)
            
            ;; Store metadata
            (map-set signature-metadata signature-key {
                ip-hash: none,
                user-agent-hash: none,
                timestamp: current-time,
                verification-method: verification-method
            })
            
            ;; Update petition signer list and count if valid
            (if is-valid
                (begin
                    (update-petition-signers petition-id signer)
                    (increment-petition-signature-count petition-id)
                    (var-set total-signatures (+ (var-get total-signatures) u1))
                )
                false
            )
            
            (ok {
                signature-valid: is-valid,
                petition-id: petition-id,
                signer: signer,
                signed-at: current-time,
                total-signatures: (get-petition-signature-count petition-id)
            })
        )
    )
)

;; Verify an existing signature
(define-public (verify-existing-signature (petition-id uint) (signer principal))
    (let 
        (
            (signature-key {petition-id: petition-id, signer: signer})
            (signature-data (unwrap! (map-get? signatures signature-key) ERR_INVALID_SIGNATURE))
        )
        ;; Re-verify the signature
        (let 
            (
                (message-hash (generate-message-hash petition-id signer (get signed-at signature-data)))
                (is-valid (verify-signature (get signature signature-data) message-hash signer))
            )
            ;; Update verification status if changed
            (if (not (is-eq is-valid (get verified signature-data)))
                (begin
                    (map-set signatures signature-key (merge signature-data {
                        verified: is-valid
                    }))
                    (map-set signature-verification-status signature-key is-valid)
                )
                false
            )
            
            (ok {
                petition-id: petition-id,
                signer: signer,
                verified: is-valid,
                original-verification: (get verified signature-data),
                signed-at: (get signed-at signature-data)
            })
        )
    )
)

;; Remove signature (admin only, for fraud cases)
(define-public (remove-signature (petition-id uint) (signer principal) (reason (string-ascii 100)))
    (let 
        (
            (signature-key {petition-id: petition-id, signer: signer})
        )
        ;; Authorization check
        (asserts! (default-to false (map-get? admin-permissions tx-sender)) ERR_UNAUTHORIZED)
        
        ;; Check signature exists
        (asserts! (is-some (map-get? signatures signature-key)) ERR_INVALID_SIGNATURE)
        
        ;; Remove signature records
        (map-delete signatures signature-key)
        (map-delete signature-verification-status signature-key)
        (map-delete signature-metadata signature-key)
        
        ;; Update petition counts
        (decrement-petition-signature-count petition-id)
        
        (ok {
            removed: true,
            petition-id: petition-id,
            signer: signer,
            reason: reason,
            removed-by: tx-sender
        })
    )
)

;; =============================================================================
;; READ-ONLY FUNCTIONS - SIGNATURE QUERIES
;; =============================================================================

;; Get signature details for a specific signer and petition
(define-read-only (get-signature (petition-id uint) (signer principal))
    (map-get? signatures {petition-id: petition-id, signer: signer})
)

;; Check if a principal has signed a petition
(define-read-only (has-signed (petition-id uint) (signer principal))
    (is-some (get-signature petition-id signer))
)

;; Get signature count for a petition
(define-read-only (get-petition-signature-count (petition-id uint))
    (default-to u0 (map-get? petition-signature-counts petition-id))
)

;; Get total signatures across all petitions
(define-read-only (get-total-signatures)
    (var-get total-signatures)
)

;; Get list of signers for a petition
(define-read-only (get-petition-signers (petition-id uint))
    (default-to (list) (map-get? petition-signers petition-id))
)

;; Verify signature validity
(define-read-only (is-signature-valid (petition-id uint) (signer principal))
    (default-to false (map-get? signature-verification-status {petition-id: petition-id, signer: signer}))
)

;; Get signature metadata
(define-read-only (get-signature-metadata (petition-id uint) (signer principal))
    (map-get? signature-metadata {petition-id: petition-id, signer: signer})
)

;; Get signature statistics for a petition
(define-read-only (get-petition-signature-stats (petition-id uint))
    (let 
        (
            (total-sigs (get-petition-signature-count petition-id))
            (signers-list (get-petition-signers petition-id))
        )
        {
            petition-id: petition-id,
            total-signatures: total-sigs,
            unique-signers: (len signers-list),
            signer-list: signers-list
        }
    )
)

;; =============================================================================
;; PRIVATE HELPER FUNCTIONS
;; =============================================================================

;; Generate message hash for signature verification
(define-private (generate-message-hash (petition-id uint) (signer principal) (timestamp uint))
    (let 
        (
            (message-data (concat 
                (concat (unwrap-panic (to-consensus-buff? MESSAGE_PREFIX)) 
                        (unwrap-panic (to-consensus-buff? petition-id)))
                (concat (unwrap-panic (to-consensus-buff? signer))
                        (unwrap-panic (to-consensus-buff? timestamp)))
            ))
        )
        (sha256 message-data)
    )
)

;; Verify digital signature (simplified for demo)
(define-private (verify-signature (signature (buff 65)) (message-hash (buff 32)) (signer principal))
    ;; In a real implementation, this would use proper cryptographic verification
    ;; For demo purposes, we'll verify based on signature length and basic checks
    (let 
        (
            (zero-signature 0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000)
        )
        (and 
            (is-eq (len signature) SIGNATURE_LENGTH)
            (> (len message-hash) u0)
            (not (is-eq signature zero-signature))
        )
    )
)

;; Check if petition is valid (would integrate with petition contract)
(define-private (is-petition-valid (petition-id uint))
    ;; Simplified check - in real implementation would call petition contract
    (> petition-id u0)
)

;; Update petition signers list
(define-private (update-petition-signers (petition-id uint) (signer principal))
    (let 
        (
            (current-signers (default-to (list) (map-get? petition-signers petition-id)))
        )
        (map-set petition-signers petition-id 
            (unwrap! (as-max-len? (append current-signers signer) u1000) false)
        )
    )
)

;; Increment petition signature count
(define-private (increment-petition-signature-count (petition-id uint))
    (let 
        (
            (current-count (default-to u0 (map-get? petition-signature-counts petition-id)))
        )
        (map-set petition-signature-counts petition-id (+ current-count u1))
    )
)

;; Decrement petition signature count
(define-private (decrement-petition-signature-count (petition-id uint))
    (let 
        (
            (current-count (default-to u0 (map-get? petition-signature-counts petition-id)))
        )
        (if (> current-count u0)
            (map-set petition-signature-counts petition-id (- current-count u1))
            false
        )
    )
)
