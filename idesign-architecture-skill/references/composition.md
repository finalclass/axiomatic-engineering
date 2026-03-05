# Composition (Ch. 4)

## Requirements and Changes

Requirements change -- that is what requirements do. The more requirements change, the higher the demand for software professionals. Embrace change; it is what keeps you employed.

### Resenting Change

Most developers design their system against the requirements, maximizing the affinity between requirements and architecture. When requirements change, the design must change too. This makes change painful, expensive, and destructive. People learn to resent change -- literally resenting the hand that feeds them.

### The Design Prime Directive

**Never design against the requirements.**

Any attempt at designing against the requirements will always guarantee pain. There should never be a direct mapping between requirements and design.

### Futility of Requirements

- A decent system has dozens of use cases; large systems have hundreds
- No one has ever had the time to correctly spec all use cases upfront
- Requirements specs contain duplicates, contradictions, missing items
- Requirements will change over time: new ones added, existing ones removed or modified
- Attempting to gather the complete set and design against them is an exercise in futility

## Composable Design

The goal of any system design is to satisfy ALL use cases -- present and future, known and unknown. A composable design does not aim to satisfy any use case in particular.

### Core Use Cases

Not all use cases are equal. There are only two types:
- **Core use cases**: represent the essence of the business (2-6 per system, rarely more)
- **Regular use cases**: variations and permutations of core use cases

Core use cases:
- Will hardly ever be presented explicitly in the requirements document
- Are not easy to find, and the small number does not make it simple to agree on what they are
- Will almost always be some kind of abstraction of other use cases
- May require a new term or name to differentiate them from the rest
- Even a flawed requirements document will contain them because they ARE the essence of the business

Finding core use cases is an iterative process between the architect and the requirements owner.

### The Architect's Mission

Your mission as architect: identify the **smallest set of components** that you can put together to satisfy all the core use cases. Since all other use cases are merely variations, regular use cases represent a different interaction between the components, not a different decomposition.

**When requirements change, your design does not.**

This is about decomposition into components, not implementation. The integration code inside Managers will change as requirements change -- but that is an implementation change, not an architectural change.

## Architecture Validation

Composable design enables **design validation**: produce an interaction between your services for each core use case.

### Call Chain Diagrams
- Superimpose the call chain onto the layered architecture diagram
- Components connected by arrows showing direction and type of call
- Solid black arrow = synchronous (request/response) call
- Dashed gray arrow = queued call
- Simple, quick, good for nontechnical audiences
- Downside: no notion of call order, duration, or multiple calls to same component

### Sequence Diagrams
- Similar to UML sequence diagrams with IDesign notational differences
- Lifelines colored according to architectural layers
- Each participating component has a vertical bar (lifeline)
- Time flows top to bottom; length of bars indicates relative duration
- Better for complex use cases and technical audiences
- Extremely useful for subsequent detailed design (interfaces, methods, parameters)

### Smallest Set

You want not just a set of components but the **smallest** set. Less is more in architecture.

- A monolith (1 component) is too few -- horrible internal complexity
- 300 components (one per use case) is too many -- high integration cost
- The order of magnitude for a typical system is ~10 services
- Using The Method: 2-5 Managers, 2-3 Engines, 3-8 ResourceAccess, plus Resources and Utilities = ~12 building blocks at most
- If larger, break into subsystems

**You cannot validate architectures with a single component or hundreds of components.** A single large component by definition does everything, and a component per use case also supports all use cases -- neither proves design merit.

### Duration of Design Effort

- Requirements gathering and analysis may take weeks or months -- that is NOT design
- Once you have the core use cases and areas of volatility, producing a valid design using The Method takes hours to a few days at most
- Design is not time-consuming if you know what you are doing

## There Is No Feature

**Features are always and everywhere aspects of integration, not implementation.**

This is a universal design rule governing all systems. You never see a "feature" as a discrete component in any well-designed system:
- A car transports you from A to B -- the feature emerges from integrating chassis, engine, gearbox, seats, dashboard, driver, road, insurance, and fuel
- A laptop provides word processing -- the feature emerges from integrating keyboard, screen, hard drive, bus, CPU, and memory
- This is fractal: every level of every system works the same way, down to the quarks

In software: you do not implement features in individual services. Features emerge from how services interact. To add or change a feature, you change the workflows of the Managers, not the participating services.

## Handling Change

With functional decomposition, change is spread across multiple components and aspects of the system. People defer changes, fight changes, or explain to customers that changes are bad ideas. Fighting change is tantamount to killing the system -- customers need the feature now, not in six months.

### Containing the Change

The trick is not to fight, postpone, or punt change -- it is to **contain its effects**.

With volatility-based decomposition:
- A change to a requirement is a change to a use case
- Some Manager implements the workflow executing that use case
- The Manager may be gravely affected -- perhaps you discard it entirely and create a new one
- But the underlying components (Engines, ResourceAccess, Resources, Utilities) are NOT affected

The bulk of effort in any system goes into the services the Manager uses:
- **Engines** are expensive: business activities vital to the system's workflows
- **ResourceAccess** is nontrivial: identifying atomic business verbs, translating them to resource access methods
- **Resources** must be scalable, reliable, highly performant: schemas, caching, replication, partitioning, connection management, indexing, transactions, etc.
- **Utilities** require top skills: world-class security, diagnostics, logging, messaging, hosting
- **Clients** are time and labor intensive: superior UX, convenient and reusable APIs

When a change happens to the Manager, you salvage and reuse ALL the effort that went into Clients, Engines, ResourceAccess, Resources, and Utilities. By reintegrating these services in the Manager, you contain the change and respond quickly and efficiently.

**This is the essence of agility.**
