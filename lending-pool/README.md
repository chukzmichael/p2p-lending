# P2P Lending Platform Smart Contract

## Overview
A decentralized peer-to-peer lending platform built on the Stacks blockchain using Clarity smart contracts. This platform enables users to create, fund, and manage collateralized loans with customizable terms.

## Features
- Create loan requests with customizable terms
- Collateral-backed lending
- Flexible interest rates (0-50% APR)
- Automatic loan lifecycle management
- Liquidation mechanism for defaulted loans
- Built-in balance management system
- Comprehensive error handling
- Secure fund transfer mechanisms

## Prerequisites
- Stacks blockchain environment
- Clarity CLI tools
- STX tokens for deployment and testing
- Understanding of Clarity smart contracts

## Contract Architecture

### Data Structures
1. **Lending Pool Loans Map**
   ```clarity
   lending-pool-loans: {
     lending-pool-loan-id: uint,
     loan-borrower-address: principal,
     loan-lender-address: optional principal,
     loan-principal-amount: uint,
     loan-collateral-amount: uint,
     loan-annual-interest-rate: uint,
     loan-duration-blocks: uint,
     loan-start-block-height: optional uint,
     loan-current-status: string-ascii
   }
   ```

2. **Participant Balances Map**
   ```clarity
   participant-stx-balances: principal → uint
   ```

### Core Functions

#### For Borrowers
1. `create-lending-pool-loan`
   - Create new loan requests
   - Parameters: principal amount, collateral amount, interest rate, duration
   - Returns: loan ID

2. `repay-lending-pool-loan`
   - Repay active loans with interest
   - Parameters: loan ID
   - Returns: success/failure

#### For Lenders
1. `fund-lending-pool-loan`
   - Fund open loan requests
   - Parameters: loan ID
   - Returns: success/failure

2. `liquidate-defaulted-loan`
   - Claim collateral from defaulted loans
   - Parameters: loan ID
   - Returns: success/failure

#### Utility Functions
1. `deposit-stx-to-lending-pool`
   - Deposit STX tokens
   - Returns: deposit amount

2. `withdraw-stx-from-lending-pool`
   - Withdraw available STX tokens
   - Parameters: withdrawal amount
   - Returns: success/failure

## Usage

### Creating a Loan Request
```clarity
(contract-call? .p2p-lending-protocol create-lending-pool-loan 
  u1000000 ;; 1000 STX loan amount
  u1500000 ;; 1500 STX collateral
  u10      ;; 10% APR
  u144     ;; 1 day duration (144 blocks)
)
```

### Funding a Loan
```clarity
(contract-call? .p2p-lending-protocol fund-lending-pool-loan u1)
```

### Repaying a Loan
```clarity
(contract-call? .p2p-lending-protocol repay-lending-pool-loan u1)
```

## Error Codes

| Code | Description | Solution |
|------|-------------|----------|
| ERR-UNAUTHORIZED-ACCESS | Caller not authorized | Verify caller permissions |
| ERR-INVALID-LOAN-AMOUNT | Invalid loan amount | Check amount > 0 |
| ERR-INSUFFICIENT-USER-BALANCE | Insufficient funds | Add more funds |
| ERR-LOAN-RECORD-NOT-FOUND | Loan doesn't exist | Verify loan ID |
| ERR-LOAN-ALREADY-FUNDED-ERROR | Loan already funded | Check loan status |
| ERR-LOAN-NOT-FUNDED-ERROR | Loan not funded | Wait for funding |
| ERR-LOAN-IN-DEFAULT-STATE | Loan defaulted | Contact support |
| ERR-INVALID-LOAN-PARAMETERS | Invalid parameters | Check parameters |
| ERR-LOAN-REPAYMENT-NOT-DUE | Repayment not due | Check loan term |

## Security Considerations

1. **Collateral Management**
   - Collateral must exceed or equal loan amount
   - Secure collateral storage
   - Protected withdrawal mechanisms

2. **Access Control**
   - Function-level authorization
   - Status-based restrictions
   - Protected administrative functions

3. **Input Validation**
   - Amount validation
   - Parameter bounds checking
   - Status verification

4. **Rate Limiting**
   - Interest rate caps (50% max)
   - Minimum loan duration
   - Maximum loan amounts

## Contributing
1. Fork the repository
2. Create a feature branch
3. Commit changes
4. Push to branch
5. Create Pull Request