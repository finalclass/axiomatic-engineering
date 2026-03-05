# System Design Example: TradeMe (Ch. 5)

A complete case study demonstrating The Method applied to a real system. Focus on the **thought process and rationale**, not on copying the specific outcome -- every system is different.

## System Overview

**TradeMe** is a marketplace system for matching tradesmen (plumbers, electricians, etc.) to contractors and construction projects. Think of it as a brokerage platform.

- **Tradesmen**: Self-employed skilled workers with skill levels, certifications, geographic areas, expected pay rates
- **Contractors**: Need tradesmen on an ad hoc basis (days to weeks), list projects with required trades, skills, location, rates, duration
- **Revenue model**: Spread between tradesman ask rate and contractor bid rate + membership fees
- **Operations**: 9 call centers across Europe, ~220 account reps, locale-specific regulations
- **Legacy system**: Two-tier desktop app, 5 disconnected subsystems, business logic in clients, no security design, change-resistant

**Goals for new system**: Automate work, single system across all locales, deploy beyond Europe, compete with more flexible competitors.

## Use Cases and Core Use Case Identification

The customer provided 8 use cases (mostly reflecting legacy behavior):
1. Add Tradesman/Contractor
2. Request Tradesman
3. Match Tradesman
4. Assign Tradesman
5. Terminate Tradesman
6. Pay Tradesman
7. Create Project
8. Close Project

### Finding the Core Use Case

Most provided use cases were simple functionalities (add member, create project, pay someone) that any design can handle. The system's raison d'etre is **matching tradesmen to contractors and projects**. Only **Match Tradesman** resembles the core purpose.

**Principles**:
- Core use cases represent the essence of the business (2-6 per system)
- They are rarely presented explicitly in requirements
- They are almost always abstractions of other use cases
- Even flawed requirements contain them because they ARE the business
- Do NOT ignore non-core use cases -- demonstrating that the design easily supports them shows the design's versatility

### Simplifying Use Cases

**Swim lanes technique**: Show flow of control between roles. For TradeMe, three role types were identified:
- **Client** (users -- back-office reps or system admins)
- **Market** (core marketplace logic)
- **Member** (tradesmen and contractors)

Swim lanes help clarify required behavior, add decision boxes or synchronization bars, and are later used to seed and validate the design.

## The Anti-Design Effort

Deliberately produce the **worst possible design** through functional decomposition, to expose what NOT to do.

### Anti-Design #1: The Monolith
A single god service -- dumping ground of all functionalities. No encapsulation. Cannot validate.

### Anti-Design #2: Granular Building Blocks (Services Explosion)
Every activity in the use cases becomes a component. Results in either:
- **Fat client**: Client absorbs all business logic (orchestration, sequencing, error compensation)
- **Chained services**: Services call each other up and sideways -- tight coupling, open architecture

### Anti-Design #3: Domain Decomposition
Decompose along entity lines (Tradesman service, Contractor service, Project service). Nearly limitless possible domain boundaries with no principled selection criteria. Impossible to validate -- a request touches multiple domains. Has all drawbacks from Chapter 2.

## Business Alignment

### The Vision
> *A platform for building applications to support the TradeMe marketplace.*

- Terse and explicit -- read like a legal statement
- "Platform" (not just "application") addresses business need for diversity and extensibility
- Powerful tool for **repelling irrelevant demands** that do not serve the vision

### The Business Objectives (7 items)
1. Unify repositories and applications
2. Quick turnaround for new requirements
3. High degree of customization across countries/markets
4. Full business visibility and accountability (fraud detection, audit)
5. Forward looking on technology and regulations
6. Integrate well with external systems
7. Streamline security

**Note**: Development cost was NOT an objective. The pain was in the items above.

### The Mission Statement
> *Design and build a collection of software components that the development team can assemble into applications and features.*

Deliberately does NOT identify developing features as the mission. The mission is to **build components** -- making volatility-based decomposition the natural approach.

### The Chain
```
Vision → Objectives → Mission Statement → Architecture
```
This **reverses typical dynamics**: instead of the architect pleading with management, you compel the business to instruct you to design the right architecture. Once they agree on the chain, they are on your side.

## Volatility Identification

### Glossary (Who/What/How/Where)
Before decomposing, answer four questions to seed the effort:

- **Who**: Tradesmen, Contractors, Reps, Education centers, Background processes (timers)
- **What**: Membership, Marketplace of projects, Certificates/training
- **How**: Searching, Complying with regulations, Accessing resources
- **Where**: Local database, Cloud, Other systems

The "what" list hints strongly at possible subsystems. Use it to **seed decomposition** as you look for volatilities.

### Rejected/Reframed Volatility Candidates

| Candidate | Verdict | Reason |
|-----------|---------|--------|
| **Tradesman** | Rejected | Variable, not volatile. Adding attributes doesn't change architecture. Signals domain decomposition. Real volatility is *membership management*. |
| **Education certificates** | Reframed | Certification itself is just an attribute. Real volatility is in the *workflow of matching regulations with certifications* (→ Regulation Engine). |
| **Projects** | Reframed | A `Project Manager` implies domain decomposition. A `Market Manager` is better -- many activities don't require a project context. Core volatility is *the marketplace*. |
| **Payments** | Outside system | Volatile but ancillary. TradeMe is not a payment system. Handled as external *Resources*. |
| **Notification** | Weak | Message Bus Utility suffices. Only if notification transport became strongly volatile would a dedicated Manager be needed. |
| **Analysis** | Rejected | Speculative design. The company is not in the optimization business. Folded into Market Manager if ever needed. |

**Principle**: If identifying a volatility produces domain decomposition along entity lines, look further. You must clearly state: WHAT the volatility is, WHY it is volatile, WHAT RISK it poses.

### Accepted Areas of Volatility

| Volatility Area | Encapsulated In | Notes |
|---|---|---|
| Client applications | Individual Client apps | Each client environment evolves independently |
| Managing membership | `Membership Manager` | Adding/removing members, benefits, discounts |
| Fees | `Market Manager` | All ways TradeMe makes money |
| Projects | `Market Manager` | NOT a separate Project service |
| Disputes | `Membership Manager` | Misunderstandings, fraud |
| Matching and approvals | `Search Engine` + `Market Manager` | Two sub-volatilities: algorithm + criteria definition |
| Education | `Education Manager` + `Search Engine` | Training workflow + class searching |
| Regulations | `Regulation Engine` | Changes per country and over time |
| Reports | `Regulation Engine` | Reporting and auditing requirements |
| Localization | `Clients` (UI) + `Regulation Engine` (rules) | Two distinct sub-volatilities |
| Resources (storage) | `ResourceAccess` + `Resources` | Storage nature is volatile |
| Deployment model | Subsystem composition + `Message Bus` | Cloud vs on-premise, data locality |
| Authentication/authorization | `Security` Utility | Credential models, identity, roles |

**Key**: The mapping of volatilities to components is NOT 1:1. A single Manager can encapsulate multiple related volatilities.

## Static Architecture

```
CLIENT TIER:
  Tradesman Portal | Contractors Portal | Education Portal | Marketplace App | Timer

UTILITIES (vertical bar):
  Security | Logging | Message Bus

BUSINESS LOGIC TIER:
  Membership Manager | Market Manager | Education Manager
  Regulation Engine | Search Engine

RESOURCE ACCESS TIER:
  Regulations Access | Payments Access | Members Access
  Projects Access | Contractors Access | Education Access | Workflows Access

RESOURCES TIER:
  Regulations | Payments | Members | Projects | Contractors | Education | Workflows
```

### Key Observations
- **3 Managers** (Membership, Market, Education) -- within cardinality guidelines
- **2 Engines** (Regulation, Search) -- golden ratio to Managers
- **Timer** is in Client tier because it initiates behavior even though it's not part of the system
- **ResourceAccess** converts atomic business verbs (e.g., "pay") into resource access
- **3 Utilities**: Security, Message Bus, Logging

## Operational Concepts

### All Communication via Message Bus
All Client-to-Manager communication happens over the Message Bus. Clients and Managers never interact directly -- they are unaware of each other, fostering extensibility and independent evolution.

### Message Bus Properties
- Queued Pub/Sub mechanism: N:M communication
- Messages queue if bus or publisher is down, process when connectivity restores
- Private queue per subscriber handles subscriber downtime
- Minimum features: queuing, multicast, security, headers/context propagation, offline work, failure handling, transactional processing, high throughput, multiple-protocol support, reliable messaging

### "The Message Is the Application" Pattern

The most important operational concept. There is no single collection of components you can point to as "the application." The system is a loose collection of services posting and receiving messages. Each service processes a message, does local work, posts back to the bus. Behavior changes are induced by changing how services respond to messages, not by changing the architecture.

**When NOT to use**: Adds complexity. A simpler design where Clients just queue calls to Managers may suffice. Calibrate to the capability of the developers and management.

## Workflow Manager Pattern

A Manager that can create, store, retrieve, and execute workflows using a third-party workflow execution tool.

**How it operates**:
1. For each Client call, load the correct workflow type AND specific instance (with state/context)
2. Execute the workflow
3. Persist the workflow instance back to the workflow store
4. No session with the Client -- state-aware through workflow persistence
5. Each call carries the unique workflow instance ID

**Benefits**:
- To add/change a feature, change the *workflows*, not the participating services
- Product owners or end users can edit workflows (with safeguards)
- Enables high degree of customization across markets
- Software team focuses on core services rather than chasing requirement changes

## Design Validation

Validate the architecture BEFORE work commences by showing the call chain for each use case.

### Validation Pattern (Self-Similar Across All Use Cases)
1. A Client posts to the Message Bus
2. A Manager (workflow-based) picks up the message and loads the appropriate workflow
3. The Manager consults Engines and/or ResourceAccess components
4. The Manager posts results back to the Message Bus
5. Other Managers and/or Clients respond to the posted message

### Use Case Validations Summary

**Add Tradesman/Contractor**: Client → Message Bus → Membership Manager (loads workflow from Workflows Access) → Regulation Engine + Payments Access + Members Access

**Request Tradesman**: Client → Message Bus → Market Manager (loads workflow) → Regulation Engine + Projects Access. Posts back to bus triggering Match Tradesman.

**Match Tradesman** (core use case): Client/Timer → Message Bus → Market Manager → Search Engine + Members Access + Projects Access + Contractors Access. Posts to bus → triggers Membership Manager for Assign.

**Assign Tradesman**: Message Bus → Membership Manager → Regulation Engine + Members Access. Posts to bus → Market Manager → Projects Access. Collaborative execution between two Managers via bus.

**Terminate Tradesman**: Client → Message Bus → Market Manager → Projects Access. Posts to bus → Membership Manager → Regulation Engine + Members Access. Flow can also run in **reverse direction** (tradesman-initiated).

**Pay Tradesman**: Timer → Message Bus → Market Manager → Workflows Access + Payments Access (→ external payment system).

**Create Project**: Client → Message Bus → Market Manager → Workflows Access + Projects Access. Simple, handled entirely by one Manager.

**Close Project**: Client → Message Bus → Market Manager → Projects Access. Posts to bus → Membership Manager → Regulation Engine + Members Access. Same pattern as Terminate Tradesman -- reinforces self-similarity.

### Cross-Cutting Patterns

- **Self-similarity and symmetry**: Every call chain follows the same structural pattern. This is a hallmark of good design.
- **Use case chaining**: Request → Match → Assign → Pay. Each operates independently, chaining through messages on the bus.
- **Bidirectional flow**: Same architecture supports flows from different initiators (contractor-initiated vs tradesman-initiated termination).
- **Composability**: New capabilities added by subscribing new services to existing messages or adding new workflows -- no modification of existing components.

## Principles Demonstrated

1. Design takes hours to days, not months (TradeMe: less than a week, two-person team)
2. Always transform, clarify, and consolidate raw requirements
3. The anti-design effort exposes what NOT to do
4. Business alignment (Vision → Objectives → Mission → Architecture) gets the business on your side
5. Candidate volatilities must be rigorously challenged -- entities as volatilities signal domain decomposition
6. Distinguish variable (data changes) from volatile (behavior/structure changes)
7. Volatility may reside outside the system (payments as external Resources)
8. The mapping of volatilities to components is not 1:1
9. Self-similarity and symmetry in call chains validate the design
10. The design is open-ended -- extend by adding more services or workflows, never by modifying existing ones
