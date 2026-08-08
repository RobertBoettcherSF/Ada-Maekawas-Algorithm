# Maekawa's Distributed Mutual Exclusion Algorithm in Ada

## Project Overview
This project provides a robust, strongly-typed Ada implementation of Maekawa's algorithm for mutual exclusion in distributed systems. It utilizes an event-driven simulation architecture to model distributed network messaging (Requests, Replies, Releases) between distinct nodes without relying on non-deterministic thread timing, making it highly verifiable.

## Features
- **Grid Quorum Construction**: Dynamically generates optimally intersecting sets $O(\sqrt{N})$ per the specific Wikipedia coterie definitions.
- **Basic Queueing Variant**: Defers competing requests via Timestamp-based priority queues.
- **Deadlock-Free Variant**: Fully implements the complex `INQUIRE`, `FAIL`, and `YIELD` message states to detect and resolve circular waits and priority inversions.
- **Strongly Typed Architecture**: Uses restricted range subtypes (`Valid_Node_Id`), explicit state machines, and priority-enforced event queues.

## Testing (V&V Principles)
Verification and Validation (V&V) ensures that not only does the software match the algorithmic requirements (Verification) but that it functionally serves its intended purpose in critical systems without fatal flaws (Validation).

To adhere to strict V&V standards, the testing suite actively assumes the code is *broken* (pessimistic assumptions) and requires the code's behavior to prove these assumptions false.

### Test Categories
1. **Functional Correctness (Tests 1-5):** Verifies memory initialization, accurate $\sqrt{N}$ quorum sizing, and checks the mandatory intersection property between all coteries. 
2. **Mutual Exclusion Constraints (Tests 6-8):** Validates that no two nodes can ever reach the `Holding` state simultaneously, guaranteeing safety.
3. **Edge Cases & Priorities (Test 9):** Ensures temporal priority inversion is respected (older timestamps receive priority regardless of network arrival latency).
4. **Error Handling & Deadlock Avoidance (Tests 10-13):** Proves that the implementation correctly generates `INQUIRE`, `FAIL`, and `YIELD` network messages to break circular waits, preventing the network from halting.

*Why this matters:* In distributed avionics or embedded coordination (e.g., Ada's primary domain), a failure in mutual exclusion causes data corruption, and a failure in deadlock avoidance causes total system loss. These tests mathematically prove the network reaches a valid state.

## Usage

### Compilation
The project uses the GNAT toolchain and a provided Makefile.
```bash
make all
