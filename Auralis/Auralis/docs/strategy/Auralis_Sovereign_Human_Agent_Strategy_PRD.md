# Auralis: Sovereign Human Agent Strategy & Product Requirements

**Project:** Next Gen OS / Auralis
**Document Type:** Strategy + Product Requirements Document
**Status:** Working source of truth
**Date:** September 29, 2026

---

## 1. Executive Summary

Auralis should not compete to become another general-purpose AI assistant.

The general assistant layer is rapidly commoditizing. Frontier model providers and large consumer platforms will continue to make voice, browser use, email triage, scheduling, shopping, travel booking, computer control, memory, and basic proactivity cheaper and more capable. These capabilities should be treated as interchangeable infrastructure that Auralis can consume rather than as the core product Auralis must own.

Auralis should instead become the **sovereign representation of a human in an agentic world**.

Its job is to maintain the durable context that should remain stable even when models, devices, interfaces, services, and specialized agents change:

- identity
- family and household context
- values and priorities
- goals and obligations
- financial constraints
- assets and ownership
- relationships
- permissions and delegated authority
- memory and history
- preferences
- policies
- receipts and provenance
- economic agency

The core product promise is not simply **"AI that does things for you."**

It is:

> **A system that understands what matters to you, protects your interests, gives software only the authority it has earned, and represents you across the agentic economy without requiring a platform to own your digital life.**

The immediate product should make this philosophy useful through concrete household problems. The long-term architecture should make the human—not a model provider, marketplace, advertiser, app, or agent—the durable center of the system.

---

## 2. Product Thesis

### 2.1 The market is solving execution

The emerging agent ecosystem is becoming increasingly good at answering:

- How do I book this?
- How do I send this?
- How do I buy this?
- How do I complete this form?
- How do I find this information?
- How do I operate this website?

These are execution problems.

Execution will remain important, but it is unlikely to be a durable moat by itself. Models improve. Browser automation becomes cheaper. Connectors proliferate. Voice becomes standard. Specialized tools become callable commodities.

### 2.2 The unsolved problem is representation

Before execution, a much harder set of questions exists:

- Should this happen at all?
- Is this consistent with the user's priorities?
- Can the household afford it?
- Which competing obligation matters more?
- What authority has this agent been granted?
- What risk level is acceptable in this domain?
- What should happen automatically and what requires approval?
- Which identity, funds, credentials, or relationships may be used?
- Who benefits from the recommendation?
- Can the action be explained and audited later?
- Can the user revoke the authority without losing their digital life?

Auralis should own this layer.

### 2.3 Durable hierarchy

Auralis should assume the following hierarchy:

**Human / household**
↓
**Identity, values, policy, context, ownership, authority**
↓
**Auralis runtime**
↓
**Agents and specialized services**
↓
**Models, browsers, APIs, apps, protocols, blockchains, devices**

Models are replaceable components. The human representation is the durable asset.

---

## 3. Vision

Auralis becomes the personal operating substrate through which a person or family participates in an agentic economy.

A user should eventually be able to change:

- model provider
- assistant personality
- device
- interface
- specialized agent
- financial provider
- marketplace
- communication surface

without losing the accumulated representation of who they are and how their world should operate.

The user's agentic identity should feel less like an account inside a product and more like a portable digital extension of the person.

### Long-term vision statement

> **Every person should be able to have capable autonomous software acting in their interest without surrendering ownership of their identity, context, relationships, assets, or agency to the company providing the intelligence.**

---

## 4. Strategic Position

Auralis should not define itself as:

- a ChatGPT competitor
- a Muse competitor
- a general chatbot
- a browser agent
- a shopping bot
- a finance dashboard
- a crypto wallet with AI
- a single-purpose productivity assistant

Auralis should be the layer that coordinates and governs all of those capabilities around a persistent human.

### 4.1 What Auralis owns

Auralis should seek durable ownership of:

1. **Human context** — a longitudinal model of the person and household.
2. **Policy** — explicit rules for how software may act.
3. **Authority** — who or what is permitted to do what.
4. **Memory** — useful history that survives replacement of individual agents.
5. **Receipts** — evidence of decisions, actions, inputs, outputs, and provenance.
6. **Identity** — portable identity and credentials for human and agent actors.
7. **Economic agency** — the ability to act, negotiate, transact, and receive value on behalf of the human.
8. **Coordination** — orchestration across models, agents, devices, services, family members, and eventually peer agents.

### 4.2 What Auralis should rent or integrate

Auralis should assume it can replace or swap:

- LLM inference
- search
- computer use
- browser automation
- speech recognition
- speech generation
- maps
- travel inventory
- email providers
- calendars
- payment rails
- commerce marketplaces
- specialized vertical agents

These are capabilities, not identity.

---

## 5. Primary User

The initial user should not be optimized around an affluent technology enthusiast seeking another productivity tool.

The first useful Auralis experience should serve an ordinary household carrying meaningful cognitive, financial, and administrative load.

### Characteristics

The target household may:

- live around a monthly budget rather than unlimited discretionary spending
- have children or dependents
- manage recurring bills, insurance, groceries, appointments, school or childcare, transportation, household maintenance, and government paperwork
- routinely make tradeoffs between today's wants and future obligations
- lack a human executive assistant, accountant, concierge, family office, or personal operations staff
- have information fragmented across financial institutions, calendars, messages, email, documents, apps, and family members
- benefit from help but not want another system requiring constant management

### Core user truth

Wealthy households can purchase people who continuously protect their interests.

Ordinary households largely receive software that records what happened after the fact.

Auralis should progressively provide ordinary people with the kind of **protective, anticipatory, coordinated support historically available only through human staff.**

---

## 6. Jobs to Be Done

Auralis should optimize around these jobs rather than around generic AI capability.

### 6.1 Protect my household

- notice financial leakage
- identify preventable fees
- track credits and refunds
- catch duplicate or unnecessary expenses
- warn when a purchase conflicts with near-term obligations
- identify expiring benefits or entitlements
- surface changes in recurring bills
- prepare negotiation or cancellation actions

### 6.2 Reduce bureaucratic load

- understand forms and requirements
- gather required information
- prepare submissions
- track deadlines
- maintain supporting records
- detect incomplete obligations
- follow up when a response is missing

### 6.3 Coordinate family life

- merge household schedules and obligations
- plan weekends and activities
- coordinate meals and groceries
- account for budget, weather, location, age, preferences, energy, and time
- help parents create personalized experiences for children
- maintain useful family context without requiring repeated explanation

### 6.4 Help me make better decisions, not merely execute requests

When asked to perform an action, Auralis should consider:

- affordability
- timing
- stated priorities
- existing commitments
- policies
- opportunity cost
- household impact
- confidence
- reversibility

The system should be capable of saying, in effect:

> "I can do this, but it conflicts with another thing you told me matters more. Here is the tradeoff."

This must not become paternalistic control. The user remains sovereign and can override the system.

### 6.5 Represent me to other agents

Over time:

- discover counterpart agents
- negotiate requests
- exchange credentials
- make offers
- obtain quotes
- transact within authorized limits
- preserve receipts
- establish reputation
- revoke relationships

---

## 7. Core Product Principles

### 7.1 The human is the principal

Every agent is subordinate to the person or household it represents.

Auralis does not attempt to become the authority over the user. It helps the user encode, exercise, and revise their own authority.

### 7.2 Alignment over engagement

Success should not be measured by maximum time in app, prompts sent, notifications opened, purchases made, or transactions generated.

The ideal successful action may produce **zero screen time**.

### 7.3 Protect before optimizing

The system should first prevent avoidable harm, waste, forgotten obligations, and conflicts before optimizing convenience.

### 7.4 Proactivity must be earned

Proactivity is powerful only when paired with explicit authority boundaries and confidence.

The product should never assume that being technically capable of an action means it is authorized to perform it.

### 7.5 Context and authority are earned progressively

Auralis should not begin by asking the user to surrender a complete model of their life. It should earn deeper context by solving a concrete problem first.

The preferred adoption loop is:

**tangible help → trust → additional context → better judgment → delegated authority → larger tangible help**

Context and authority are related but distinct. Learning a fact about the household does not automatically grant permission to act on it. Each new connection, data source, capability, and autonomous permission should be justified by a visible user benefit.

This creates a model of **progressive sovereignty**:

1. Auralis solves something useful with minimal access.
2. It explains what additional context would improve the next outcome.
3. The user chooses whether to grant that context.
4. Auralis proves reliable at recommendation and preparation.
5. The user may then delegate narrowly scoped authority.
6. Authority remains revocable without destroying the user's accumulated identity or history.

### 7.6 Explainability at the decision boundary

Users should not need explanations for every trivial background action.

But when an action materially affects money, commitments, identity, relationships, health, legal status, or reputation, Auralis should be able to explain:

- why the action was considered
- which policy authorized it
- which information influenced it
- what was actually done
- what can be reversed

### 7.7 Portability over lock-in

The architecture should favor user portability of:

- identity
- permissions
- policies
- memories
- receipts
- preferences
- credentials
- relationship state

### 7.8 Interfaces are situational

Auralis does not require one permanent UI.

The appropriate surface may be:

- voice
- generated UI
- notification
- family dashboard
- messaging
- ambient audio
- background automation
- an external specialized application

The system should generate or select the minimum interface required for the decision at hand.

---

## 8. Constitutional Agency: Authority Model

Proactivity should be implemented as a policy system rather than as a personality trait.

### 8.1 Authority ladder

Each capability should be assignable an authority level.

#### Level 0 — Observe
The agent may read approved information and build context, but cannot change external state.

#### Level 1 — Surface
The agent may identify an issue or opportunity and notify the user.

#### Level 2 — Recommend
The agent may propose an action and explain why.

#### Level 3 — Prepare
The agent may draft, assemble, calculate, prefill, negotiate provisionally, or stage an action without committing it.

#### Level 4 — Ask and Execute
The agent may prepare the action, obtain explicit approval, then execute it.

#### Level 5 — Autonomous Within Policy
The agent may execute without case-by-case approval when policy, confidence, amount, domain, counterparty, and reversibility constraints are satisfied.

### 8.2 Authority must be domain-specific

A user may allow very different autonomy for different actions.

Examples:

- retrieve a $12 travel credit: Level 5
- cancel a duplicate $8 subscription: Level 5 if cancellation is reversible
- transfer $50 between owned accounts: Level 5 under explicit financial policy
- spend $300: Level 4
- change insurance provider: Level 4
- send an emotionally sensitive family message: Level 3 or 4
- terminate a relationship or make a major legal commitment: explicit confirmation required

### 8.3 Policy dimensions

Policies should eventually support:

- capability
- actor / agent
- domain
- account / asset
- counterparty
- amount
- frequency
- time window
- confidence threshold
- reversibility
- geographic constraints
- household member
- purpose
- expiry
- escalation path

### 8.4 Receipts

Every material autonomous action should produce a receipt containing, as appropriate:

- initiating intent or trigger
- acting agent identity
- delegated authority
- policy decision
- inputs used
- external systems contacted
- transactions or state changes
- result
- confidence
- timestamp
- reversible/irreversible status
- evidence or external confirmation

Receipts should make autonomy inspectable without requiring users to supervise every action live.

---

## 9. The Initial Product Wedge

The largest strategic risk is building an elegant operating system with no indispensable daily value.

Auralis therefore needs a narrow, visible wedge that exercises the deeper architecture.

### Recommended wedge: Household Advocate / Digital Family Office

The first Auralis experience should continuously help the household avoid waste, recover value, manage obligations, coordinate family life, and make better tradeoffs.

The wedge should not be sold as sovereignty, agent infrastructure, or an AI operating system. It should be sold through immediate outcomes a household can recognize:

- money recovered or protected
- bills reduced
- forgotten obligations handled
- administrative work removed
- family logistics reconciled
- bad tradeoffs surfaced before they become expensive

The first question is:

> **"Where can my household be better protected this week?"**

The strategic objective beneath that simple experience is to convert **consumer inattention into consumer agency**. Many incumbent business models benefit from friction, confusion, inertia, fragmented information, or the user's lack of time. Auralis should systematically remove those disadvantages while remaining aligned to the household rather than to a merchant, advertiser, marketplace, or transaction fee.

### Initial capability set

1. **Household context**
   - people
   - recurring obligations
   - broad goals
   - preferences
   - budget constraints

2. **Financial awareness**
   - recurring charges
   - upcoming bills
   - available balances or user-supplied budget state
   - refundable/credit opportunities

3. **Household planning**
   - calendar context
   - weekend activity planning
   - meal / grocery coordination
   - simple family logistics

4. **Opportunity detection**
   - unnecessary subscription
   - changed bill
   - expiring credit
   - possible refund
   - upcoming administrative deadline
   - purchase conflicting with short-term obligation

5. **Progressive action**
   - initially surface or prepare
   - later request approval and execute
   - eventually autonomously handle low-risk, explicitly authorized workflows

### Adoption flywheel

The Household Advocate should deliberately create a context-and-trust flywheel:

1. **Deliver one measurable win.** Find a refund, reduce a recurring cost, reconcile a family obligation, or prevent an avoidable mistake.
2. **Ask for the next connection only when useful.** Example: "I can watch for this automatically if you connect the account that contains these bills."
3. **Reuse context visibly.** The next recommendation should be better because Auralis remembers the household's actual priorities and constraints.
4. **Earn delegated authority.** After repeated successful recommendations, the user can authorize bounded autonomous work.
5. **Compound household understanding.** Each successful domain makes adjacent domains more useful without forcing the user to rebuild context.

This flywheel is strategically critical because the durable advantage is not a single automation. It is the user's growing confidence that Auralis understands enough of their life to make the next decision better.

### Why this wedge

It provides immediate human value while forcing Auralis to build its differentiated primitives:

- memory
- context
- policy
- authority
- receipts
- capabilities
- scheduling
- artifacts
- agent identity

The wedge is therefore both a product and a proving ground for the operating system.

---

## 10. Family Operating System Expansion

The existing parent/child ideas should not be treated as disconnected applications.

They can become different manifestations of the same household context.

Examples:

### Child experiences
- personalized stories
- generated illustrations
- learning activities
- rainy-day activities
- bedtime routines

### Parent support
- weekend activity suggestions
- at-home activity planning
- meal planning
- family calendar orchestration
- packing and trip preparation
- household reminders

### Household administration
- bills
- benefits
- insurance
- receipts
- appointments
- maintenance
- documents
- recurring purchases

A single family context graph can make each experience progressively better.

The product should avoid becoming a monolithic app containing dozens of fixed tabs. Auralis should instead surface the relevant experience dynamically.

---

## 11. Generative UI Strategy

Auralis should assume that fixed application navigation becomes less important over time.

The system should select or generate an interface based on the task.

### Examples

A spoken question may require only a spoken answer.

A weekend planning request may generate a temporary visual itinerary with:

- activities
- timing
- weather
- driving distance
- budget
- child suitability

A financial tradeoff may generate a temporary comparison surface.

A pending autonomous action may generate an approval card.

A receipt may generate an audit view.

### Principle

> **No permanent UI unless the information itself is persistent.**

Persistent concepts such as identity, household members, policies, assets, permissions, and history may deserve durable views. Task-specific workflows should increasingly be generated on demand.

---

## 12. Architecture Implications

The current Auralis package direction aligns well with this strategy if each package is tied to a clear system responsibility.

### Runtime
Coordinates agents, capabilities, policy checks, execution, and lifecycle.

### Memory
Stores durable user-approved context and learned preferences.

### Context
Builds task-specific context from durable memory, live state, and relevant artifacts.

### Mission Control
Provides inspection, intervention, authority management, and system awareness.

### Receipts
Records material decisions and external actions.

### Artifacts
Stores durable outputs, supporting evidence, plans, documents, and generated objects.

### Scheduling
Triggers future and recurring work.

### Policy
Decides whether an attempted action is permitted and what level of confirmation is required.

### Capabilities
Provides swappable access to external actions and information.

### Agent Identity
Identifies the human principal, delegated agents, counterpart agents, and authority relationships.

### Provider Layer
Keeps model providers replaceable.

### Crypto / Wallet Layer
Should provide economic and cryptographic primitives where they materially improve portability, identity, authorization, ownership, payment, credentials, or peer coordination. It should not be exposed merely to make the product appear decentralized.

---

## 13. Agent-to-Agent Future

Auralis should be architected for a world in which humans are increasingly represented by software agents interacting with other agents.

A future interaction may resemble:

1. Auralis detects a household need.
2. Policy permits discovery but not commitment.
3. Auralis contacts qualified provider agents.
4. Provider agents return structured offers.
5. Auralis evaluates offers against household policy and context.
6. Auralis negotiates within authorized boundaries.
7. The user approves only if the action exceeds autonomous authority.
8. Credentials or payment authorization are exchanged.
9. The service is performed.
10. Both parties receive signed or verifiable receipts.
11. Reputation/context is updated.

### Required long-term primitives

- human and agent identity
- discoverable capabilities
- delegation
- signed authority
- verifiable credentials
- negotiation
- payments
- escrow where needed
- receipts
- reputation
- revocation
- dispute evidence

Auralis does not need to invent every protocol. It should remain protocol-capable and avoid architectures that assume all interactions pass through a single centralized platform.

---

## 14. Economic Alignment

Auralis should be structurally aligned with the user.

### Avoid

Business models that reward:

- maximizing purchases
- maximizing advertising exposure
- maximizing engagement
- steering toward higher-margin merchants without user benefit
- selling preferential recommendation placement without explicit disclosure
- locking user context into Auralis

### Preferred economic direction

Long-term monetization should be compatible with outcomes in which users:

- spend less
- choose not to purchase
- switch providers
- avoid fees
- obtain refunds
- use independent merchants
- spend less time interacting with Auralis

Potential models may include subscriptions, user-approved outcome sharing, paid specialized capabilities, or network services whose incentives remain transparent.

The exact business model is intentionally unresolved, but **consumer alignment is a product requirement, not merely brand language.**

---

## 15. Competitive Strategy Without Building Around Competitors

Auralis should assume that large platforms will become excellent at generic assistant capabilities.

The response is not feature parity.

The response is architectural independence.

### Strategic rule

When an external platform launches a new capability, ask:

> **Can this become another capability behind Auralis while the user's identity, context, authority, and history remain ours/theirs?**

If yes, the launch may strengthen Auralis by improving a replaceable underlying component.

Only capabilities that threaten the durable human representation layer require strategic escalation.

---

## 16. True Threat Model

### Threat 1 — A dominant assistant completes the context-and-trust flywheel first

This is the primary strategic threat.

The danger is not that another assistant can cancel subscriptions, book travel, or call customer support. The danger is that repeated useful actions teach users to think, **"this system knows me"**, causing them to grant more context, more connections, and more ongoing responsibility until that platform becomes the canonical representation of the human.

If another platform becomes the durable owner of:

- identity
- memory
- values
- relationships
- financial model
- permissions
- life history
- credentials
- economic agency

then Auralis loses its most important layer.

**Response:** prioritize portable identity, context, policy, and memory earlier than convenience features would otherwise justify.

### Threat 2 — The device OS becomes the sovereign agent runtime

A device platform already possesses identity, secure hardware, payments, permissions, messaging, location, applications, and private local data.

A truly capable device-native personal agent runtime could overlap heavily with Auralis.

**Response:** architect Auralis to interoperate with the OS while preserving portable context and identity beyond one device vendor.

### Threat 3 — Agent protocols and agent commerce consolidate into closed ecosystems

If identity, payments, delegation, discovery, merchant access, or agent-to-agent communication become controlled by a few proprietary networks, Auralis could be reduced to an application inside someone else's system.

This includes the risk that businesses integrate directly with one dominant assistant rather than exposing portable agent capabilities. A closed assistant-to-merchant network can become the new app store: the assistant controls discovery, transaction routing, identity, and economic access.

**Response:** support open and portable standards early; maintain adapters; participate in cryptographic identity and authorization ecosystems where appropriate; prefer merchant capabilities that can be invoked by any authorized agent rather than only one platform.

### Threat 4 — Auralis never finds an indispensable wedge

This is the most immediate execution risk.

Architecture without habitual value creates no compounding context, trust, distribution, or learning.

**Response:** ship concrete household value early and use it to earn deeper permissions over time.

### Threat 5 — Trust is lost through premature autonomy

One serious unauthorized or socially inappropriate action can damage the user's willingness to delegate future authority.

**Response:** constitutional agency, receipts, reversible actions, staged autonomy, and domain-specific policies must be first-class product behavior.

---

## 17. Non-Threats / Things We Should Not Chase Reactively

Auralis should not restructure its roadmap merely because another product adds:

- flight check-in
- restaurant booking
- email triage
- browser automation
- full-duplex voice
- an AI wearable
- an animated assistant character
- a new messaging surface
- a specific commerce connector

These can matter tactically, but they are capabilities rather than durable strategic ownership.

The correct response is usually integration, not duplication.

---

## 18. Product Requirements

### P0 — Required foundation

#### Human / Household Model
The system must represent multiple people and their relationships without collapsing the household into one undifferentiated user.

#### Durable Memory
The system must distinguish durable user context from temporary task context.

#### Policy Engine
Any external side effect must be capable of passing through explicit policy evaluation.

#### Capability Boundary
Agents must invoke external systems through declared capabilities rather than unrestricted hidden access.

#### Receipt Generation
Material external actions must generate durable receipts.

#### Provider Independence
Core human context must not be encoded in a way that requires one model provider.

#### User Override
The user must be able to override recommendations and modify policies.

#### Revocation
Delegated authority must be revocable.

### P1 — Household Advocate

- ingest or accept household obligations
- detect upcoming commitments
- detect recurring financial patterns
- surface opportunities to save or recover money
- reason about short-term financial conflicts
- prepare actions
- request approval where required
- track outcomes
- learn from approved/rejected recommendations

### P1 — Family Planning

- weekend activity generation
- at-home activity generation
- calendar-aware suggestions
- budget-aware suggestions
- age/preferences-aware suggestions
- generated temporary UI for multi-option decisions

### P1 — Parent / Child Experience

- personalized story generation
- image generation
- durable child-safe preference/context model
- reuse household context where appropriate

### P2 — Autonomous Low-Risk Work

- configurable Level 5 authority
- value thresholds
- confidence thresholds
- reversible-action preference
- autonomous follow-up
- periodic summaries of completed work

### P2 — Agent Network

- agent identity
- capability discovery
- delegated authority representation
- structured offers
- negotiation boundaries
- signed receipts

---

## 19. Trust and Safety Requirements

Auralis' concept of safety should primarily be expressed through user sovereignty and bounded authority.

### Required behavior

The system must:

- distinguish recommendation from authorization
- treat irreversible actions differently from reversible actions
- understand amount/risk thresholds
- require stronger authority for sensitive domains
- expose meaningful external actions after execution
- avoid silently expanding permissions
- allow users to inspect why autonomy was granted
- prevent one agent from delegating more authority than it possesses
- maintain provenance for sensitive context

### Principle

> **The agent should never gain authority merely because it has gained capability.**

---

## 20. Metrics

Traditional engagement metrics can conflict with the product philosophy.

### Primary metrics

#### Household Value Protected
Estimated money recovered, saved, prevented from leaking, or preserved through better timing/decisions.

#### Administrative Burden Removed
Meaningful household tasks completed or substantially prepared without manual workflow management.

#### Trusted Autonomy Rate
Percentage of eligible actions users intentionally allow Auralis to perform autonomously.

#### Recommendation Acceptance
How often users agree that detected opportunities or conflicts were useful.

#### Reversal / Regret Rate
How often users undo, dispute, or express regret over actions taken autonomously.

This should remain extremely low.

#### Context Reuse
How often previously accumulated context improves a new domain without requiring the user to repeat information.

#### Time-to-Useful-Action
How quickly a new user experiences concrete value rather than merely completes setup.

### Anti-metrics

Auralis should not optimize for:

- screen time
- prompt count
- notification count
- purchase volume
- maximum number of autonomous actions

---

## 21. Roadmap

### Phase 1 — Establish the Principal

Goal: create the durable representation of the human/household.

Build:

- household identity model
- memory
- context assembly
- policy foundation
- capability registry
- receipts
- artifacts
- scheduling
- provider abstraction

Success condition:

The system can answer **who it represents, what it knows, what it is allowed to do, and why an action occurred.**

### Phase 2 — Household Advocate

Goal: produce recurring measurable value and begin the context-and-trust flywheel.

Build:

- household obligations
- financial opportunities
- recurring-cost awareness
- refund / credit opportunities
- deadline detection
- recommendation/preparation workflows
- approval surfaces
- just-in-time account and data connections
- explicit explanations of why additional context would improve an outcome

Success condition:

Users can point to concrete money, effort, or obligations Auralis protected, and voluntarily grant additional context because prior value made the benefit obvious.

### Phase 3 — Family OS

Goal: broaden from protection into everyday coordination.

Build:

- family planning
- meals/groceries
- activities
- parent/child experiences
- trip preparation
- contextual generative UI

Success condition:

Different family experiences clearly benefit from the same accumulated context.

### Phase 4 — Earned Autonomy

Goal: make the best assistant increasingly invisible.

Build:

- policy editor / natural-language policy creation
- graded authority
- autonomous low-risk workflows
- periodic receipt digests
- escalation rules

Success condition:

Users intentionally delegate recurring categories of work and rarely need to reverse actions.

### Phase 5 — Portable Agent Identity

Goal: make the human representation survive changes in provider and interface.

Build:

- portable identity
- credentials
- delegation records
- interoperable agent identity
- export/import of user-owned context where safe and practical

Success condition:

A user can replace an underlying agent/model without rebuilding their digital self from zero.

### Phase 6 — Agent Economy

Goal: let Auralis represent the user to external agents and markets.

Build:

- agent discovery
- negotiation
- payments
- credentials
- contracts/commitments
- receipts
- reputation
- revocation and disputes

Success condition:

Auralis can safely complete multi-party economic workflows while retaining the human as principal.

---

## 22. Near-Term Engineering Guidance

Before adding a feature, ask:

1. Does this deepen our representation of the human or merely duplicate a generic assistant feature?
2. Does this create reusable context?
3. Does this test policy or authority?
4. Does this create a receipt-worthy external action?
5. Does it solve a concrete household pain?
6. Would we still want this capability if the underlying model provider changed tomorrow?
7. Can an external provider eventually supply this as a swappable capability instead?

### Favor work that compounds

Examples:

- policy semantics
- receipt format
- household context
- agent identity
- capability contracts
- memory boundaries
- authorization and revocation
- generative decision surfaces

### Avoid premature infrastructure

Do not build every future protocol, marketplace, identity standard, or economic mechanism before a real product workflow needs it.

The operating system should emerge through real household use, not through speculative completeness.

---

## 23. Product Narrative

The external explanation should remain simpler than the architecture.

### Today

> **Auralis helps your household protect its money, manage its obligations, and coordinate everyday life.**

### As autonomy grows

> **Auralis is an AI that understands your household and works in your interest—even when you aren't actively managing it.**

### Long-term

> **Auralis is your sovereign agent: the digital representation you own, carrying your context, authority, relationships, and economic agency across the services and agents you choose.**

The architecture can be radical while the user experience remains ordinary and useful.

---

## 24. Strategic Decisions From This PRD

1. **Do not attempt to win the generic assistant capability race.**
2. **Treat frontier models and computer-use systems as providers.**
3. **Prioritize the persistent human representation layer.**
4. **Use household advocacy as the initial product wedge.**
5. **Make family experiences share one context rather than becoming separate siloed apps.**
6. **Make proactivity a policy/authority problem, not a personality setting.**
7. **Require receipts for material autonomous work.**
8. **Build toward portable agent identity and user-owned context.**
9. **Use crypto only where it creates real improvements in ownership, authorization, credentials, payments, or peer coordination.**
10. **Prefer integration over reactive duplication when general assistant platforms launch new capabilities.**
11. **Judge strategic threats by whether they capture the canonical representation of the human—not by individual agent features.**
12. **Ship a useful wedge before completing the theoretical operating system.**

---

## 25. North Star

Auralis succeeds when the answer to this question is clear:

> **In a world filled with intelligent agents, who does the software ultimately work for?**

For Auralis, the answer must always be:

> **the human.**

Not the model company.
Not the marketplace.
Not the advertiser.
Not the device vendor.
Not Auralis itself.

The human remains the principal; Auralis exists to make that sovereignty operational.
