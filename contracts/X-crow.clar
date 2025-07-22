;; Rate Limiting Map
(define-map last-action principal uint)
(define-constant min-blocks-between-actions u10)

(define-data-var client (optional principal) none)
(define-data-var freelancer (optional principal) none)
(define-data-var arbiter (optional principal) none)
(define-data-var amount uint u0)
(define-data-var deposit-made bool false)
(define-data-var client-approved bool false)
(define-data-var freelancer-approved bool false)
(define-data-var deposit-block uint u0)
(define-data-var dispute-raised bool false)
(define-constant timeout u144)

;; Platform Settings
(define-map allowed-signers principal bool)
(define-data-var required-signatures uint u2)
(define-data-var platform-fee uint u25) ;; 2.5%
(define-constant fee-denominator u1000)
(define-data-var contract-locked bool false)
(define-data-var contract-owner principal tx-sender)

;; Enhanced Error Constants
(define-constant err-deposit-already-made u100)
(define-constant err-unauthorized-client u101)
(define-constant err-unauthorized-freelancer u102)
(define-constant err-approval-required u103)
(define-constant err-unauthorized-refund u104)
(define-constant err-freelancer-already-approved u105)
(define-constant err-timeout-not-reached u106)
(define-constant err-invalid-principal u107)
(define-constant err-no-deposit u108)
(define-constant err-unauthorized-signer u110)
(define-constant err-invalid-signer u111)
(define-constant err-self-signing u112)
(define-constant err-milestone-limit u121)
(define-constant err-invalid-amount u122)
(define-constant err-invalid-deadline u123)
(define-constant err-milestone-exists u124)
(define-constant err-description-too-long u125)
(define-constant err-unauthorized-dispute u130)
(define-constant err-unauthorized-arbiter u131)
(define-constant err-no-dispute u132)
(define-constant err-invalid-winner u135)
(define-constant err-contract-locked u140)
(define-constant err-rate-limited u150)
(define-constant err-same-address u160)
(define-constant err-zero-amount u161)
(define-constant err-insufficient-balance u162)

;; Fee Calculation Function
(define-private (calculate-platform-fee (payment uint))
    (/ (* payment (var-get platform-fee)) fee-denominator))

;; Milestone Structure
(define-map milestones uint {
    milestone-amount: uint,
    description: (string-ascii 256),
    completed: bool,
    deadline: uint,
    approved-by-client: bool,
    approved-by-freelancer: bool
})

;; Enhanced Security Functions
(define-private (check-reentrancy)
    (begin
        (asserts! (not (var-get contract-locked)) (err err-contract-locked))
        (var-set contract-locked true)
        (ok true)))

(define-private (unlock-contract)
    (var-set contract-locked false))

(define-private (check-rate-limit)
    (let ((last-block (default-to u0 (map-get? last-action tx-sender))))
        (asserts! (>= (- stacks-block-height last-block) min-blocks-between-actions) 
                 (err err-rate-limited))
        (map-set last-action tx-sender stacks-block-height)
        (ok true)))

;; Input Validation Functions
(define-private (validate-principal (addr principal))
    (and (not (is-eq addr 'ST000000000000000000002AMW42H))
         (not (is-eq addr (as-contract tx-sender)))))

(define-private (validate-amount (amt uint))
    (and (> amt u0) (<= amt u1000000000000))) ;; Max 1M STX

;; Enhanced validation for trusted principals
(define-private (validate-trusted-principal (addr principal) (expected-role (optional principal)))
    (begin
        (asserts! (validate-principal addr) (err err-invalid-principal))
        (asserts! (is-some expected-role) (err err-invalid-principal))
        (asserts! (is-eq (some addr) expected-role) (err err-unauthorized-client))
        (ok addr)))

;; Safe principal extraction with validation
(define-private (get-validated-principal (role (optional principal)))
    (let ((addr (unwrap! role (err err-invalid-principal))))
        (begin
            (asserts! (validate-principal addr) (err err-invalid-principal))
            (ok addr))))

;; Read-only Functions
(define-read-only (Xcrow-status) 
    (ok {
        client: (var-get client),
        freelancer: (var-get freelancer),
        arbiter: (var-get arbiter),
        amount: (var-get amount),
        deposit-made: (var-get deposit-made),
        deposit-block: (var-get deposit-block),
        client-approved: (var-get client-approved),
        freelancer-approved: (var-get freelancer-approved),
        dispute-raised: (var-get dispute-raised)
    }))

(define-read-only (get-detailed-status)
    (let ((status (Xcrow-status)))
        (ok {
            basic-info: (unwrap! status (err u500)),
            contract-metrics: {
                total-locked: (var-get amount),
                platform-fee: (calculate-platform-fee (var-get amount)),
                time-remaining: (if (> (+ (var-get deposit-block) timeout) stacks-block-height)
                                   (- (+ (var-get deposit-block) timeout) stacks-block-height)
                                   u0),
                blocks-since-deposit: (if (> (var-get deposit-block) u0)
                                        (- stacks-block-height (var-get deposit-block))
                                        u0)
            }
        })))

(define-read-only (get-milestone (milestone-id uint))
    (map-get? milestones milestone-id))

;; Enhanced Public Functions
(define-public (deposit (freelancer-addr principal) (deposit-amount uint))
    (begin
        (try! (check-rate-limit))
        (try! (check-reentrancy))
        (asserts! (not (var-get deposit-made)) (err err-deposit-already-made))
        (asserts! (not (is-eq tx-sender freelancer-addr)) (err err-same-address))
        (asserts! (validate-principal freelancer-addr) (err err-invalid-principal))
        (asserts! (validate-amount deposit-amount) (err err-invalid-amount))
        (asserts! (>= (stx-get-balance tx-sender) deposit-amount) (err err-insufficient-balance))
        
        (match (stx-transfer? deposit-amount tx-sender (as-contract tx-sender))
            success (begin
                (var-set client (some tx-sender))
                (var-set freelancer (some freelancer-addr))
                (var-set amount deposit-amount)
                (var-set deposit-made true)
                (var-set deposit-block stacks-block-height)
                (unlock-contract)
                (ok "Deposit made successfully"))
            error (begin
                (unlock-contract)
                (err err-insufficient-balance)))))

(define-public (set-arbiter (arbiter-addr principal))
    (begin
        (try! (check-rate-limit))
        (try! (validate-trusted-principal tx-sender (var-get client)))
        (asserts! (validate-principal arbiter-addr) (err err-invalid-principal))
        (asserts! (not (is-eq arbiter-addr tx-sender)) (err err-same-address))
        (let ((freelancer-addr (try! (get-validated-principal (var-get freelancer)))))
            (asserts! (not (is-eq arbiter-addr freelancer-addr)) (err err-same-address))
            (var-set arbiter (some arbiter-addr))
            (ok "Arbiter set successfully"))))

(define-public (client-approve)
    (begin
        (try! (check-rate-limit))
        (try! (check-reentrancy))
        (try! (validate-trusted-principal tx-sender (var-get client)))
        (asserts! (var-get deposit-made) (err err-no-deposit))
        (asserts! (not (var-get dispute-raised)) (err err-no-dispute))
        (var-set client-approved true)
        (unlock-contract)
        (ok "Client approved release")))

(define-public (freelancer-approve)
    (begin
        (try! (check-rate-limit))
        (try! (check-reentrancy))
        (try! (validate-trusted-principal tx-sender (var-get freelancer)))
        (asserts! (var-get deposit-made) (err err-no-deposit))
        (asserts! (not (var-get dispute-raised)) (err err-no-dispute))
        (var-set freelancer-approved true)
        (unlock-contract)
        (ok "Freelancer approved release")))

(define-public (withdraw)
    (let (
        (client-ok (var-get client-approved))
        (freelancer-ok (var-get freelancer-approved))
        (freelancer-addr (try! (get-validated-principal (var-get freelancer))))
        (amt (var-get amount))
        (platform-fee-amt (calculate-platform-fee amt))
        (net-amount (- amt platform-fee-amt)))
    (begin
        (try! (check-rate-limit))
        (try! (check-reentrancy))
        (asserts! (and client-ok freelancer-ok) (err err-approval-required))
        (asserts! (var-get deposit-made) (err err-no-deposit))
        (asserts! (not (var-get dispute-raised)) (err err-no-dispute))
        
        ;; Transfer net amount to freelancer (already validated)
        (try! (stx-transfer? net-amount (as-contract tx-sender) freelancer-addr))
        
        ;; Transfer platform fee to contract owner (if any)
        (if (> platform-fee-amt u0)
            (try! (stx-transfer? platform-fee-amt (as-contract tx-sender) (var-get contract-owner)))
            true)
        
        ;; Reset state
        (var-set deposit-made false)
        (var-set client-approved false)
        (var-set freelancer-approved false)
        (var-set amount u0)
        (unlock-contract)
        (ok "Payment released to freelancer"))))

(define-public (refund)
    (let (
        (current-block (var-get deposit-block))
        (freelancer-ok (var-get freelancer-approved))
        (amt (var-get amount))
        ;; FIXED: Validate client address immediately after extraction
        (client-addr (try! (get-validated-principal (var-get client)))))
    (begin
        (try! (check-rate-limit))
        (try! (check-reentrancy))
        ;; Validate that tx-sender is the client
        (try! (validate-trusted-principal tx-sender (var-get client)))
        (asserts! (not freelancer-ok) (err err-freelancer-already-approved))
        (asserts! (> (- stacks-block-height current-block) timeout) (err err-timeout-not-reached))
        (asserts! (var-get deposit-made) (err err-no-deposit))
        
        ;; FIXED: client-addr is now validated before use
        (try! (stx-transfer? amt (as-contract tx-sender) client-addr))
        
        (var-set deposit-made false)
        (var-set amount u0)
        (var-set client-approved false)
        (var-set freelancer-approved false)
        (unlock-contract)
        (ok "Refund processed successfully"))))

;; Enhanced Multi-signature Functions
(define-public (add-signer (signer principal))
    (begin
        (try! (check-rate-limit))
        (try! (validate-trusted-principal tx-sender (var-get client)))
        (asserts! (validate-principal signer) (err err-invalid-principal))
        (asserts! (not (is-eq signer tx-sender)) (err err-self-signing))
        (map-set allowed-signers signer true)
        (ok "Signer added successfully")))

(define-public (remove-signer (signer principal))
    (begin
        (try! (check-rate-limit))
        (try! (validate-trusted-principal tx-sender (var-get client)))
        (asserts! (is-some (map-get? allowed-signers signer)) (err err-invalid-signer))
        (map-delete allowed-signers signer)
        (ok "Signer removed successfully")))

(define-public (sign-approval)
    (begin 
        (try! (check-rate-limit))
        (asserts! (default-to false (map-get? allowed-signers tx-sender)) (err err-unauthorized-signer))
        (asserts! (var-get deposit-made) (err err-no-deposit))
        (var-set client-approved true)
        (ok "Approval signed successfully")))

;; Enhanced Milestone Management
(define-public (add-milestone (milestone-id uint) (milestone-amount uint) (description (string-ascii 256)) (deadline uint))
    (begin
        (try! (check-rate-limit))
        (try! (validate-trusted-principal tx-sender (var-get client)))
        (asserts! (< milestone-id u1000) (err err-milestone-limit))
        (asserts! (validate-amount milestone-amount) (err err-invalid-amount))
        (asserts! (> deadline stacks-block-height) (err err-invalid-deadline))
        (asserts! (is-none (map-get? milestones milestone-id)) (err err-milestone-exists))
        (asserts! (<= (len description) u256) (err err-description-too-long))
        
        (map-set milestones milestone-id {
            milestone-amount: milestone-amount,
            description: description,
            completed: false,
            deadline: deadline,
            approved-by-client: false,
            approved-by-freelancer: false
        })
        (ok "Milestone added successfully")))

(define-public (complete-milestone (milestone-id uint))
    (let ((milestone (unwrap! (map-get? milestones milestone-id) (err err-invalid-principal))))
        (begin
            (try! (check-rate-limit))
            (try! (validate-trusted-principal tx-sender (var-get freelancer)))
            (asserts! (not (get completed milestone)) (err err-milestone-exists))
            
            (map-set milestones milestone-id (merge milestone { completed: true }))
            (ok "Milestone marked as completed"))))

;; Enhanced Dispute Resolution
(define-public (raise-dispute)
    (begin
        (try! (check-rate-limit))
        (asserts! (or 
            (is-eq (some tx-sender) (var-get client))
            (is-eq (some tx-sender) (var-get freelancer))) 
            (err err-unauthorized-dispute))
        (asserts! (var-get deposit-made) (err err-no-deposit))
        (asserts! (not (var-get dispute-raised)) (err err-no-dispute))
        (var-set dispute-raised true)
        (ok "Dispute raised successfully")))

(define-public (resolve-dispute (winner principal))
    (let (
        (client-addr (try! (get-validated-principal (var-get client))))
        (freelancer-addr (try! (get-validated-principal (var-get freelancer))))
        (validated-winner (begin
            (asserts! (or (is-eq winner client-addr) (is-eq winner freelancer-addr)) (err err-invalid-winner))
            (asserts! (validate-principal winner) (err err-invalid-principal))
            winner)))
    (begin
        (try! (check-rate-limit))
        (try! (check-reentrancy))
        (try! (validate-trusted-principal tx-sender (var-get arbiter)))
        (asserts! (var-get dispute-raised) (err err-no-dispute))
        
        (try! (stx-transfer? (var-get amount) (as-contract tx-sender) validated-winner))
        (var-set deposit-made false)
        (var-set dispute-raised false)
        (var-set amount u0)
        (var-set client-approved false)
        (var-set freelancer-approved false)
        (unlock-contract)
        (ok "Dispute resolved successfully"))))

;; Emergency Functions (only contract owner)
(define-public (emergency-pause)
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) (err err-unauthorized-client))
        (var-set contract-locked true)
        (ok "Contract paused")))

(define-public (emergency-unpause)
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) (err err-unauthorized-client))
        (var-set contract-locked false)
        (ok "Contract unpaused")))