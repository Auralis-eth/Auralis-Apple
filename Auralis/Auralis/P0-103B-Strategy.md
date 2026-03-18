# P0-103B Strategy: Query parser + type detection

## Status

Partially blocked

## Ticket

Implement deterministic search query classification for ENS, addresses, contracts, token symbols, names, and collections with inline detection feedback.

## Dependencies

Pure parsing can start independently. Local index enrichment can layer in later from P0-451 and P0-461.

## Strategy

- Start with pure parsing and classification first.
- Keep the parser deterministic and local.
- Layer Music and Token index enrichment later instead of waiting for it up front.

## Key Risk

Mixed input, ENS-like invalid strings, ambiguous addresses, and very short token symbols must produce deterministic, non-misleading behavior even before local index enrichment lands.

## Definition Of Done

- Core parsing and type detection work without depending on every downstream data source.
- Later local enrichment can plug in without changing the basic classification model.

## Validation Target

Verify ENS detection, address detection, token lookup matches, and invalid address rejection without network calls or receipts.
