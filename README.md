# X-crow.clar – Freelance Escrow Smart Contract

**X-crow.clar** is a Clarity smart contract for secure freelance escrow transactions on the Stacks blockchain. It supports milestone payments, dispute resolution, multi-signature approvals, rate limiting, and platform fees.

---

## Features

- **Escrow Roles:**  
  - `client`, `freelancer`, and optional `arbiter` for dispute resolution.
- **Deposit & Approval:**  
  - Client deposits STX, sets freelancer, and both parties must approve before funds are released.
- **Milestones:**  
  - Supports up to 1000 milestones, each with amount, description, deadline, and approval flags.
- **Dispute Resolution:**  
  - Either party can raise a dispute; arbiter resolves by selecting a winner.
- **Multi-signature Support:**  
  - Client can add/remove signers; signers can approve release.
- **Rate Limiting & Reentrancy Protection:**  
  - Prevents spam and reentrancy attacks using block height checks and contract lock.
- **Platform Fee:**  
  - 2.5% fee deducted from payments and sent to contract owner.
- **Emergency Controls:**  
  - Contract owner can pause/unpause contract operations.

---

## Usage

### 1. Deposit

Client deposits funds and sets freelancer:

````clarity
(deposit freelancer-addr deposit-amount)
````

### 2. Set Arbiter

Client sets an arbiter for dispute resolution:

````clarity
(set-arbiter arbiter-addr)
````

### 3. Approvals

Client and freelancer approve release of funds:

````clarity
(client-approve)
(freelancer-approve)
````

### 4. Withdraw

Release funds to freelancer (after both approvals):

````clarity
(withdraw)
````

### 5. Refund

Client can refund if freelancer hasn’t approved and timeout has passed:

````clarity
(refund)
````

### 6. Milestones

Add and complete milestones:

````clarity
(add-milestone milestone-id milestone-amount description deadline)
(complete-milestone milestone-id)
````

### 7. Dispute Resolution

Raise and resolve disputes:

````clarity
(raise-dispute)
(resolve-dispute winner)
````

### 8. Multi-signature

Add/remove signers and sign approval:

````clarity
(add-signer signer)
(remove-signer signer)
(sign-approval)
````

### 9. Emergency Controls

Pause/unpause contract (owner only):

````clarity
(emergency-pause)
(emergency-unpause)
````

---

## Read-only Functions

- `escrow-status` – Returns current contract state.
- `get-detailed-status` – Returns contract state and metrics.
- `get-milestone milestone-id` – Returns milestone details.

---

## Security

- **Input Validation:**  
  - Checks for valid principals, amounts, deadlines, and roles.
- **Rate Limiting:**  
  - Minimum blocks between actions per address.
- **Reentrancy Protection:**  
  - Contract lock prevents concurrent actions.
- **Emergency Pause:**  
  - Owner can pause contract in emergencies.

---

## Error Codes

Contract uses detailed error codes for all failure scenarios (e.g., unauthorized actions, invalid inputs, rate limiting, etc.).

---

## License

MIT License (see repository for details).

---

## Author

Donatus David

---

**Note:**  
This contract is for educational and demonstration purposes. Review and audit before deploying in production.
