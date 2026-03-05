# Service Contract Design (Appendix B)

## Modularity and Cost

Total system cost is the sum of two nonlinear cost elements:

### Cost per Service
- As the number of services decreases, their size increases (toward a monolith)
- Complexity increases nonlinearly with size: a service 2x as big may be 4x more complex; 4x as big may be 20-100x more complex
- Increased complexity induces nonlinear increases in cost
- Result: cost per service is a compounded, nonlinear, monotonically increasing function of size

### Integration Cost
- As the number of services increases, the complexity of possible interactions increases
- With n services, interaction complexity grows in proportion to n^2 or even n^n
- Integration cost is also a nonlinear curve, shooting up with more services

### Area of Minimum Cost
- The total system cost curve (sum of both) has a flat region: the **area of minimum cost**
- Services are not too big, not too small; not too many, not too few
- You do not need the absolute minimum -- just stay in the flat region (diminishing returns beyond that)
- What you MUST avoid: the nonlinear edges (monolith or explosion of services), which are many multiples more expensive
- **Functional decomposition always lands at the expensive edges** -- either a few massive accumulations or an explosion of small services
- Systems designed outside the area of minimum cost have already failed before anyone writes the first line of code -- because the tools organizations have (add another developer, another month) are linear, and the problem is nonlinear

## Services and Contracts

A **contract** is the public interface that the service presents to its clients -- a set of operations that clients can call. Not all interfaces are service contracts; service contracts are formal interfaces the service commits to support, unchanged.

### Contracts as Facets
- A contract represents a facet of the service (like an employment contract is one facet of a person)
- A single service can support more than one contract (multiple facets)
- The first reduction: assume a one-to-one ratio between services and contracts, then the cost curve behavior remains unchanged

### Attributes of Good Contracts

Good contracts are:

1. **Logically consistent** -- no unrelated operations bundled together. Every operation in the contract must logically belong with the others.
2. **Cohesive** -- all the aspects required to describe the interaction, no more, no less. Nothing missing, nothing extra.
3. **Independent** -- each contract (facet) stands alone and operates independently of other contracts.

**The basic element of reuse is the contract, not the service.** Good interfaces are reusable while the underlying services never are (like the tool-hand interface reused from stone axe to computer mouse).

Logically consistent, cohesive, and independent contracts ARE reusable contracts. Reusability is not binary -- it is a spectrum. The more a contract has these three attributes, the more reusable it is.

## Factoring Contracts

Design contracts as if they will be reused countless times across multiple systems including your competitors'. The degree of actual reuse is immaterial -- the obligation to design reusable contracts keeps you in the area of minimum cost.

### Factoring Down (Base Extraction)
- Extract a base contract from a more specific contract
- When a contract has operations that are not universally applicable, factor the general operations into a base contract and keep the specific ones in a derived contract
- Example: `IScannerAccess` has `ScanCode()` and `AdjustBeam()` -- but `AdjustBeam()` is scanner-specific. Factor down to `IReaderAccess` (base with `ReadCode()`) and `IScannerAccess : IReaderAccess` (derived with `AdjustBeam()`)
- This enables non-optical devices (keypads, RFID readers) to implement `IReaderAccess`

### Factoring Sideways (Separating Concerns)
- Separate logically unrelated operations into independent contracts
- When a contract is not logically consistent (grab-bag of unrelated operations), split it
- Example: `IReaderAccess` with `ReadCode()`, `OpenPort()`, `ClosePort()` -- port management is a different concern than code reading. Factor sideways into `IReaderAccess` and `ICommunicationDevice`
- Services implement both contracts; other devices (conveyer belts) can reuse just `ICommunicationDevice`
- Every change in business domain should NOT lead to a reflected change in the design -- that is the hallmark of bad design

### Factoring Up (Contract Hierarchy)
- Create a shared base contract when identical operations appear in multiple unrelated contracts
- Example: all devices need `Abort()` and `RunDiagnostics()` -- factor up to `IDeviceControl` base contract
- Both `IReaderAccess` and `IBeltAccess` derive from `IDeviceControl`

## Contract Design Metrics

Metrics are **evaluation tools, not validation tools**. Complying does not guarantee a good design, but violating implies a bad design.

### Size Metrics (Operations per Contract)

| Operations | Assessment |
|-----------|------------|
| 1 | Red flag -- investigate. A single-operation facet is suspect |
| 2 | Possibly fine, but examine carefully |
| **3-5** | **Optimal range** |
| 6-9 | Acceptable, but starting to drift from area of minimum cost |
| 12+ | Very likely a poor design -- look for ways to factor |
| 20+ | **Immediately reject** -- no possible circumstances where this is benign |

### Avoid Properties
- Do not expose property-like operations (getters/setters) in service contracts
- Properties imply state and implementation details -- when the service changes, the client must change
- Good interactions are always behavioral: `DoSomething()`, `Abort()` -- not `GetName()`, `SetName()`
- Keep data where the data is; only invoke operations on it

### Limit the Number of Contracts per Service
- A service should support no more than 1 or 2 contracts
- If a service supports 3+ independent facets, the service may be too big
- In order of magnitude: 1-4 contracts per service, with PERT estimate of ~2.2
- In practice: most well-designed services have 1 or 2 contracts
- Tip: if your architecture has 8+ Managers, represent some Managers as additional independent facets (contracts) on other Managers to reduce the count

### Using Metrics
- Do NOT try to design to the metrics -- contract design is iterative
- Spend time identifying the reusable contract, keep examining if they are logically consistent, cohesive, and independent
- If you violate the metrics, keep working until you have decent contracts
- Once you have devised good contracts, you will find that they match the metrics naturally

## The Contract Design Challenge

- Designing contracts is an acquired skill requiring practice and mentorship
- The ideas are simple but not simplistic
- The real challenge is not designing the contracts but getting management support for the time investment
- Rushing to implementation with poor contracts will cause the project to fail (nonlinear cost consequences)
- With junior teams: the architect must design the contracts or closely guide the process
- Make contract design part of each service life cycle
