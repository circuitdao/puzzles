# Circuit Puzzles - Security & Developer Guide

This document is the definitive guide for LLM agents and developers working on the `circuit_puzzles/` codebase. It focuses strictly on Chialisp smart coin architecture, security patterns, and vulnerability prevention.

## Project Context
Circuit Puzzles implements the Circuit Protocol (BYC stablecoin) on the Chia blockchain. The system relies on a complex interaction of singletons (Vaults, Oracle, Statutes, Treasury) and Coin/Asset Tokens (CATs).

**Directory:** `puzzles/circuit_puzzles/`

---

## 1. Core Chialisp Concepts

### The Coinset Model (UTXO)
Unlike account-based blockchains (Ethereum), Chia uses a Coin Set model.
*   **Coins are Immutable:** A coin exists with a specific `(parent_id, puzzle_hash, amount)`. It cannot be modified, only "spent" (destroyed) to create new coins.
*   **State is Ephemeral:** State must be passed forward from the spent coin to the newly created coin. In Chialisp, this is typically done by currying "state" values into the puzzle hash of the new coin.
*   **Sandboxed Execution:** A puzzle execution sees *only* its own arguments. It cannot read global state or other coins directly. Coordination happens via **Announcements** and **Messages** asserted in the block.

### Chialisp Type System (Critical for Security)
Chialisp has **no high-level data types** - all values are one of three primitives:
*   **Atom:** A bag of bytes (arbitrary length). Can represent numbers, hashes, strings, etc.
*   **Cons:** A pair `(first . rest)` - the fundamental list building block.
*   **List:** Nested cons cells, terminated by nil `()`.

**Key Security Implications:**
1.  **No Integer Overflow/Underflow:** Unlike fixed-width integers (uint256, int64), Chialisp atoms have **arbitrary precision**. Arithmetic operations on atoms never overflow or wrap around. A value like `2^256 + 1` is perfectly valid and distinct from `1`.
2.  **Negative Numbers:** Represented as atoms with sign bit. No underflow - negative arithmetic produces correct negative atoms.
3.  **Type Confusion is the Real Risk:** The danger is not overflow, but **treating a list as an atom** (or vice versa) in operations like `curry_hashes`, division, or comparisons. This causes CLVM errors or undefined behavior.

### Argument Naming (Strict Enforcement)
*   **UPPERCASE (Curried):** Fixed at creation. Baked into the puzzle hash. Represents **State** or **Configuration**.
    *   *Examples:* `MOD_HASH`, `STATUTES_STRUCT`, `COLLATERAL`, `OWNER_PUZZLE_HASH`.
*   **lowercase (Solution):** Provided by the spender. **Untrusted**. Represents **User Input**.
    *   *Examples:* `amount`, `new_price`, `operation`, `lineage_proof`.

### Standard Library Includes
Always use the provided includes for security primitives:
```clojure
(include condition_codes.clib)     ; Standard opcodes (CREATE_COIN, etc.)
(include condition_filtering.clib) ; Anti-spoofing filters
(include statutes_utils.clib)      ; Protocol parameter validation
(include utils.clib)               ; Math, hashing, and list helpers
```

---

## 2. Smart Coin Architecture Patterns

### A. The Singleton Pattern
A "Singleton" is a coin that maintains a persistent identity across spends.
*   **Identity:** Defined by its `launcher_id` (the ID of the coin that launched it).
*   **Lineage Proof:** To spend a singleton, you must prove it descends from the `launcher_id`.
*   **Puzzle Structure:** Typically `(singleton_top_layer (INNER_PUZZLE ...))`. The inner puzzle handles the logic, while the top layer enforces the singleton invariant (only one child coin created).

### B. The State Machine Pattern
Puzzles implement state machines where:
1.  **Current State:** Encoded in curried arguments (`COLLATERAL`, `DEBT`).
2.  **Transition:** A spend with a specific `operation` (e.g., "borrow").
3.  **Next State:** `CREATE_COIN` with updated curried arguments.

```clojure
; Conceptual State Machine Spend
(mod (STATE solution)
  (assign
    new_state (update_logic STATE solution)
    (list CREATE_COIN
      (curry_hashes MOD_HASH (sha256 ONE new_state)) ; Recreate self with new state
      amount
    )
  )
)
```

### C. The Dispatcher Pattern
To keep puzzles within size limits, use a dispatcher.
*   The main puzzle validates the operation and permissions.
*   It delegates logic to separate "programs" (e.g., `programs/vault_borrow.clsp`).
*   **Security:** Always whitelist allowed operation hashes.

---

## 3. Security Best Practices & Vulnerability Prevention

### A. Strict Input Validation (Bounds & Types)
**Rule:** Validate **ALL** solution arguments. Never assume inputs are safe.

1.  **Type Safety (Atoms vs Lists):**
    *   Arithmetic operators (e.g., `>`) implicitly check for atoms.
    *   **Critical:** If an input is used *only* inside a conditional branch, you must explicit check it is an atom to prevent state corruption.
    ```clojure
    ; BAD: Logic error if max_delta is 0, input could be a list
    (if (= max_delta 0) ONE (> input max_delta))

    ; GOOD: Explicit check
    (assert (not (l input)) ...)
    ```

2.  **Minimum AND Maximum Bounds:**
    *   Checking `(> value 0)` is rarely enough for governance or configuration.
    *   **Vulnerability:** Uncapped time delays (e.g., `veto_period`) can lock the protocol permanently.
    ```clojure
    ; BAD:
    (> new_veto_interval 0)

    ; GOOD:
    (assert
      (> new_veto_interval 0)
      (> 31536000 new_veto_interval) ; Max 1 year cap
    )
    ```

### B. Denial-of-Service (DoS) Prevention
**Rule:** Assume attackers will try to exhaust block cost or storage limits.

1.  **Infinite List Growth (Storage DoS):**
    *   **Vulnerability:** Lists that grow with user activity (e.g., Oracle `PRICE_INFOS`) must have a hard length cap. Pruning based on "age" is insufficient if an attacker can spam "fresh" data.
    *   **Fix:** Implement a circular buffer or force-prune the oldest entry when `(list-length ...)` exceeds a limit (e.g., 50).

2.  **Recursive Compute Exhaustion (CPU DoS):**
    *   **Vulnerability:** Iterating over a user-provided list (e.g., settling an auction with `treasury_coins`) allows griefing if the list is too long.
    *   **Fix:** Assert an upper bound on the length of input lists before processing.
    ```clojure
    (assert (< (list-length input_list 0) 20) (process-list input_list ...))
    ```

3.  **Puzzle Reveal Size (Generator DoS):**
    *   **Vulnerability:** Storing massive atoms (e.g., a 10KB number) in state can make the coin unspendable due to generator byte limits.
    *   **Fix:** Enforce reasonable value caps (e.g., 64-bit integers) on stored data.

### C. Spoofing & Identity
**Rule:** Verify *who* is saying something, not just *what* is being said.

1.  **Protocol Prefix Protection:**
    *   Users can spoof protocol messages if allowed to emit conditions starting with the protocol prefix (`C` for Circuit).
    *   **Fix:** Use `(fail-on-protocol-condition inner_conditions)` or `(filter-and-extract-remark-solution ...)` from `condition_filtering.clib`.

2.  **Announcement Origins:**
    *   **Vulnerability:** `ASSERT_PUZZLE_ANNOUNCEMENT` checks *what* puzzle hash created an announcement, but not *which specific coin*.
    *   **Risk:** An attacker can create a ephemeral coin with the Oracle's puzzle hash and emit a fake price announcement.
    *   **Fix:**
        *   **Preferred:** Use `ASSERT_MY_PARENT_ID` or verify lineage if possible.
        *   **Alternative:** The announcer should include its own Coin ID (or Parent ID) in the message: `(sha256tree (c MY_COIN_ID message))`.

### D. Time Bracketing
**Rule:** Prevent timestamp manipulation.
*   Transactions must assert a valid time window relative to the block time.
```clojure
(list ASSERT_SECONDS_ABSOLUTE (- current_timestamp MAX_TX_BLOCK_TIME))
(list ASSERT_BEFORE_SECONDS_ABSOLUTE (+ current_timestamp MAX_TX_BLOCK_TIME))
```

---

## 4. Common Anti-Patterns

| Anti-Pattern | Why it's dangerous | Correction |
| :--- | :--- | :--- |
| **Trusting `inner_solution`** | Inputs could be anything (negative, lists, etc.). | Always use `assert` to validate type, range, and logic. |
| **Missing Max Caps** | Governance/Config params can be set to infinity, bricking logic. | Assert `(< value REASONABLE_MAX)`. |
| **Unbounded Lists** | Recursion on user input exceeds block cost. | Cap list length or use circular buffers. |
| **Implicit Type Checks** | Logic skipped in `if/else` bypasses checks. | Explicitly use `(not (l var))` if not doing math. |
| **Weak Announcements** | `ASSERT_PUZZLE_ANN...` is spoofable by same-hash coins. | Bind announcements to Coin ID or unique nonce. |
| **Bricked Coin (Bad Hash)** | `CREATE_COIN` with wrong hash destroys funds. | Test hash computation with `curry_hashes` rigorously. |

---

## 5. Quick Reference

### Condition Codes
| Code | Name | Usage |
| :--- | :--- | :--- |
| 51 | `CREATE_COIN` | `(list 51 puzzle_hash amount memos)` |
| 60 | `CREATE_COIN_ANNOUNCEMENT` | `(list 60 message)` (Binds to Coin ID) |
| 62 | `CREATE_PUZZLE_ANNOUNCEMENT` | `(list 62 message)` (Binds to Puzzle Hash) |
| 71 | `ASSERT_MY_PARENT_ID` | Critical for lineage / unique identity. |
| 66 | `SEND_MESSAGE` | `(list 66 mode msg ...)` - Sends ephemeral message. |
| 67 | `RECEIVE_MESSAGE` | `(list 67 mode msg ...)` - Asserts receipt of message. |

### Message Modes & Identity Binding
The `mode` parameter (e.g., `0x3f`, `0x12`) in `SEND/RECEIVE_MESSAGE` determines the identity requirements for the counterparty coin.

| Mode (Hex) | Bits | Requirement | Usage Pattern |
| :--- | :--- | :--- | :--- |
| **0x3f** | `111 111` | **Strict Coin ID** | Used for exact 1:1 binding. Requires `(msg coin_id)` in varargs. Ensures message is consumed by *specific* coin instance. |
| **0x12** | `010 010` | **Puzzle Hash** | Used for "Any instance of Logic X". Requires `(msg puzzle_hash)` in varargs. Allows interaction with *any* coin running specific code (e.g., Announcer -> Registry). |

**Security Implication:** `SEND_MESSAGE` with strict modes (like `0x3f` for Coin ID) **mandates** that the recipient coin exists and is spent in the same block to consume the message. This prevents "ghost coin" attacks where funds are sent to non-existent addresses.

### Helper Functions (`utils.clib` / `statutes_utils.clib`)
*   `assert-statute`: Verifies a value matches the global `STATUTES` singleton.
*   `sha256tree`: Hashes a list structure (Merkle tree).
*   `curry_hashes`: Computes puzzle hash with new curried arguments. Use `(sha256 ONE atom)` for numbers and `(sha256tree list)` for lists.

---

## 6. Testing & Auditing Checklist

1.  [ ] **Input Integrity:** Are all lowercase args validated for Type (atom) and Range (min/max)?
2.  [ ] **Cost Safety:** Are all lists capped? Is recursion bounded?
3.  [ ] **Spoofing:** Are protocol prefixes blocked? Are announcements bound to specific identities?
4.  [ ] **Lineage:** Does the coin verify its parent (`ASSERT_MY_PARENT_ID`)?
5.  [ ] **Statutes:** Are all protocol parameters verified against the `STATUTES` singleton?
6.  [ ] **Bricking:** Do `CREATE_COIN` calls use `curry_hashes` with the exact structure of the puzzle?
7.  [ ] **State Corruption:** Are all values that get curried into next coin state validated (non-negative, non-zero for divisors, proper types)?

---

## 7. Critical Coin Bricking Vulnerabilities (Audit Findings)

This section documents specific vulnerabilities where **solution arguments get curried into the next puzzle spend** in ways that make coins permanently unspendable. These represent the most severe class of bugs in the Chia UTXO model.

### A. Type Corruption Vulnerabilities

#### **1. List `target_puzzle_hash` in Auction Bids (CRITICAL)**
- **Files:** `recharge_bid.clsp`, `surplus_bid.clsp`
- **Audit Reference:** Cantina 3.1.3 - Fixed
- **Attack:** Provide `target_puzzle_hash = (list 1 2 3)` instead of 32-byte hash.
- **Impact:** Auction permanently locked.
- **Fix:** Add `(assert (not (l target_puzzle_hash)) (= (strlen target_puzzle_hash) 32) ...)`

### B. Arithmetic Corruption Vulnerabilities

#### **2. Negative `new_principal` in Vault Repayment (HIGH)**
- **File:** `vault_repay.clsp`
- **Audit Reference:** Cantina 3.2.1 - Fixed
- **Attack:** Repay with `sf_transfer_amount = 0`, `repay_amount = PRINCIPAL + accrued_fees`.
- **Impact:** Vault becomes unrepayable or unborrowable.
- **Fix:** `(assert (> new_principal MINUS_ONE) ...)`

#### **3. Negative `auction_price` in Liquidation (MEDIUM - Known Issue)**
- **File:** `vault_keeper_bid.clsp`
- **Mechanism:** If governance sets `min_price` to 0 and `step_price_decrease` is high, `auction_price` can become negative or zero.
- **Impact:** Auction bricks (division by zero or negative coin creation) until `auction_ttl` expires. It is NOT permanent; auction can be restarted after timeout.
- **Mitigation:** Governance must ensure `min_price > 0`. Code could enforce `(max 1 price)`.

### C. Division by Zero Vulnerabilities

#### **4. Zero `cumulative_interest_df` in Savings Vault (CRITICAL)**
- **File:** `savings_vault.clsp`
- **Mechanism:** `cumulative_interest_df` used as divisor.
- **Attack Scenario:** Governance misconfiguration or calculation underflow.
- **Fix:** `(assert (> cumulative_interest_df 0) ...)`

---

## 8. State Corruption Attack Patterns

**Pattern Recognition for Security Review:**

🔴 **High Risk Pattern:** Solution arg → arithmetic → curried without validation
```clojure
; VULNERABLE:
new_value (- USER_INPUT some_value)  ; Could be negative
(CREATE_COIN (curry ... (sha256 ONE new_value)) ...)  ; Bricks coin
```

🟢 **Safe Pattern:** Solution arg → validation → arithmetic → curried
```clojure
; SAFE:
(assert (> USER_INPUT some_value) ...)  ; Validate first
new_value (- USER_INPUT some_value)
(CREATE_COIN (curry ... (sha256 ONE new_value)) ...)
```

---

## 9. Security Researcher Guidance & False Positives

### A. Treasury Identity "Deadlock" (FALSE POSITIVE)
*   **Initial Concern:** The Treasury requires the "Approver" logic to run as its `inner_puzzle` to validate messages, but Keeper puzzles assert they are Vaults (`ASSERT_MY_PUZZLEHASH`).
*   **Resolution:** The Treasury **does not** execute the Approver logic itself. It passively verifies a `RECEIVE_MESSAGE` from the Approver coin. The `inner_puzzle` passed to Treasury during a Keeper operation is just a dummy/wrapper, not the actual protocol logic.

### B. Surplus Auction "Ghost Coin" Settlement (FALSE POSITIVE)
*   **Initial Concern:** `surplus_settle.clsp` sends funds to a `payout_coin_id` derived from user input. An attacker could send funds to a fake/ghost coin ID, burning the Auction Coin without unlocking the Payout Coin.
*   **Resolution:** Chialisp consensus rules for `SEND_MESSAGE` (Opcode 66) **require the recipient coin to exist and be spent in the same block**. If the attacker directs the message to a ghost coin, the transaction fails because the ghost coin cannot be spent.

### C. Announcer Registry Flooding (FALSE POSITIVE)
*   **Initial Concern:** An approved announcer could register multiple times, bloating the registry until `MINT` (which iterates the list) exceeds block cost limits.
*   **Resolution:**
    1.  `MINT` operation clears the registry `()`, so it resets every epoch.
    2.  `announcer_register.clsp` enforces `(> registry_claim_counter CLAIM_COUNTER)` and updates the Announcer's internal state. This prevents the same singleton from registering more than once per epoch.

### D. Infinite CRT Minting via Fake Recharge Auction (FALSE POSITIVE)
*   **Initial Concern:** An attacker launches their own Singleton using the `RECHARGE_AUCTION_MOD` to bypass `recharge_start_auction` and calls `recharge_settle` to mint CRT. `crt_tail` authorizes based on Mod Hash.
*   **Resolution:** Lineage enforcement prevents this.
    1.  **Lineage:** `recharge_auction` logic enforces that every spend descends from a parent of the same type, tracing back to the Eve spend.
    2.  **Eve Spend:** The Eve spend (`recharge_launch.clsp`) requires explicit authorization (`RECEIVE_MESSAGE`) from the `STATUTES` singleton (Governance).
    3.  **Result:** An attacker cannot bootstrap a fake singleton into a valid "Recharge Auction" state because they cannot execute the unauthorized Eve spend, and they cannot skip it due to lineage checks.

---

## 10. Economic & Logic Risks (Low/Medium)

### A. Liquidation Auction "Negative Price" DoS
**Risk:** If `min_price` is 0 and `step_price_decrease` is large, the `auction_price` calculation can yield a negative result.
**Impact:** Division by zero or negative coin creation causes the auction to crash ("brick") until `auction_ttl` expires.
**Mitigation:** Governance should ensure `STATUTE_VAULT_AUCTION_MINIMUM_PRICE_FACTOR_BPS > 0`.

### B. Announcer Reward Dilution
**Risk:** While an announcer cannot flood the list, they *can* use `announcer_configure` to change their Inner Puzzle Hash. Does this allow re-registration?
**Analysis:** No, `announcer_configure` preserves the `CLAIM_COUNTER`. The registration constraint travels with the Singleton instance, not the inner puzzle identity.

---

## 11. Audit History & Fixes

**Cantina Competition Audit (August 2025):** 38 issues.
**Key Fixes Verified:**
*   **Treasury Drainage:** Uniqueness check added to `treasury_coins` list.
*   **Recharge Settle:** `crt_tail_hash` now derived from statutes, not user input.
*   **Announcer Lineage:** Exit paths tightened to preventing spoofing "Approved" status.
*   **Bid Hijacking:** Bids now bound to `OFFER_MOD_HASH` to prevent RBF theft.
