# P0-103B Strategy: Query parser + type detection

## Status

Completed

## Ticket

Implement deterministic search query classification for ENS, addresses, contracts, token symbols, names, and collections with inline detection feedback.

## Outcome

- Replaced the Search placeholder with a real search surface that shows inline type detection feedback in the app shell.
- Added a deterministic local parser for ENS names, address-like input, contracts, token symbols, NFT names, collections, and generic text fallback.
- Built a local search index from the active wallet scope plus saved accounts so classification stays side-effect free and ready for the later resolution pipeline.
- Added focused parser coverage for ENS, address, symbol, name, collection, and scope-index construction behavior.

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

## Validation Result

- `BuildProject` passed on the `Auralis` scheme.
- File-level diagnostics were clean for the parser, search view, and tests.
- Runtime sanity checks passed through `ExecuteSnippet` for ENS, wallet, contract, symbol, collection, and invalid-address cases.
- The environment test runner timed out repeatedly, so build-clean plus parser snippet validation is the verified baseline here.
