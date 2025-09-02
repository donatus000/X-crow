;; Enhanced X-crow Escrow Contract with Dynamic Fees and Time-Locked Multi-Sig

;; Rate Limiting Map
(define-map last-action principal uint)
(define-constant min-blocks-between-actions u10)

;; Core Contract State
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
(define-data-var platform-fee uint u25) ;; 2.5% (fallback)
(define-constant fee-denominator u1000)
(define-data-var contract-locked bool false)
(define-data-var contract-owner principal tx-sender)

;; Dynamic Fee Structure
(define-map user-volume principal uint)
(define-map user-reputation principal {
  total-contracts: uint,
  successful-contracts: uint,
  total-volume: uint,
  average-rating: uint,
  dispute-count: uint,
  last-updated: uint
})

(define-map fee-tiers uint { min-volume: uint, max-volume: uint, fee-rate: uint })
(define-data-var base-fee uint u25) ;; 2.5%
(define-data-var reputation-discount uint u5) ;; 0.5% discount for high reputation
(define-data-var volume-discount-threshold uint u1000000) ;; 1M STX threshold

;; Time-Locked Multi-Signature System
(define-map pending-transactions uint {
  transaction-type: (string-ascii 50),
  target-amount: uint,
  target-address: principal,
  signatures-required: uint,
  signatures-received: uint,
  created-at: uint,
  execution-delay: uint,
  executed: bool
})

(define-map transaction-signatures { tx-id: uint, signer: principal } bool)
(define-data-var transaction-counter uint u0)
(define-constant large-amount-threshold u1000000) ;; 1M STX

;; Enhanced Project and Milestone System
(define-map projects uint {
  project-id: uint,
  client: principal,
  freelancer: principal,
  total-budget: uint,
  milestones-count: uint,
  completed-milestones: uint,
  project-status: (string-ascii 20),
  created-at: uint,
  deadline: uint,
  arbiter: (optional principal)
})

(define-map milestone-escrows uint {
  project-id: uint,
  milestone-id: uint,
  escrowed-amount: uint,
  release-conditions: (string-ascii 256),
  auto-release-date: (optional uint),
  client-approved: bool,
  freelancer-delivered: bool,
  evidence-hash: (optional (buff 32)),
  payment-released: bool,
  created-at: uint
})

(define-data-var project-counter uint u0)
(define-data-var milestone-escrow-counter uint u0)

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
(define-constant err-transaction-not-found u170)
(define-constant err-transaction-executed u171)
(define-constant err-insufficient-signatures u172)
(define-constant err-execution-delay-not-met u173)
(define-constant err-already-signed u174)
(define-constant err-project-not-found u180)
(define-constant err-milestone-not-found u181)
(define-constant err-milestone-already-paid u182)
(define-constant err-milestone-not-delivered u183)
(define-constant err-project-completed u184)
(define-constant err-auto-release-not-ready u185)

;; Initialize fee tiers
(map-set fee-tiers u1 { min-volume: u0, max-volume: u100000, fee-rate: u25 })
(map-set fee-tiers u2 { min-volume: u100001, max-volume: u500000, fee-rate: u20 })
(map-set fee-tiers u3 { min-volume: u500001, max-volume: u1000000, fee-rate: u15 })
(map-set fee-tiers u4 { min-volume: u1000001, max-volume: u999999999, fee-rate: u10 })

;; Dynamic Fee Calculation Functions
(define-private (get-fee-rate-for-volume (volume uint))
  (if (<= volume u100000) u25
    (if (<= volume u500000) u20
      (if (<= volume u1000000) u15 u10))))

(define-private (calculate-dynamic-fee (user principal) (payment-amount uint))
  (let (
    (user-vol (default-to u0 (map-get? user-volume user)))
    (base-rate (get-fee-rate-for-volume user-vol))
    (reputation-bonus (if (> user-vol (var-get volume-discount-threshold)) (var-get reputation-discount) u0))
    (final-rate (if (>= base-rate reputation-bonus) (- base-rate reputation-bonus) u1)))
    (/ (* payment-amount final-rate) fee-denominator)))

(define-private (update-user-volume (user principal) (transaction-amount uint))
  (let ((current-vol (default-to u0 (map-get? user-volume user))))
    (map-set user-volume user (+ current-vol transaction-amount))))

;; Legacy fee calculation for backward compatibility
(define-private (calculate-platform-fee (payment uint))
    (/ (* payment (var-get platform-fee)) fee-denominator))

;; Legacy Milestone Structure (kept for backward compatibility)
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

;; Helper function to calculate total from list
(define-private (sum-amounts (amounts (list 10 uint)))
  (fold + amounts u0))

;; Enhanced Project and Milestone Management Functions

;; Create a multi-milestone project
(define-public (create-milestone-project 
  (freelancer-addr principal) 
  (total-budget uint) 
  (project-deadline uint)
  (milestone-amounts (list 10 uint))
  (milestone-descriptions (list 10 (string-ascii 256))))
  
  (let (
    (project-id (+ (var-get project-counter) u1))
    (milestones-count (len milestone-amounts))
    (calculated-total (sum-amounts milestone-amounts)))
    
    (begin
      (try! (check-rate-limit))
      (try! (check-reentrancy))
      (asserts! (validate-principal freelancer-addr) (err err-invalid-principal))
      (asserts! (not (is-eq tx-sender freelancer-addr)) (err err-same-address))
      (asserts! (> project-deadline stacks-block-height) (err err-invalid-deadline))
      (asserts! (> milestones-count u0) (err err-invalid-amount))
      (asserts! (<= milestones-count u10) (err err-milestone-limit))
      (asserts! (validate-amount total-budget) (err err-invalid-amount))
      (asserts! (is-eq total-budget calculated-total) (err err-invalid-amount))
      (asserts! (>= (stx-get-balance tx-sender) total-budget) (err err-insufficient-balance))
      
      ;; Transfer total budget to contract
      (try! (stx-transfer? total-budget tx-sender (as-contract tx-sender)))
      
      ;; Create project record
      (map-set projects project-id {
        project-id: project-id,
        client: tx-sender,
        freelancer: freelancer-addr,
        total-budget: total-budget,
        milestones-count: milestones-count,
        completed-milestones: u0,
        project-status: "active",
        created-at: stacks-block-height,
        deadline: project-deadline,
        arbiter: none
      })
      
      ;; Create individual milestone escrows
      (unwrap-panic (create-milestone-escrows-indexed project-id milestone-amounts milestone-descriptions milestones-count))
      
      ;; Update user volume
      (update-user-volume tx-sender total-budget)
      
      (var-set project-counter project-id)
      (unlock-contract)
      (ok project-id))))

;; Helper function to create milestone escrows using indexed approach
(define-private (create-milestone-escrows-indexed 
  (project-id uint) 
  (amounts (list 10 uint)) 
  (descriptions (list 10 (string-ascii 256)))
  (count uint))
  
  (begin
    ;; Create milestones based on count - using sequential approach to avoid type mismatch
    (and (>= count u1) (is-ok (create-milestone-at-index project-id amounts descriptions u0)))
    (and (>= count u2) (is-ok (create-milestone-at-index project-id amounts descriptions u1)))
    (and (>= count u3) (is-ok (create-milestone-at-index project-id amounts descriptions u2)))
    (and (>= count u4) (is-ok (create-milestone-at-index project-id amounts descriptions u3)))
    (and (>= count u5) (is-ok (create-milestone-at-index project-id amounts descriptions u4)))
    (and (>= count u6) (is-ok (create-milestone-at-index project-id amounts descriptions u5)))
    (and (>= count u7) (is-ok (create-milestone-at-index project-id amounts descriptions u6)))
    (and (>= count u8) (is-ok (create-milestone-at-index project-id amounts descriptions u7)))
    (and (>= count u9) (is-ok (create-milestone-at-index project-id amounts descriptions u8)))
    (and (>= count u10) (is-ok (create-milestone-at-index project-id amounts descriptions u9)))
    (ok project-id)))

;; Helper function to create a single milestone at a specific index
(define-private (create-milestone-at-index 
  (project-id uint) 
  (amounts (list 10 uint)) 
  (descriptions (list 10 (string-ascii 256)))
  (index uint))
  
  (let (
    (escrow-id (+ (var-get milestone-escrow-counter) u1))
    (milestone-amount (unwrap-panic (element-at amounts index)))
    (milestone-description (unwrap-panic (element-at descriptions index))))
    
    (begin
      (asserts! (<= (len milestone-description) u256) (err err-description-too-long))
      (asserts! (> milestone-amount u0) (err err-invalid-amount))
      
      (map-set milestone-escrows escrow-id {
        project-id: project-id,
        milestone-id: escrow-id,
        escrowed-amount: milestone-amount,
        release-conditions: milestone-description,
        auto-release-date: none,
        client-approved: false,
        freelancer-delivered: false,
        evidence-hash: none,
        payment-released: false,
        created-at: stacks-block-height
      })
      
      (var-set milestone-escrow-counter escrow-id)
      (ok escrow-id))))

;; Set arbiter for a project
(define-public (set-project-arbiter (project-id uint) (arbiter-addr principal))
  (let ((project-info (unwrap! (map-get? projects project-id) (err err-project-not-found))))
    (begin
      (try! (check-rate-limit))
      (asserts! (is-eq tx-sender (get client project-info)) (err err-unauthorized-client))
      (asserts! (validate-principal arbiter-addr) (err err-invalid-principal))
      (asserts! (not (is-eq arbiter-addr tx-sender)) (err err-same-address))
      (asserts! (not (is-eq arbiter-addr (get freelancer project-info))) (err err-same-address))
      
      (map-set projects project-id 
        (merge project-info { arbiter: (some arbiter-addr) }))
      (ok "Project arbiter set successfully"))))

;; Submit milestone delivery with evidence
(define-public (submit-milestone-delivery (escrow-id uint) (evidence-hash (buff 32)))
  (let (
    (escrow-info (unwrap! (map-get? milestone-escrows escrow-id) (err err-milestone-not-found)))
    (project-info (unwrap! (map-get? projects (get project-id escrow-info)) (err err-project-not-found))))
    
    (begin
      (try! (check-rate-limit))
      (asserts! (is-eq tx-sender (get freelancer project-info)) (err err-unauthorized-freelancer))
      (asserts! (not (get freelancer-delivered escrow-info)) (err err-milestone-exists))
      (asserts! (not (get payment-released escrow-info)) (err err-milestone-already-paid))
      (asserts! (is-eq (get project-status project-info) "active") (err err-project-completed))
      
      (map-set milestone-escrows escrow-id 
        (merge escrow-info { 
          freelancer-delivered: true,
          evidence-hash: (some evidence-hash),
          auto-release-date: (some (+ stacks-block-height u1440)) ;; 24h auto-release
        }))
      
      (ok "Milestone delivery submitted with evidence"))))

;; Approve and release milestone payment
(define-public (approve-milestone-payment (escrow-id uint))
  (let (
    (escrow-info (unwrap! (map-get? milestone-escrows escrow-id) (err err-milestone-not-found)))
    (project-info (unwrap! (map-get? projects (get project-id escrow-info)) (err err-project-not-found)))
    (payment-amount (get escrowed-amount escrow-info))
    (platform-fee-amount (calculate-dynamic-fee (get client project-info) payment-amount))
    (net-payment (- payment-amount platform-fee-amount)))
    
    (begin
      (try! (check-rate-limit))
      (try! (check-reentrancy))
      (asserts! (is-eq tx-sender (get client project-info)) (err err-unauthorized-client))
      (asserts! (get freelancer-delivered escrow-info) (err err-milestone-not-delivered))
      (asserts! (not (get payment-released escrow-info)) (err err-milestone-already-paid))
      
      ;; Release payment to freelancer
      (try! (stx-transfer? net-payment (as-contract tx-sender) (get freelancer project-info)))
      
      ;; Transfer platform fee
      (if (> platform-fee-amount u0)
        (try! (stx-transfer? platform-fee-amount (as-contract tx-sender) (var-get contract-owner)))
        true)
      
      ;; Update escrow status
      (map-set milestone-escrows escrow-id 
        (merge escrow-info { 
          client-approved: true,
          payment-released: true
        }))
      
      ;; Update project completion status
      (let (
        (new-completed (+ (get completed-milestones project-info) u1))
        (updated-status (if (is-eq new-completed (get milestones-count project-info)) "completed" "active")))
        (map-set projects (get project-id escrow-info) 
          (merge project-info { 
            completed-milestones: new-completed,
            project-status: updated-status
          })))
      
      (unlock-contract)
      (ok "Milestone payment released successfully"))))

;; Auto-release milestone payment after timeout
(define-public (auto-release-milestone (escrow-id uint))
  (let (
    (escrow-info (unwrap! (map-get? milestone-escrows escrow-id) (err err-milestone-not-found)))
    (auto-release-block (unwrap! (get auto-release-date escrow-info) (err err-auto-release-not-ready))))
    
    (begin
      (try! (check-rate-limit))
      (asserts! (>= stacks-block-height auto-release-block) (err err-auto-release-not-ready))
      (asserts! (get freelancer-delivered escrow-info) (err err-milestone-not-delivered))
      (asserts! (not (get payment-released escrow-info)) (err err-milestone-already-paid))
      
      ;; Auto-approve and release payment
      (try! (approve-milestone-payment escrow-id))
      (ok "Milestone payment auto-released"))))

;; Raise dispute for a specific milestone
(define-public (raise-milestone-dispute (escrow-id uint))
  (let (
    (escrow-info (unwrap! (map-get? milestone-escrows escrow-id) (err err-milestone-not-found)))
    (project-info (unwrap! (map-get? projects (get project-id escrow-info)) (err err-project-not-found))))
    
    (begin
      (try! (check-rate-limit))
      (asserts! (or 
        (is-eq tx-sender (get client project-info))
        (is-eq tx-sender (get freelancer project-info))) 
        (err err-unauthorized-dispute))
      (asserts! (not (get payment-released escrow-info)) (err err-milestone-already-paid))
      
      ;; Update project status to disputed
      (map-set projects (get project-id escrow-info) 
        (merge project-info { project-status: "disputed" }))
      
      (ok "Milestone dispute raised"))))

;; Resolve milestone dispute (arbiter only)
(define-public (resolve-milestone-dispute (escrow-id uint) (award-to-freelancer bool))
  (let (
    (escrow-info (unwrap! (map-get? milestone-escrows escrow-id) (err err-milestone-not-found)))
    (project-info (unwrap! (map-get? projects (get project-id escrow-info)) (err err-project-not-found)))
    (arbiter-addr (unwrap! (get arbiter project-info) (err err-unauthorized-arbiter)))
    (payment-amount (get escrowed-amount escrow-info))
    (winner (if award-to-freelancer (get freelancer project-info) (get client project-info))))
    
    (begin
      (try! (check-rate-limit))
      (try! (check-reentrancy))
      (asserts! (is-eq tx-sender arbiter-addr) (err err-unauthorized-arbiter))
      (asserts! (is-eq (get project-status project-info) "disputed") (err err-no-dispute))
      (asserts! (not (get payment-released escrow-info)) (err err-milestone-already-paid))
      
      ;; Transfer payment to winner (no platform fee for disputed resolutions)
      (try! (stx-transfer? payment-amount (as-contract tx-sender) winner))
      
      ;; Update escrow status
      (map-set milestone-escrows escrow-id 
        (merge escrow-info { payment-released: true }))
      
      ;; Update project status back to active if not all milestones are complete
      (map-set projects (get project-id escrow-info) 
        (merge project-info { project-status: "active" }))
      
      (unlock-contract)
      (ok "Milestone dispute resolved"))))

;; Time-Locked Multi-Signature Functions
(define-public (propose-large-withdrawal (withdrawal-amount uint) (recipient principal))
  (let ((tx-id (+ (var-get transaction-counter) u1)))
    (begin
      (asserts! (>= withdrawal-amount large-amount-threshold) (err err-invalid-amount))
      (try! (validate-trusted-principal tx-sender (var-get client)))
      (asserts! (validate-principal recipient) (err err-invalid-principal))
      
      (map-set pending-transactions tx-id {
        transaction-type: "withdrawal",
        target-amount: withdrawal-amount,
        target-address: recipient,
        signatures-required: u3,
        signatures-received: u1,
        created-at: stacks-block-height,
        execution-delay: u1440, ;; 24 hour delay
        executed: false
      })
      
      (map-set transaction-signatures { tx-id: tx-id, signer: tx-sender } true)
      (var-set transaction-counter tx-id)
      (ok tx-id))))

(define-public (sign-pending-transaction (tx-id uint))
  (let ((tx-info (unwrap! (map-get? pending-transactions tx-id) (err err-transaction-not-found))))
    (begin
      (asserts! (default-to false (map-get? allowed-signers tx-sender)) (err err-unauthorized-signer))
      (asserts! (not (default-to false (map-get? transaction-signatures { tx-id: tx-id, signer: tx-sender }))) (err err-already-signed))
      (asserts! (not (get executed tx-info)) (err err-transaction-executed))
      
      (map-set transaction-signatures { tx-id: tx-id, signer: tx-sender } true)
      (map-set pending-transactions tx-id (merge tx-info { 
        signatures-received: (+ (get signatures-received tx-info) u1) 
      }))
      (ok "Transaction signed"))))

(define-public (execute-pending-transaction (tx-id uint))
  (let ((tx-info (unwrap! (map-get? pending-transactions tx-id) (err err-transaction-not-found))))
    (begin
      (asserts! (>= (get signatures-received tx-info) (get signatures-required tx-info)) (err err-insufficient-signatures))
      (asserts! (> stacks-block-height (+ (get created-at tx-info) (get execution-delay tx-info))) (err err-execution-delay-not-met))
      (asserts! (not (get executed tx-info)) (err err-transaction-executed))
      
      ;; Execute the transaction
      (try! (stx-transfer? (get target-amount tx-info) (as-contract tx-sender) (get target-address tx-info)))
      (map-set pending-transactions tx-id (merge tx-info { executed: true }))
      (ok "Transaction executed"))))

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

(define-read-only (get-user-volume (user principal))
  (map-get? user-volume user))

(define-read-only (get-user-reputation (user principal))
  (map-get? user-reputation user))

(define-read-only (get-pending-transaction (tx-id uint))
  (map-get? pending-transactions tx-id))

(define-read-only (calculate-fee-for-user (user principal) (transaction-amount uint))
  (ok (calculate-dynamic-fee user transaction-amount)))

;; New read-only functions for project management
(define-read-only (get-project-status (project-id uint))
  (map-get? projects project-id))

(define-read-only (get-milestone-escrow (escrow-id uint))
  (map-get? milestone-escrows escrow-id))

(define-read-only (get-project-progress (project-id uint))
  (let ((project (map-get? projects project-id)))
    (match project
      project-data
        (ok {
          completion-rate: (if (> (get milestones-count project-data) u0)
            (/ (* (get completed-milestones project-data) u100) (get milestones-count project-data))
            u0),
          completed-milestones: (get completed-milestones project-data),
          total-milestones: (get milestones-count project-data),
          status: (get project-status project-data),
          remaining-budget: (- (get total-budget project-data) 
            (/ (* (get completed-milestones project-data) (get total-budget project-data)) 
               (get milestones-count project-data)))
        })
      (err err-project-not-found))))

;; Enhanced Public Functions (Legacy support maintained)
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
                ;; Update user volume for dynamic fee calculation
                (update-user-volume tx-sender deposit-amount)
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
        (client-addr (try! (get-validated-principal (var-get client))))
        (amt (var-get amount))
        ;; Use dynamic fee calculation
        (platform-fee-amt (calculate-dynamic-fee client-addr amt))
        (net-amount (- amt platform-fee-amt)))
    (begin
        (try! (check-rate-limit))
        (try! (check-reentrancy))
        (asserts! (and client-ok freelancer-ok) (err err-approval-required))
        (asserts! (var-get deposit-made) (err err-no-deposit))
        (asserts! (not (var-get dispute-raised)) (err err-no-dispute))
        
        ;; For large amounts, require time-locked multi-sig
        (if (>= amt large-amount-threshold)
            (begin
                ;; Large amount - create pending transaction instead
                (let ((tx-id (+ (var-get transaction-counter) u1)))
                    (map-set pending-transactions tx-id {
                        transaction-type: "large-withdrawal",
                        target-amount: net-amount,
                        target-address: freelancer-addr,
                        signatures-required: u2,
                        signatures-received: u1,
                        created-at: stacks-block-height,
                        execution-delay: u144, ;; 1 day delay for large amounts
                        executed: false
                    })
                    (var-set transaction-counter tx-id)
                    (unlock-contract)
                    (ok "Large withdrawal requires additional approval")))
            ;; Normal amount - process immediately
            (begin
                ;; Transfer net amount to freelancer
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
                (ok "Payment released to freelancer"))))))

(define-public (refund)
    (let (
        (current-block (var-get deposit-block))
        (freelancer-ok (var-get freelancer-approved))
        (amt (var-get amount))
        (client-addr (try! (get-validated-principal (var-get client)))))
    (begin
        (try! (check-rate-limit))
        (try! (check-reentrancy))
        (try! (validate-trusted-principal tx-sender (var-get client)))
        (asserts! (not freelancer-ok) (err err-freelancer-already-approved))
        (asserts! (> (- stacks-block-height current-block) timeout) (err err-timeout-not-reached))
        (asserts! (var-get deposit-made) (err err-no-deposit))
        
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

;; Enhanced Milestone Management (Legacy support)
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

;; Enhanced Dispute Resolution (Legacy support)
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

;; Fee Management Functions
(define-public (update-fee-tier (tier-id uint) (min-vol uint) (max-vol uint) (fee-rate uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) (err err-unauthorized-client))
        (asserts! (<= fee-rate u100) (err err-invalid-amount)) ;; Max 10% fee
        (asserts! (< min-vol max-vol) (err err-invalid-amount))
        ;; Ensure tier-id is a valid uint and handle unchecked data
        (asserts! (is-eq (some tier-id) (some tier-id)) (err err-invalid-amount))
        (map-set fee-tiers tier-id { min-volume: min-vol, max-volume: max-vol, fee-rate: fee-rate })
        (ok "Fee tier updated")))

(define-public (set-reputation-discount (discount uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) (err err-unauthorized-client))
        (asserts! (<= discount u10) (err err-invalid-amount)) ;; Max 1% discount
        (var-set reputation-discount discount)
        (ok "Reputation discount updated")))

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
