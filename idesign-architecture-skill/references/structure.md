# Structure (Ch. 3)

## Layers and Services

A layered approach to system design requires a handful of layers, terminating with a layer of actual physical resources (database, message queue, etc.). The preferred way of crossing layers is by calling services.

### Benefits of Using Services

1. **Scalability** -- services can be instantiated per-call, avoiding proportional back-end load
2. **Security** -- service-oriented platforms treat security as first-class; they authenticate and authorize all calls (not just from client, but between services)
3. **Throughput and availability** -- services can accept calls over queues, handling excess load; multiple instances can process the same queue
4. **Responsiveness** -- services can throttle calls into a buffer
5. **Reliability** -- can use reliable messaging protocols, handle network issues, order calls
6. **Consistency** -- services can participate in the same unit of work (transaction or coordinated business transaction with eventual consistency)
7. **Synchronization** -- calls can be automatically synchronized even if clients use multiple concurrent threads

## The Four Layers + Utilities

### Client Layer (Presentation Layer)

- The top layer. Elements can be end-user applications OR other systems interacting with your system.
- All Clients use the same entry points, subject to the same access security, data types, and interfacing requirements.
- Encapsulates the potential volatility in Clients: desktop apps, web portals, mobile apps, APIs, admin applications. These use different technologies, deploy differently, have their own versions and life cycles.
- Often the most volatile part of a typical software system.
- Changes in one Client component do not affect another.

### Business Logic Layer

Encapsulates the volatility in the system's business logic (required behavior, best expressed in use cases).

#### Managers
- Encapsulate the volatility in the **sequence** (orchestration of the workflow)
- Tend to encapsulate a **family of logically related use cases** within a particular subsystem
- Each Manager has its own related set of use cases to execute

#### Engines
- Encapsulate the volatility in the **activity** (business rules and activities)
- More restricted scope than Managers
- Managers may use zero or more Engines
- Engines may be shared between Managers (designed with reuse in mind)
- If two Managers use two different Engines for the same activity, you have functional decomposition

### Resource Access Layer

- Encapsulates the volatility in accessing a resource
- Must encapsulate both: (a) volatility in the method of access, and (b) volatility in the resource itself

**Critical Rule: Do NOT expose CRUD-like or I/O-like contracts.**
- If your ResourceAccess contract has Select(), Insert(), Delete() -- you are exposing that the resource is a database
- Avoid operations like Open(), Close(), Seek(), Read(), Write() -- these betray a file-based resource

**Use Atomic Business Verbs:**
- Activities decompose to indivisible activities called atomic business verbs
- Example: In a bank, "credit" and "debit" are atomic business verbs (atomic from the business perspective)
- Atomic business verbs are practically immutable because they relate to the nature of the business
- A well-designed ResourceAccess exposes atomic business verbs, converting them internally to CRUDs

### Resource Layer

- Contains actual physical Resources: database, file system, cache, message queue
- The Resource can be internal or external to the system
- Often the Resource is a whole system in its own right

### Utilities Bar

- A vertical bar on the side of the architecture containing Utility services
- Common infrastructure that nearly all systems require
- Examples: Security, Logging, Diagnostics, Instrumentation, Pub/Sub, Message Bus, Hosting
- **Litmus test**: Can the component plausibly be used in any other system, such as a smart cappuccino machine?

## Classification Guidelines

### Naming Rules

Names must be two-part compound words in PascalCase. The suffix is the service type.

| Type | Suffix | Prefix | Examples |
|------|--------|--------|----------|
| Manager | Manager | Noun associated with encapsulated use case volatility | AccountManager, MarketManager, MembershipManager |
| Engine | Engine | Gerund (noun from verb + "-ing") or noun describing activity | CalculatingEngine, SearchEngine, RegulationEngine |
| ResourceAccess | Access | Noun associated with the Resource | MembersAccess, PaymentsAccess, ProjectsAccess |

**Gerund rules:**
- Gerunds should ONLY be used as prefix with Engines. Gerunds elsewhere signal functional decomposition.
- Good: CalculatingEngine (Engines "do" things: aggregate, adapt, strategize, validate, rate, calculate, transform)
- Bad: BillingManager, BillingAccess -- the gerund conveys "doing" rather than orchestration or access volatility
- Good: AccountManager, AccountAccess

**Atomic business verbs should NOT be used in a prefix** for a service name. These verbs belong only in operation names in contracts at the resource access level.

### The Four Questions

| Question | Layer | Description |
|----------|-------|-------------|
| **Who** | Clients | Who interacts with the system |
| **What** | Managers | What is required of the system |
| **How** (Business) | Engines | How the system performs business activities |
| **How** (Resource) | ResourceAccess | How the system accesses Resources |
| **Where** | Resources | Where the system state is |

Use the four questions for **initiation** (start with a clean slate) and **validation** (check: are all Clients purely "who" with no "what"?).

### Managers-to-Engines Ratio

| Managers | Engines |
|----------|---------|
| 1 | 0 or at most 1 |
| 2 | likely 1 |
| 3 | 2 is likely best |
| 5 | may need as many as 3 |
| 8+ | you have already failed |

Most systems will never have many Managers because they will not have many truly independent families of use cases. A single Manager can support more than one family of use cases (different service contracts or facets).

### Key Observations

**Volatility decreases top-down:**
- Clients are the most volatile
- Managers change when use cases change, but less than Clients
- Engines are less volatile than Managers
- ResourceAccess is even less volatile
- Resources are the least volatile, changing at a glacial pace

This is extremely valuable: the most-depended-upon components (lower layers) are also the least volatile. If they were most volatile, the system would implode.

**Reuse increases top-down:**
- Clients are hardly ever reusable (platform-specific)
- Managers are reusable (same Manager from multiple Clients)
- Engines are even more reusable (same Engine called by multiple Managers)
- ResourceAccess components are very reusable
- Resources are the most reusable element

**Almost-Expendable Managers:**
1. **Expensive Manager** -- you fight the change, fear its cost. Too big, likely functional decomposition.
2. **Expendable Manager** -- you shrug it off, think nothing of it. Pass-through. Always a design flaw.
3. **Almost-Expendable Manager** -- you contemplate the change, think through specific ways to adapt. **This is the ideal.** The Manager merely orchestrates Engines and ResourceAccess, encapsulating sequence volatility.

## Subsystems and Services

### Vertical Slices
- A cohesive interaction between Manager, Engine, and ResourceAccess constitutes a logical subsystem -- a vertical slice
- Each vertical slice implements a corresponding set of use cases

### Sizing
- Avoid over-partitioning. Most systems: only a handful of subsystems.
- Limit Managers per subsystem to three.

### Incremental Construction
- **Incremental** = build components layer by layer within a correct architecture (foundation, walls, roof)
- **Iterative** = grow from a small version to a larger one (skateboard to car) -- wasteful and difficult
- Building incrementally is predicated on the architecture remaining constant. Only possible with volatility-based decomposition.
- Extensibility: mostly leave existing things alone, extend by adding more slices or subsystems.

## About Microservices

There are no microservices -- only services. Services are services regardless of size.

### Three Problems with Microservices (as commonly practiced)

1. **Implied constraint on the number of services** -- the building blocks within subsystems (Manager, Engine, ResourceAccess) should all be services too. Push the benefits of services as deep as possible.
2. **Widespread use of functional decomposition** -- dooms every microservices effort. Potentially the biggest failure in the history of software.
3. **Communication protocols** -- the vast majority use REST/HTTP for all communication. A well-designed system should NEVER use the same communication mechanism internally and externally. External: HTTP may be fine. Internal: use fast, reliable channels (TCP/IP, named pipes, IPC, message queues, etc.).

## Open and Closed Architectures

### Open Architecture (Avoid)
- Any component can call any other regardless of layer
- Trading encapsulation for flexibility is a bad trade
- Calling down multiple layers: when you switch a Resource, all Engines must change
- Calling up: Manager must respond to UI changes
- Calling sideways: Manager A calling Manager B -- almost always functional decomposition

### Closed Architecture (Preferred)
- Components in one layer can call those in the adjacent lower layer only
- Promotes decoupling by trading flexibility for encapsulation -- the better trade

### Semi-Closed/Semi-Open (Avoid)
- Allows calling more than one layer down
- Justified only in: (1) key infrastructure where every ounce of performance matters, (2) codebases that hardly ever change

## Relaxing the Rules

### Calling Utilities
Utilities reside in a vertical bar cutting across all layers. Any component can use any Utility.

### Calling ResourceAccess by Business Logic
Both Managers and Engines can call ResourceAccess without violating closed architecture.

### Managers Calling Engines
Managers can directly call Engines. Engines are really an expression of the Strategy design pattern.

### Queued Manager-to-Manager Calls
A Manager can queue a call to another Manager (the queue listener is effectively another Client). Business systems commonly have one use case triggering a deferred execution of another use case.

### Opening the Architecture (Handling Violations)
- Do NOT brush transgressions aside or demand blind compliance
- Nearly always, a transgression indicates an underlying need
- Address the need in a way that complies with closed architecture
- Sideways Manager call? -> Queue the call instead
- Manager calls up to Client? -> Use Pub/Sub Utility service

## Strive for Symmetry

- All good architectures are symmetric
- Symmetry appears as repeated call patterns across use cases
- Absence of symmetry is a cause for concern
- If a Manager implements four use cases and three publish events but the fourth does not -- why? Investigate.
- If only one of four use cases queues a call to another Manager -- that asymmetry is a design smell
- Symmetry is so fundamental you should see the same call patterns across Managers
