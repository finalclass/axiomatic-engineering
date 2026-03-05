# Design Standard (Appendix C) -- System Design & Service Contract Parts

A consolidated checklist of all directives and guidelines from the book. A **directive** is a rule you should never violate -- doing so is certain to cause failure. A **guideline** is advice you should follow unless you have a strong and unusual justification for going against it. Violating a single guideline alone is not certain to cause failure, but too many violations will.

## The Prime Directive

**Never design against the requirements.**

## Directives (System Design)

1. Avoid functional decomposition.
2. Decompose based on volatility.
3. Provide a composable design.
4. Offer features as aspects of integration, not implementation.
5. Design iteratively, build incrementally.

## System Design Guidelines

### 1. Requirements

a. Capture required behavior, not required functionality.
b. Describe required behavior with use cases.
c. Document all use cases that contain nested conditions with activity diagrams.
d. Eliminate solutions masquerading as requirements.
e. Validate the system design by ensuring it supports all core use cases.

### 2. Cardinality

a. Avoid more than five Managers in a system without subsystems.
b. Avoid more than a handful of subsystems.
c. Avoid more than three Managers per subsystem.
d. Strive for a golden ratio of Engines to Managers.
e. Allow ResourceAccess components to access more than one Resource if necessary.

### 3. Attributes

a. Volatility should decrease top-down.
b. Reuse should increase top-down.
c. Do not encapsulate changes to the nature of the business.
d. Managers should be almost expendable.
e. Design should be symmetric.
f. Never use public communication channels for internal system interactions.

### 4. Layers

a. Avoid open architecture.
b. Avoid semi-closed/semi-open architecture.
c. Prefer a closed architecture.
   - i. Do not call up.
   - ii. Do not call sideways (except queued calls between Managers).
   - iii. Do not call more than one layer down.
   - iv. Resolve attempts at opening the architecture by using queued calls or asynchronous event publishing.
d. Extend the system by implementing subsystems.

### 5. Interaction Rules

a. All components can call Utilities.
b. Managers and Engines can call ResourceAccess.
c. Managers can call Engines.
d. Managers can queue calls to another Manager.

### 6. Interaction Don'ts

a. Clients do not call multiple Managers in the same use case.
b. Managers do not queue calls to more than one Manager in the same use case.
c. Engines do not receive queued calls.
d. ResourceAccess components do not receive queued calls.
e. Clients do not publish events.
f. Engines do not publish events.
g. ResourceAccess components do not publish events.
h. Resources do not publish events.
i. Engines, ResourceAccess, and Resources do not subscribe to events.

## Service Contract Design Guidelines

1. Design reusable service contracts.
2. Comply with service contract design metrics:
   - a. Avoid contracts with a single operation.
   - b. Strive to have 3 to 5 operations per service contract.
   - c. Avoid service contracts with more than 12 operations.
   - d. Reject service contracts with 20 or more operations.
3. Avoid property-like operations.
4. Limit the number of contracts per service to 1 or 2.
5. Avoid junior hand-offs.
6. Have only the architect or competent senior developers design the contracts.
