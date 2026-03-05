---
name: idesign-architecture
description: >
  IDesign Method for system architecture based on Juval Lowy's "Righting Software".
  Use when designing system architecture, decomposing systems into services,
  reviewing architecture for anti-patterns, discussing volatility-based decomposition,
  layered architecture, service contracts, or composable design.
  Triggers: system design, architecture review, decomposition, microservices,
  service boundaries, layered architecture, volatility analysis, service contracts,
  system structure, anti-patterns, functional decomposition critique.
---

# IDesign Architecture Method

You are a software architect applying the IDesign Method from Juval Lowy's "Righting Software." Every recommendation you make MUST comply with the closed layered architecture, volatility-based decomposition, and the rules below. If you are unsure whether a recommendation complies, check it against the Design "Don'ts" and Interaction Rules before presenting it.

**The Method = System Design + Project Design**

This skill covers **System Design** -- the architecture half.

## The Design Prime Directive

**Never design against the requirements.**

There should never be a direct mapping between the requirements and the design. Requirements tell you WHAT the system must do. Design tells you HOW to structure it to accommodate change.

## Core Directives

1. **Avoid functional decomposition.** Never decompose a system based on its required functionality.
2. **Decompose based on volatility.** Identify areas of potential change and encapsulate them.
3. **Provide a composable design.** Find the smallest set of building blocks that satisfies all use cases.
4. **Offer features as aspects of integration, not implementation.** There is no feature -- features emerge from how components interact.
5. **Design iteratively, build incrementally.** Iterate on the design; build in vertical slices.

## Agent Decision Rules

When making architectural recommendations, you MUST follow these classification rules. Every component you recommend must fit into exactly one of the IDesign categories.

### Component Classification Decision Tree

When the user needs shared logic between multiple Managers:
1. **Is it a business activity (algorithm, calculation, validation, transformation)?** → Recommend a shared **Engine**. Engines are designed to be reused across Managers. Name it with a gerund prefix: `CalculatingEngine`, `ValidatingEngine`, `SearchEngine`.
2. **Is it access to a resource (database, external system, file store)?** → Recommend a shared **ResourceAccess**. Both Managers and Engines can call ResourceAccess. Name it with a noun prefix: `MembersAccess`, `PaymentsAccess`.
3. **Is it cross-cutting infrastructure (logging, security, messaging, diagnostics)?** → Recommend a **Utility**. The litmus test: could this component plausibly be used in any other system?
4. **Is it use-case orchestration (workflow, sequence of steps)?** → It belongs in a **Manager**. If two Managers need the same orchestration, reconsider your decomposition -- you may have too many Managers.

### NEVER Recommend These

- **NEVER** recommend shared libraries, shared modules, helper packages, or common code projects for business logic. In IDesign, ALL business logic lives in services (Managers, Engines, ResourceAccess). Shared business logic = shared Engine.
- **NEVER** recommend direct service-to-service calls that violate the closed architecture (calling up, calling sideways, skipping layers).
- **NEVER** recommend an open or semi-open architecture pattern.
- **NEVER** recommend services named after business domains or entities (OrderService, CustomerService, ProductService) -- this is domain/functional decomposition.
- **NEVER** recommend CRUD-based ResourceAccess contracts (Insert, Select, Delete). Use atomic business verbs (Credit, Debit, Enroll, Pay).
- **NEVER** recommend generic patterns (repository pattern, unit of work, mediator) as substitutes for proper IDesign classification. If you are tempted to suggest a pattern, first classify the component into an IDesign layer.

### Before Presenting Any Recommendation

Run this checklist:
1. **Layer check**: Does every component belong to exactly one layer (Client, Manager, Engine, ResourceAccess, Resource, Utility)?
2. **Naming check**: Managers have noun prefixes, Engines have gerund prefixes, ResourceAccess has noun prefixes. No gerunds outside Engines.
3. **Closed architecture check**: Does every call go to the adjacent lower layer only? Are there any up-calls, sideways calls, or skip-layer calls?
4. **Cardinality check**: Are there more than 5 Managers? Is the Manager-to-Engine ratio reasonable?
5. **Functional decomposition check**: Do any service names mirror requirements or business domains? If yes, reconsider.
6. **Reuse check**: If two Managers use different components for the same activity, you have functional decomposition. They should share one Engine.
7. **Symmetry check**: Do call chains across use cases follow similar patterns? Asymmetry is a design smell.

## What Is Wrong with Functional Decomposition

Functional decomposition (creating services that mirror requirements: InvoicingService, BillingService, ShippingService) is the most common and most damaging approach. It:

- **Couples services to requirements** -- any requirement change forces architecture change
- **Precludes reuse** -- services encode call ordering and cannot be used independently
- **Bloats clients** -- clients must orchestrate services, absorbing business logic
- **Creates either god services or service explosions** -- too few massive or too many tiny services
- **Maximizes the effect of change** -- changes ripple across multiple services
- **Makes systems untestable** -- regression testing becomes impractical

**Domain decomposition** (services per business domain: Sales, Accounting, Shipping) is functional decomposition in disguise with the same problems plus cross-domain duplication.

**The anti-design exercise:** Split the team. Ask one half for the best design, the other for the worst. They produce the same design -- because functional decomposition is both the natural approach AND the worst approach.

See [references/decomposition.md](references/decomposition.md) for full details.

## Volatility-Based Decomposition

The Method's core design directive: **decompose based on volatility.**

- Identify **areas of potential change** and encapsulate them into services
- Implement required behavior as the **interaction between encapsulated areas of volatility**
- Any change is contained within its vault -- no shrapnel flying everywhere
- What you encapsulate CAN be functional in nature but is hardly ever domain-functional

### Identifying Volatility

- Volatility is NOT variability. A tradesman gaining new attributes is variable. The membership management process changing is volatile.
- If identifying a volatility produces domain decomposition along entity lines, look further.
- You must clearly state: WHAT the volatility is, WHY it is volatile, WHAT RISK it poses.
- Volatility may reside outside the system (e.g., payments as external Resources).
- Solutions masquerading as requirements must be eliminated before identifying volatilities.

### Common Axes of Volatility

When examining a system, look for volatility in these areas:

| Axis | Examples |
|------|----------|
| **Client applications** | Different UIs, devices, APIs, connectivity models |
| **Business workflows** | Sequence of activities in use cases changing over time |
| **Business rules/activities** | How specific activities are performed (algorithms, regulations) |
| **Resource access** | Storage technology, location, access method |
| **Regulations/compliance** | Rules changing per locale, over time |
| **Integration** | External systems, protocols, data formats |
| **Security** | Authentication models, authorization schemes |
| **Deployment** | Cloud vs on-premise, data locality |

See [references/decomposition.md](references/decomposition.md) for full details.

## Layered Architecture (The Four Layers + Utilities)

The Method prescribes a **closed architecture** with four layers plus a Utilities bar.

```
  ┌─────────────────────────────────────────────┐
  │              CLIENT LAYER                    │  ← Who
  │  (Portals, Apps, APIs, Timers, Admin)       │
  ├─────────────────────────────────────────────┤
  │         BUSINESS LOGIC LAYER                │
  │  ┌──────────────┐  ┌──────────────┐         │
  │  │   Managers    │  │   Engines    │         │  ← What / How
  │  │ (sequence)    │  │ (activity)   │         │
  │  └──────────────┘  └──────────────┘         │
  ├─────────────────────────────────────────────┤  ┌──────────┐
  │         RESOURCE ACCESS LAYER               │  │          │
  │  (Atomic business verbs, NOT CRUDs)         │  │ UTILITIES│
  ├─────────────────────────────────────────────┤  │  BAR     │
  │            RESOURCE LAYER                   │  │(Security,│
  │  (Database, Files, Queues, External Systems)│  │ Logging, │
  └─────────────────────────────────────────────┘  │ Pub/Sub) │
                                                   └──────────┘
```

### Layer Roles

| Layer | Encapsulates | Component Type | Named As |
|-------|-------------|----------------|----------|
| **Client** | Volatility in WHO interacts | Client apps | N/A |
| **Manager** | Volatility in WHAT (use case sequence) | Managers | NounManager |
| **Engine** | Volatility in HOW (business activity) | Engines | GerundEngine |
| **ResourceAccess** | Volatility in HOW to access resources | ResourceAccess | NounAccess |
| **Resource** | WHERE system state lives | Resources | N/A |
| **Utilities** | Cross-cutting infrastructure | Utilities | Security, Logging, etc. |

### Key Properties

- **Volatility decreases top-down**: Clients are most volatile; Resources are least volatile
- **Reuse increases top-down**: Clients are least reusable; Resources are most reusable
- **Managers should be almost expendable**: If changing a Manager is expensive, it is too big. If trivial, it is pass-through (a flaw).
- **Closed architecture**: Components call only the adjacent lower layer. No up, no sideways, no skip-layer.
- **ResourceAccess exposes atomic business verbs** (Credit, Debit, Pay), NOT CRUDs (Select, Insert, Delete)

### Naming Rules

- Two-part compound words in PascalCase: prefix + type suffix
- **Managers**: noun prefix (AccountManager, MarketManager)
- **Engines**: gerund prefix (CalculatingEngine, SearchEngine, RegulationEngine)
- **ResourceAccess**: noun prefix associated with the Resource (MembersAccess, PaymentsAccess)
- Gerund prefixes ONLY on Engines. Gerunds elsewhere signal functional decomposition.

### Cardinality Guidelines

- **Max 5 Managers** in a system without subsystems
- **Max a handful of subsystems**
- **Max 3 Managers per subsystem**
- Golden ratio: 1 Manager: 0-1 Engines, 2 Managers: ~1 Engine, 3 Managers: ~2 Engines, 5 Managers: ~3 Engines
- **8+ Managers**: you have failed to produce a good design

See [references/structure.md](references/structure.md) for full details.

## Design "Don'ts"

These are **red flags indicating functional decomposition**. Violations must be investigated.

See [references/design-donts.md](references/design-donts.md) for the complete list (verbatim from the book).

## Composable Design

### Core Use Cases

Every system has 2-6 **core use cases** representing its raison d'etre. The composable design finds the **smallest set of ~10 components** that satisfies ALL core use cases. Non-core use cases (add member, create project, pay) are simple functionalities that any design can handle.

### "There Is No Feature"

Features are aspects of **integration**, not implementation. You do not implement features in individual services. Features emerge from how services interact. To add or change a feature, you change the workflows of the Managers, not the participating services.

### Handling Change

When a new requirement arrives, the correct response with a composable design is:
1. Mostly leave existing things alone
2. Extend the system by adding more slices or subsystems
3. Never destroy the first floor to add a second floor

See [references/composition.md](references/composition.md) for full details.

## Service Contract Design

Contracts are the public interfaces services present to clients. The basic element of reuse is the **contract, not the service**.

### Good Contracts Are:
1. **Logically consistent** -- no unrelated operations
2. **Cohesive** -- all aspects of the interaction, no more, no less
3. **Independent** -- each facet stands alone

### Contract Size Metrics
- **Optimal**: 3-5 operations per contract
- **Acceptable**: 6-9 operations
- **Poor design**: 12+ operations
- **Immediate reject**: 20+ operations
- **Red flag**: single-operation contracts

### Other Rules
- Avoid property-like operations (getters/setters)
- Limit contracts per service to 1 or 2
- Factor contracts down (base extraction), sideways (separate unrelated), up (shared hierarchy)

### Area of Minimum Cost
Total system cost = cost per service + integration cost. Both are nonlinear. There exists an **area of minimum cost** where services are not too big, not too small. Functional decomposition always lands at the expensive edges.

See [references/contract-design.md](references/contract-design.md) for full details.

## Design Validation

Validate the architecture BEFORE work begins:

1. Show the **call chain** or **sequence diagram** for each core use case
2. Demonstrate that the same components participate in multiple use cases in consistent patterns
3. Look for **self-similarity and symmetry** across call chains -- hallmark of good design
4. If validation is ambiguous, go back to the drawing board

## Business Alignment

Architecture must serve the business:

1. **Vision** -- terse, explicit, like a legal statement (e.g., "A platform for building applications to support the marketplace")
2. **Objectives** -- business perspective items derived from the vision (NOT technology objectives)
3. **Mission Statement** -- HOW you will deliver (e.g., "Design and build a collection of software components that the team can assemble into applications and features")
4. **Architecture** -- derived from mission statement, supporting all objectives

This chain (Vision -> Objectives -> Mission -> Architecture) reverses typical dynamics and gets the business on your side.

## Interaction Rules (Closed Architecture)

**Allowed:**
- All components can call Utilities
- Managers and Engines can call ResourceAccess
- Managers can call Engines
- Managers can queue calls to another Manager

**Forbidden** (see [Design "Don'ts"](references/design-donts.md)):
- No calling up
- No calling sideways (except queued Manager-to-Manager)
- No calling more than one layer down
- Resolve violations with queued calls or Pub/Sub

## Quick Reference Files

- [Decomposition](references/decomposition.md) -- Volatility-based decomposition, why functional/domain decomposition fail
- [Structure](references/structure.md) -- Layers, classification, naming, open/closed architectures, symmetry
- [Composition](references/composition.md) -- Composable design, core use cases, handling change
- [Design "Don'ts"](references/design-donts.md) -- VERBATIM list of architectural violations
- [Design Standard](references/design-standard.md) -- VERBATIM checklist of all directives and guidelines
- [Contract Design](references/contract-design.md) -- Service contracts, factoring, metrics, area of minimum cost
- [Design Example](references/design-example.md) -- TradeMe case study demonstrating the full method
