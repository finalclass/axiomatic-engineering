# Design "Don'ts" (Ch. 3 - Structure)

Red flags indicating functional decomposition or architectural violations. If you do any of these, treat it as a warning sign and investigate what you are missing.

## Call-Flow Violations

### Clients must not call multiple Managers in the same use case
- Doing so tightly couples Managers -- they no longer represent separate families of use cases, separate subsystems, or separate slices
- Chained Manager calls from the Client indicate functional decomposition: the Client is stitching together underlying functionalities
- Clients CAN call multiple Managers but NOT in the same use case (e.g., Client calls Manager A for use case 1, then Manager B for use case 2)

### Clients must not call Engines
- The only entry points to the business layer are the Managers
- Managers represent the system; Engines are an internal layer implementation detail
- If Clients call Engines, use case sequencing and associated volatility migrates to the Clients, polluting them with business logic
- Calls from Clients to Engines are the hallmark of functional decomposition

### Managers must not queue calls to more than one Manager in the same use case
- If two Managers receive a queued call, why not a third? Why not all of them?
- The need for multiple Managers to respond to a queued call is a strong indication you should use a Pub/Sub Utility service instead

### Engines must not receive queued calls
- Engines are utilitarian and exist to execute a volatile activity for a Manager
- They have no independent meaning on their own
- A queued call, by definition, executes independently from anything else in the system
- Performing just the activity of an Engine, disconnected from any use case or other activities, does not make any business sense

### ResourceAccess services must not receive queued calls
- Similar to the Engines guideline
- ResourceAccess services exist to service a Manager or an Engine and have no meaning on their own
- Accessing a Resource independently from anything else in the system does not make any business sense

### Engines never call each other
- Not only does this violate the closed architecture principle, it also does not make sense in a volatility-based decomposition
- The Engine should have already encapsulated everything to do with that activity
- Any Engine-to-Engine calls indicate functional decomposition

### ResourceAccess services never call each other
- If ResourceAccess services encapsulate the volatility of an atomic business verb, one atomic verb cannot require another
- Similar to the rule that Engines should not call each other
- Note: a 1:1 mapping between ResourceAccess and Resources is NOT required
- Often two or more Resources logically must be joined together to implement some atomic business verbs
- A single ResourceAccess service should perform the join rather than making inter-ResourceAccess calls

## Event/Pub-Sub Violations

### Clients must not publish events
- Events represent changes to the state of the system about which Clients (or Managers) may want to know
- A Client has no need to notify itself (or other Clients)
- Knowledge of the internals of the system is often required to detect the need to publish an event -- knowledge that the Clients should not have
- However, with functional decomposition the Client IS the system and needs to publish events

### Engines must not publish events
- Publishing an event requires noticing and responding to a change in the system
- This is typically a step in a use case executed by the Manager
- An Engine performing an activity has no way of knowing much about the context of the activity or the state of the use case

### ResourceAccess services must not publish events
- ResourceAccess services have no way of knowing the significance of the state of the Resource to the system
- Any such knowledge or responding behavior should reside in Managers

### Resources must not publish events
- The need for the Resource to publish events is often the result of a tightly coupled functional decomposition
- Similar to the case for ResourceAccess -- business logic of this kind should reside in Managers
- As a Manager modifies the state of the system, the Manager should also publish the appropriate events

### Engines, ResourceAccess, and Resources must not subscribe to events
- Processing an event is almost always the start of some use case, so it must be done in a Client or a Manager
- The Client may inform a user about the event, and the Manager may execute some back-end behavior
