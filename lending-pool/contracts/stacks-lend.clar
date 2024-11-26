;; P2P Lending Platform
;; This contract enables peer-to-peer lending functionality with collateral, interest rates, and loan management

;; Error codes
(define-constant ERR-UNAUTHORIZED-ACCESS u1)
(define-constant ERR-INVALID-LOAN-AMOUNT u2)
(define-constant ERR-INSUFFICIENT-USER-BALANCE u3)
(define-constant ERR-LOAN-RECORD-NOT-FOUND u4)
(define-constant ERR-LOAN-ALREADY-FUNDED-ERROR u5)
(define-constant ERR-LOAN-NOT-FUNDED-ERROR u6)
(define-constant ERR-LOAN-IN-DEFAULT-STATE u7)
(define-constant ERR-INVALID-LOAN-PARAMETERS u8)
(define-constant ERR-LOAN-REPAYMENT-NOT-DUE u9)

;; Data structures
(define-map lending-pool-loans
  { lending-pool-loan-id: uint }
  {
    loan-borrower-address: principal,
    loan-lender-address: (optional principal),
    loan-principal-amount: uint,
    loan-collateral-amount: uint,
    loan-annual-interest-rate: uint,
    loan-duration-blocks: uint,
    loan-start-block-height: (optional uint),
    loan-current-status: (string-ascii 20)
  }
)

(define-map participant-stx-balances principal uint)

(define-data-var lending-pool-loan-counter uint u1)

;; Read-only functions
(define-read-only (get-loan-details (lending-pool-loan-id uint))
  (map-get? lending-pool-loans { lending-pool-loan-id: lending-pool-loan-id })
)

(define-read-only (get-participant-balance (participant-address principal))
  (default-to u0 (map-get? participant-stx-balances participant-address))
)

(define-read-only (calculate-total-repayment-with-interest (lending-pool-loan-id uint))
  (let (
    (loan-record (unwrap! (get-loan-details lending-pool-loan-id) (err ERR-LOAN-RECORD-NOT-FOUND)))
    (loan-principal (get loan-principal-amount loan-record))
    (annual-interest-rate (get loan-annual-interest-rate loan-record))
  )
  (ok (+ loan-principal (/ (* loan-principal annual-interest-rate) u100)))
  )
)

;; Public functions
(define-public (create-lending-pool-loan (requested-principal-amount uint) (offered-collateral-amount uint) (proposed-interest-rate uint) (requested-loan-duration uint))
  (let (
    (new-loan-id (var-get lending-pool-loan-counter))
  )
    ;; Input validation
    (asserts! (> requested-principal-amount u0) (err ERR-INVALID-LOAN-AMOUNT))
    (asserts! (>= offered-collateral-amount requested-principal-amount) (err ERR-INVALID-LOAN-PARAMETERS))
    (asserts! (and (> proposed-interest-rate u0) (<= proposed-interest-rate u50)) (err ERR-INVALID-LOAN-PARAMETERS))
    (asserts! (> requested-loan-duration u0) (err ERR-INVALID-LOAN-PARAMETERS))
    
    ;; Transfer collateral to contract
    (try! (stx-transfer? offered-collateral-amount tx-sender (as-contract tx-sender)))
    
    ;; Create loan record
    (map-set lending-pool-loans
      { lending-pool-loan-id: new-loan-id }
      {
        loan-borrower-address: tx-sender,
        loan-lender-address: none,
        loan-principal-amount: requested-principal-amount,
        loan-collateral-amount: offered-collateral-amount,
        loan-annual-interest-rate: proposed-interest-rate,
        loan-duration-blocks: requested-loan-duration,
        loan-start-block-height: none,
        loan-current-status: "OPEN"
      }
    )
    
    ;; Increment loan counter
    (var-set lending-pool-loan-counter (+ new-loan-id u1))
    (ok new-loan-id)
  )
)

(define-public (fund-lending-pool-loan (lending-pool-loan-id uint))
  (let (
    (loan-record (unwrap! (get-loan-details lending-pool-loan-id) (err ERR-LOAN-RECORD-NOT-FOUND)))
    (funding-amount (get loan-principal-amount loan-record))
  )
    ;; Validate loan status
    (asserts! (is-eq (get loan-current-status loan-record) "OPEN") (err ERR-LOAN-ALREADY-FUNDED-ERROR))
    
    ;; Transfer funds to borrower
    (try! (stx-transfer? funding-amount tx-sender (get loan-borrower-address loan-record)))
    
    ;; Update loan record
    (map-set lending-pool-loans
      { lending-pool-loan-id: lending-pool-loan-id }
      (merge loan-record {
        loan-lender-address: (some tx-sender),
        loan-start-block-height: (some block-height),
        loan-current-status: "ACTIVE"
      })
    )
    (ok true)
  )
)

(define-public (repay-lending-pool-loan (lending-pool-loan-id uint))
  (let (
    (loan-record (unwrap! (get-loan-details lending-pool-loan-id) (err ERR-LOAN-RECORD-NOT-FOUND)))
    (total-repayment-amount (unwrap! (calculate-total-repayment-with-interest lending-pool-loan-id) (err ERR-INVALID-LOAN-AMOUNT)))
  )
    ;; Validate loan status
    (asserts! (is-eq (get loan-current-status loan-record) "ACTIVE") (err ERR-LOAN-NOT-FUNDED-ERROR))
    (asserts! (is-eq tx-sender (get loan-borrower-address loan-record)) (err ERR-UNAUTHORIZED-ACCESS))
    
    ;; Transfer repayment to lender
    (try! (stx-transfer? total-repayment-amount tx-sender (unwrap! (get loan-lender-address loan-record) (err ERR-LOAN-NOT-FUNDED-ERROR))))
    
    ;; Return collateral to borrower
    (try! (as-contract (stx-transfer? (get loan-collateral-amount loan-record) tx-sender (get loan-borrower-address loan-record))))
    
    ;; Update loan status
    (map-set lending-pool-loans
      { lending-pool-loan-id: lending-pool-loan-id }
      (merge loan-record { loan-current-status: "REPAID" })
    )
    (ok true)
  )
)

(define-public (liquidate-defaulted-loan (lending-pool-loan-id uint))
  (let (
    (loan-record (unwrap! (get-loan-details lending-pool-loan-id) (err ERR-LOAN-RECORD-NOT-FOUND)))
    (loan-start-height (unwrap! (get loan-start-block-height loan-record) (err ERR-LOAN-NOT-FUNDED-ERROR)))
    (loan-maturity-height (+ loan-start-height (get loan-duration-blocks loan-record)))
  )
    ;; Validate loan status and conditions
    (asserts! (is-eq (get loan-current-status loan-record) "ACTIVE") (err ERR-LOAN-NOT-FUNDED-ERROR))
    (asserts! (>= block-height loan-maturity-height) (err ERR-LOAN-REPAYMENT-NOT-DUE))
    (asserts! (is-eq tx-sender (unwrap! (get loan-lender-address loan-record) (err ERR-UNAUTHORIZED-ACCESS))) (err ERR-UNAUTHORIZED-ACCESS))
    
    ;; Transfer collateral to lender
    (try! (as-contract (stx-transfer? (get loan-collateral-amount loan-record) tx-sender (unwrap! (get loan-lender-address loan-record) (err ERR-LOAN-NOT-FUNDED-ERROR)))))
    
    ;; Update loan status
    (map-set lending-pool-loans
      { lending-pool-loan-id: lending-pool-loan-id }
      (merge loan-record { loan-current-status: "DEFAULTED" })
    )
    (ok true)
  )
)

;; Utility functions
(define-public (deposit-stx-to-lending-pool)
  (let (
    (current-participant-balance (get-participant-balance tx-sender))
    (deposit-stx-amount (stx-get-balance tx-sender))
  )
    (map-set participant-stx-balances tx-sender (+ current-participant-balance deposit-stx-amount))
    (ok deposit-stx-amount)
  )
)

(define-public (withdraw-stx-from-lending-pool (withdrawal-amount uint))
  (let (
    (current-participant-balance (get-participant-balance tx-sender))
  )
    (asserts! (<= withdrawal-amount current-participant-balance) (err ERR-INSUFFICIENT-USER-BALANCE))
    
    (try! (as-contract (stx-transfer? withdrawal-amount tx-sender tx-sender)))
    (map-set participant-stx-balances tx-sender (- current-participant-balance withdrawal-amount))
    (ok true)
  )
)