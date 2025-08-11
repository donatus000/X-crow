# X-crow: Advanced Freelance Escrow Smart Contract

A secure, feature-rich escrow system for freelance work implemented in Clarity for the Stacks blockchain.

## Features

### Core Functionality
- **Role-based Access Control**
  - Client (project owner)
  - Freelancer (service provider)
  - Arbiter (dispute resolver)
  - Contract Owner (platform administrator)

### Security & Protection
- **Multi-signature Support**
  - Required for large transactions (>1M STX)
  - Configurable signature requirements
  - Time-locked execution delays
- **Rate Limiting**
  - Prevents spam attacks
  - Minimum block intervals between actions
- **Reentrancy Protection**
  - Contract-level locking mechanism
  - Secure state transitions

### Economic Model
- **Dynamic Fee Structure**
  - Volume-based tiers (2.5% - 1%)
  - Reputation-based discounts
  - Customizable fee parameters
- **Milestone Management**
  - Support for up to 1000 milestones
  - Individual amount tracking
  - Deadline enforcement
  - Dual-party approval system

## Usage Examples

### Basic Escrow Flow

```clarity
;; 1. Client deposits funds
(deposit freelancer-principal deposit-amount)

;; 2. Set arbiter (optional)
(set-arbiter arbiter-principal)

;; 3. Both parties approve
(client-approve)
(freelancer-approve)

;; 4. Release funds
(withdraw)
```

### Milestone Management

```clarity
;; Create milestone
(add-milestone 
    milestone-id 
    amount 
    "Milestone description" 
    deadline-block)

;; Mark complete
(complete-milestone milestone-id)
```

### Dispute Resolution

```clarity
;; Raise dispute
(raise-dispute)

;; Resolve (arbiter only)
(resolve-dispute winner-principal)
```

## Contract State Queries

```clarity
;; Get basic status
(Xcrow-status)

;; Get detailed metrics
(get-detailed-status)

;; Check milestone
(get-milestone milestone-id)

;; Get user stats
(get-user-volume user-principal)
(get-user-reputation user-principal)
```

## Security Features

### Rate Limiting
- 10 blocks minimum between actions
- Prevents transaction spam
- Per-address tracking

### Multi-signature Requirements
- Large transactions (>1M STX)
- 24-hour execution delay
- Multiple required signers

### Emergency Controls
```clarity
;; Platform owner only
(emergency-pause)
(emergency-unpause)
```

## Error Handling

Comprehensive error codes for:
- Authentication failures
- Invalid inputs
- State violations
- Rate limiting
- Insufficient funds
- Transaction restrictions

## Development

### Prerequisites
- Clarity CLI
- Stacks blockchain node
- Node.js v14+

### Testing
```bash
clarinet test tests/X-crow_test.ts
```

### Deployment
```bash
clarinet deploy --network mainnet contracts/X-crow.clar
```

## License

MIT License

## Author

Donatus David

---

**Warning**: This contract handles real assets. Audit and thorough testing required before production use.

## Contributing

1. Fork the repository
2. Create feature branch
3. Commit changes
4. Push to branch
5. Create Pull Request

For detailed specifications and integration guides, see Documentation.
