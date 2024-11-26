;; P2P Lending Platform
;; This contract enables peer-to-peer lending functionality with variable interest rates,
;; loan refinancing, and partial repayments

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
(define-constant ERR-INSUFFICIENT-COLLATERAL u10)
(define-constant ERR-INVALID-INTEREST-RATE u11)
(define-constant ERR-REFINANCE-NOT-ALLOWED u12)
(define-constant ERR-INVALID-REPAYMENT-AMOUNT u13)
(define-constant ERR-OVERFLOW u14)

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
    loan-current-status: (string-ascii 20),
    loan-repaid-amount: uint
  }
)

(define-map participant-stx-balances principal uint)
(define-map interest-rates (string-ascii 20) uint)

(define-data-var lending-pool-loan-counter uint u1)

;; Initialize interest rates
(map-set interest-rates "LOW" u5)
(map-set interest-rates "MEDIUM" u10)
(map-set interest-rates "HIGH" u15)

;; Read-only functions
(define-read-only (get-loan-details (lending-pool-loan-id uint))
  (map-get? lending-pool-loans { lending-pool-loan-id: lending-pool-loan-id })
)

(define-read-only (get-participant-balance (participant-address principal))
  (default-to u0 (map-get? participant-stx-balances participant-address))
)

(define-read-only (get-interest-rate (rate-type (string-ascii 20)))
  (default-to u0 (map-get? interest-rates rate-type))
)

(define-read-only (calculate-total-repayment-with-interest (lending-pool-loan-id uint))
  (let (
    (loan-record (unwrap! (get-loan-details lending-pool-loan-id) (err ERR-LOAN-RECORD-NOT-FOUND)))
    (loan-principal (get loan-principal-amount loan-record))
    (annual-interest-rate (get loan-annual-interest-rate loan-record))
    (loan-duration (get loan-duration-blocks loan-record))
  )
  (ok (+ loan-principal (/ (* loan-principal annual-interest-rate loan-duration) (* u100 u144 u365))))
  )
)

;; Public functions
(define-public (create-lending-pool-loan (requested-principal-amount uint) (offered-collateral-amount uint) (proposed-interest-rate (string-ascii 20)) (requested-loan-duration uint))
  (let (
    (new-loan-id (var-get lending-pool-loan-counter))
    (interest-rate (unwrap! (map-get? interest-rates proposed-interest-rate) (err ERR-INVALID-INTEREST-RATE)))
  )
    ;; Input validation
    (asserts! (> requested-principal-amount u0) (err ERR-INVALID-LOAN-AMOUNT))
    (asserts! (>= offered-collateral-amount requested-principal-amount) (err ERR-INSUFFICIENT-COLLATERAL))
    (asserts! (> requested-loan-duration u0) (err ERR-INVALID-LOAN-PARAMETERS))
    (asserts! (and (>= interest-rate u1) (<= interest-rate u100)) (err ERR-INVALID-INTEREST-RATE))
    
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
        loan-annual-interest-rate: interest-rate,
        loan-duration-blocks: requested-loan-duration,
        loan-start-block-height: none,
        loan-current-status: "OPEN",
        loan-repaid-amount: u0
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

(define-public (repay-lending-pool-loan (lending-pool-loan-id uint) (repayment-amount uint))
  (let (
    (loan-record (unwrap! (get-loan-details lending-pool-loan-id) (err ERR-LOAN-RECORD-NOT-FOUND)))
    (total-repayment-amount (unwrap! (calculate-total-repayment-with-interest lending-pool-loan-id) (err ERR-INVALID-LOAN-AMOUNT)))
    (current-repaid-amount (get loan-repaid-amount loan-record))
  )
    ;; Validate loan status and repayment amount
    (asserts! (is-eq (get loan-current-status loan-record) "ACTIVE") (err ERR-LOAN-NOT-FUNDED-ERROR))
    (asserts! (is-eq tx-sender (get loan-borrower-address loan-record)) (err ERR-UNAUTHORIZED-ACCESS))
    (asserts! (<= (+ current-repaid-amount repayment-amount) total-repayment-amount) (err ERR-INVALID-REPAYMENT-AMOUNT))
    
    ;; Transfer repayment to lender
    (try! (stx-transfer? repayment-amount tx-sender (unwrap! (get loan-lender-address loan-record) (err ERR-LOAN-NOT-FUNDED-ERROR))))
    
    ;; Update loan record
    (map-set lending-pool-loans
      { lending-pool-loan-id: lending-pool-loan-id }
      (merge loan-record {
        loan-repaid-amount: (+ current-repaid-amount repayment-amount),
        loan-current-status: (if (>= (+ current-repaid-amount repayment-amount) total-repayment-amount) "REPAID" "ACTIVE")
      })
    )
    
    ;; Return collateral if loan is fully repaid
    (if (>= (+ current-repaid-amount repayment-amount) total-repayment-amount)
      (try! (as-contract (stx-transfer? (get loan-collateral-amount loan-record) tx-sender (get loan-borrower-address loan-record))))
      true
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

(define-public (refinance-loan (lending-pool-loan-id uint) (new-interest-rate (string-ascii 20)) (new-duration uint))
  (let (
    (loan-record (unwrap! (get-loan-details lending-pool-loan-id) (err ERR-LOAN-RECORD-NOT-FOUND)))
    (new-rate (unwrap! (map-get? interest-rates new-interest-rate) (err ERR-INVALID-INTEREST-RATE)))
  )
    ;; Validate loan status and conditions
    (asserts! (is-eq (get loan-current-status loan-record) "ACTIVE") (err ERR-LOAN-NOT-FUNDED-ERROR))
    (asserts! (is-eq tx-sender (get loan-borrower-address loan-record)) (err ERR-UNAUTHORIZED-ACCESS))
    (asserts! (< new-rate (get loan-annual-interest-rate loan-record)) (err ERR-REFINANCE-NOT-ALLOWED))
    (asserts! (and (>= new-rate u1) (<= new-rate u100)) (err ERR-INVALID-INTEREST-RATE))
    
    ;; Update loan record
    (map-set lending-pool-loans
      { lending-pool-loan-id: lending-pool-loan-id }
      (merge loan-record {
        loan-annual-interest-rate: new-rate,
        loan-duration-blocks: (+ new-duration (- (get loan-duration-blocks loan-record) (- block-height (unwrap! (get loan-start-block-height loan-record) (err ERR-LOAN-NOT-FUNDED-ERROR)))))
      })
    )
    (ok true)
  )
)

;; Utility functions
(define-public (deposit-stx-to-lending-pool (deposit-amount uint))
  (let (
    (current-participant-balance (get-participant-balance tx-sender))
  )
    (try! (stx-transfer? deposit-amount tx-sender (as-contract tx-sender)))
    ;; Check for potential overflow before updating the balance
    (asserts! (< (+ current-participant-balance deposit-amount) u340282366920938463463374607431768211455) (err ERR-OVERFLOW))
    (ok (map-set participant-stx-balances tx-sender (+ current-participant-balance deposit-amount)))
  )
)

(define-public (withdraw-stx-from-lending-pool (withdrawal-amount uint))
  (let (
    (current-participant-balance (get-participant-balance tx-sender))
  )
    (asserts! (<= withdrawal-amount current-participant-balance) (err ERR-INSUFFICIENT-USER-BALANCE))
    
    (try! (as-contract (stx-transfer? withdrawal-amount tx-sender tx-sender)))
    (ok (map-set participant-stx-balances tx-sender (- current-participant-balance withdrawal-amount)))
  )
)