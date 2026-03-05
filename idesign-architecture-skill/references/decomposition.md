# Decomposition (Ch. 2)

## Core Premise: Architecture = Decomposition

- **Software architecture** is the high-level design and structure of the software system.
- The essence of architecture is the breakdown of the system into its comprising components and how those components interact at run-time. This act is called **system decomposition**.
- **Wrong decomposition = wrong architecture**, which inflicts horrendous pain in the future, often leading to a complete rewrite.
- Services (in the service-orientation sense) are the most granular unit of architecture. Technology details (interfaces, operations, class hierarchies) are detailed design, NOT system decomposition.

## Avoid Functional Decomposition

Functional decomposition decomposes a system into building blocks based on its functionality. If the system needs invoicing, billing, and shipping, you create InvoicingService, BillingService, ShippingService.

### Why It Fails

1. **Couples services to requirements** -- any change in required functionality imposes a change on services. Such changes are inevitable over time.
2. **Precludes reuse** -- services encode call ordering (what comes before/after), forming a clique of tightly coupled services that cannot be independently reused.
3. **Too many or too big** -- leads to an explosion of services (hundreds of narrow functionalities) or bloated god monoliths. Both afflictions often appear side by side.
4. **Client bloat and coupling** -- someone must combine functional services into required behavior; that someone is the client. The client absorbs business logic (sequencing, ordering, error compensation). The client IS the system. Multiple clients (web, mobile) duplicate orchestration logic.
5. **Multiple points of entry** -- the client enters the system in multiple places, multiplying security, scalability, and cross-cutting concerns.
6. **Service chaining bloat** -- alternative: services call each other (A calls B calls C). Services become coupled to call order. Error compensation creates massive coupling (C must undo A and B on failure).
7. **Maximizes the effect of change** -- by definition, changes affect multiple (if not most) components. Accommodating change is THE reason to avoid functional decomposition.
8. **Makes systems untestable** -- coupling and complexity make only unit testing practical. Unit testing alone is borderline useless (defects are in interactions). Functional decomposition makes regression testing impractical, producing systems rife with defects.

### The TANSTAAFL Argument

Functional decomposition violates the first law of thermodynamics: the outcome (system design) should be high-value, but the process (mapping requirements to services) is fast, easy, mechanistic. **You cannot add value without effort.** The very attributes that make functional decomposition appealing preclude it from adding value.

### When TO Use Functional Decomposition

Functional decomposition IS a decent **requirements discovery technique** -- it helps discover hidden functionality areas, uncover requirements and their relationships. **Extending functional decomposition into a design is deadly.** There should never be a direct mapping between requirements and design.

## Avoid Domain Decomposition

Domain decomposition decomposes based on business domains (Sales, Engineering, Accounting). It is **even worse** than functional decomposition -- it is functional decomposition in disguise (Kitchen is where you do the cooking, Bedroom is where you do the sleeping).

Problems unique to domain decomposition:
- Each domain must duplicate functionality that occurs across domains
- Each domain devolves into an ugly grab bag of functionality
- Cross-domain communication reduced to CRUD-like state changes
- Building sequentially by domain is catastrophically wasteful (each new domain requires reworking all previous domains)
- There is no meaningful reuse between parts

## Volatility-Based Decomposition

### The Method's Design Directive

**Decompose based on volatility.**

### Definition

Volatility-based decomposition identifies **areas of potential change** and encapsulates those into services or system building blocks. You then implement the required behavior as the **interaction between the encapsulated areas of volatility**.

### The Vault Metaphor

Think of your system as a series of vaults. Any change is like a hand grenade with the pin pulled out. With volatility-based decomposition: open the appropriate vault's door, toss the grenade inside, close the door. Whatever was inside may be destroyed completely, but **there is no shrapnel flying everywhere**. You have contained the change.

### Encapsulation Is Not Necessarily Functional

What you encapsulate CAN be functional in nature but is hardly ever domain-functional (meaningful to the business). Example: Electricity in a house is an area of functionality AND an important area to encapsulate because power is highly volatile (AC/DC, 110V/220V, solar/generator/grid) and not specific to any domain. The receptacle encapsulates all that volatility.

### Identifying Volatility

- **Volatility vs. Variability**: A tradesman gaining new attributes is variable (data changes). The membership management process changing is volatile (behavior/structure changes). Only volatile things merit components.
- If identifying a volatility produces domain decomposition along entity lines, look further for the true underlying volatility.
- You must clearly state: WHAT the volatility is, WHY it is volatile, WHAT RISK it poses (likelihood and effect).
- There is nothing wrong with suggesting candidate volatilities, then examining the resultant architecture. If the result is a spiderweb of interactions or is asymmetric, the design is likely wrong.
- Volatility may reside outside the system entirely (e.g., payments handled by external systems as Resources).

### Solutions Masquerading as Requirements

Requirements often contain embedded solutions that constrain the design space unnecessarily. Before identifying volatilities, eliminate solutions masquerading as requirements:
- "The system shall use a SQL database" -- the real requirement is data persistence
- "The system shall send email notifications" -- the real requirement is user notification
- Strip away the "how" to reveal the "what"

### Benefits

- Changes are **contained in each module** -- no side effects outside the module boundary
- Lower complexity + easier maintenance = much improved quality
- **Reuse**: if something is encapsulated the same way in another system, you have a chance at reuse
- **Extensibility**: extend by adding more areas of encapsulated volatility or integrating existing areas differently
- **Resilience to feature creep**: changes during development are contained, giving a better chance of meeting the schedule

### VBD and Testing

Volatility-based decomposition lends well to regression testing. Fewer components, smaller components, and simpler interactions drastically reduce complexity. This makes it feasible to write regression testing that tests the system end to end, tests each subsystem individually, and eventually tests independent components. Since VBD contains changes inside building blocks, inevitable changes do not disrupt regression testing. You can test a change in isolation without interfering with inter-component and inter-subsystem testing.

### The Volatility Challenge

The main challenges in performing volatility-based decomposition have to do with **time, communication, and perception**:

- Volatility is often not self-evident. No customer will present requirements as areas of volatility -- they present functionality.
- VBD takes longer than functional decomposition. You must analyze requirements to recognize areas of volatility.
- The whole purpose of requirements analysis is to identify areas of volatility. This requires effort and sweat -- complying with the first law of thermodynamics (TANSTAAFL).
- **The 2% problem**: Architects decompose complete systems only every few years. The week-to-year ratio is roughly 1:50, or 2%. You will never be good at something you spend only 2% of your time on. Managers who spend an even smaller fraction managing architects during this critical phase will not understand why it takes time.
- **Dunning-Kruger effect**: People unskilled in a domain underestimate its complexity. When a manager says "just do A, then B, then C" they genuinely do not understand why proper decomposition takes time. Expect this and educate.
- **Fighting insanity**: If functional decomposition is all you have ever done, you will hear an irresistible pull to repeat it. You must resist. Your professional integrity is at stake.

### Resist the Siren Song

Just because you always had a reporting block, or because a reporting block already exists, does not mean you need a dedicated reporting component. If reporting is not a volatile area (from the business perspective), there is nothing to encapsulate. Adding such a component manifests functional decomposition.

You are Odysseus. Volatility-based decomposition is your mast. Resist the siren song of your previous bad habits. Plug the ears of the developers (they row/write code) and tie yourself to the method even when temptation strikes.

### Volatility and the Business

Not everything that could change should be encapsulated. Do **not** attempt to encapsulate the **nature of the business**.

Two indicators that a potential change is the nature of the business (and should NOT be encapsulated):
1. **The change is very rare** -- the likelihood of it happening is very low
2. **The encapsulation can only be done poorly** -- no practical amount of investment in time or effort will properly encapsulate it

A change to the nature of the business justifies killing the old system and starting from scratch (like razing a house to build a skyscraper on the same plot).

**Speculative design**: Once you embrace VBD, you may start seeing volatilities everywhere and try to encapsulate everything. This produces numerous building blocks -- a clear sign of bad design. If the use of an encapsulation is extremely unlikely, or it attempts to change the nature of the system, you have fallen into the speculative design trap.

### Design for Your Competitors

A useful technique for identifying volatilities: try to design a system for your competitor (or another division).

- Ask: Can your competitor use the system you are building? Can you use theirs?
- If not, list the barriers to reuse. Where both companies perform the same service differently, that activity is probably volatile -- encapsulate it.
- If both do something identically with no chance of divergence, there is no need for a component. Allocating one would be functional decomposition. Things competitors do identically likely represent the nature of the business.
- If you encapsulate a volatile activity and your competitor later adopts the same approach, the change is contained in a single component -- you have future-proofed your system.

### Volatility and Longevity

Volatility is intimately related to longevity. The longer things have been done a certain way, the longer they will likely continue -- but also the longer until they eventually change.

- You must put forward a design that accommodates changes even if at first glance they seem independent of current requirements.
- **Heuristic for time horizon**: If the projected system lifespan is 5-7 years, identify everything that changed in the application domain over the past 7 years. Similar changes will likely occur within a similar timespan.
- Examine the longevity of all involved systems and subsystems your design interacts with. If the ERP changes every 10 years and the last change was 8 years ago, encapsulate the ERP volatility.
- The more frequently things change, the more likely they will change again at the same rate.

### The Importance of Practicing

Identifying areas of volatility is an **acquired skill**. Hardly any architect is initially trained in VBD, and the vast majority use functional decomposition. The best way to master VBD is to practice:

- Practice on everyday software systems you are familiar with (insurance company, mobile app, bank, online store)
- Examine your own past projects -- what were the pain points? Was it functional decomposition? What would the volatility-based design look like?
- Practice on physical systems (house, car, airplane) -- the principles are universal
- Study existing well-designed systems and identify their encapsulated volatilities

## Red Flags / Anti-Patterns

1. Services named after business operations (InvoicingService, BillingService, BuyingStocks)
2. Client orchestrating multiple functional services
3. Services that know about call ordering (what comes before/after them)
4. Services chaining to each other with error compensation callbacks
5. Multiple points of entry to the system
6. Changes to one requirement requiring changes across multiple services
7. God services that are grab bags of related functionality
8. Explosion of tiny services each handling a narrow functional variation
9. Direct 1:1 mapping from requirements list to service list
10. Business logic residing in the client
11. Difficulty switching clients (web to mobile) due to embedded logic
12. Cross-cutting concern changes (notifications, storage) requiring changes to all services
