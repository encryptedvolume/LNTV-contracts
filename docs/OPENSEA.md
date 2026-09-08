# ERC721-C marketplace integration

The NFT inherits Limit Break's existing `ERC721C` implementation without modifying its source. The ranked auction, 100-token supply, allocations, timing, batch bidding and refund rules are unchanged. The old restriction requiring every transfer and approval to use `RoyaltyMarketplace` has been removed. That marketplace remains available as an optional royalty-paying venue.

## Required deployment sequence

1. Deploy and verify the auction/edition with `ROYALTY_BPS=1000` (10%). No public deployment is recorded in this repository yet; existing immutable editions cannot be upgraded.
2. From the **current payout wallet**, run the configuration script below. It atomically selects OpenSea's supported StrictAuthorizedTransferSecurityRegistry, copies its curated list, registers OpenSea SignedZone as an authorizer, includes the optional local marketplace, and sets security level **4**, which blocks ordinary direct wallet transfers. Before this configuration succeeds, minted NFTs cannot be transferred; bidding and NFT claims still work.
3. In **OpenSea Studio → Creator Earnings**, set **10%** and the current payout wallet, then enable enforced earnings. Confirm the collection is indexed as ERC721-C and that the royalty is enforced at checkout. The contract call cannot update OpenSea's off-chain collection settings.
4. Re-check the registry policy after Studio's transactions. If Studio replaced the policy/list, call `configureEnforcedTrading()` again to restore the intended strict profile and optional local-market entry. Recheck Studio earnings afterward. OpenSea setup can be performed before or after the on-chain call, but **both** the final on-chain policy and Studio enforcement must be verified before announcing trading.
5. Complete a public-testnet listing, buy, offer acceptance, and royalty-receipt check with OpenSea-generated fulfillment data. The local tests below do not replace this release check.

```bash
# Set EDITION_ADDRESS, CHAIN_ID and PAYOUT_WALLET to the verified deployed values.
# Use the payout wallet's keystore or hardware wallet, not necessarily the deployment signer.
node scripts/foundry.mjs forge script script/ConfigureTrading.s.sol:ConfigureTrading \
  --rpc-url "$RPC_URL" --account payout-wallet

# Broadcast the same reviewed configuration.
node scripts/foundry.mjs forge script script/ConfigureTrading.s.sol:ConfigureTrading \
  --rpc-url "$RPC_URL" --account payout-wallet --broadcast
```

After activation, run `REQUIRE_ENFORCED_TRADING=true .venv/bin/python scripts/check_deployment.py` with the expected deployment configuration and `AUCTION_ADDRESS`. This verifies level 4, SignedZone authorization and absence of unrestricted Seaport/conduit operators, as well as the local-market policy. It cannot verify Studio settings or every curated processor's implementation.

The script checks chain ID, collection owner, the immutable **1000 bps** rate and registry code. It never creates a replacement marketplace or deploys imitation OpenSea infrastructure on a public chain. Supported target chain IDs are 1 and 11155111; 31337 is reserved for local fixtures. The documented addresses must have code on the chosen public network; an address alone is not proof of deployment or Studio support.

| Existing infrastructure | Address |
|---|---|
| StrictAuthorizedTransferSecurityRegistry | `0xA000027A9B2802E1ddf7000061001e5c005A0000` |
| OpenSea SignedZone | `0x000056F7000000EcE9003ca63978907a00FFD100` |
| Seaport 1.6 | `0x0000000000000068F116a894984e2DB1123eB395` |

## Enforcement and supported marketplaces

ERC-2981 reports the rate and recipient; it does not enforce payment by itself. ERC721-C calls the configured validator on secondary transfers. For OpenSea, SignedZone authorizes transfers around a Seaport fill using signed fulfillment data attesting to the order's creator fees. An ordinary Seaport/conduit approval is insufficient to transfer an NFT. Use restricted orders and **SIP-7 substandard 8** fulfillment data supplied by OpenSea, as described in its integration specification. Never whitelist Seaport or its conduit as unrestricted operators to make a failing order work.

Other marketplaces are supported when their settlement contracts integrate with the configured enforcement registry or are trusted royalty-enforcing processors in its curated policy. A compatible venue may require its own collection/royalty configuration. Universal marketplace compatibility, bridges and arbitrary peer-to-peer gifts are not promised. The test for a second marketplace uses a deliberately identified fixture, not a claim that every named marketplace has been certified.

The configuration copies registry list 0; subsequent changes to that curated list do not automatically change this collection's copy. Calling `configureEnforcedTrading()` again creates a fresh copy. The edition owns the copied list, so the old payout wallet has no retained list-owner privilege after rotation. A creator-managed alternative list must separately have its ownership and contents reviewed, including when the payout wallet changes.

**Administration is trusted, as in the upstream standard.** The current payout wallet owns the creator-token controls and can change the validator, validator auto-approval and external registry policy. Selecting zero/no-code leaves transfers blocked by this edition; selecting a permissive nonzero validator or unsafe policy could weaken enforcement. **Version 4.0.1 removes implicit validator approval (F4-01).** `isApprovedForAll` reads only the holder-controlled OpenZeppelin approval mapping. The inherited `autoApproveTransfersFromValidator` getter and setter remain available for ABI compatibility, but their flag cannot grant transfer authority, even when true. Holders must explicitly approve any operator. This prevents the payout wallet from seizing NFTs by combining a validator swap with auto-approval; validator/policy choices can still weaken royalty enforcement and remain trusted administration. Only configure trusted royalty-aware operators. This release does not claim an immutable, administrator-proof royalty policy.

OpenSea authorization also relies on its signer service and configured creator earnings. Wallet/control sales, side payments, wrapper ownership and understated prices are outside the observable NFT transfer price. The underlying standard cannot enforce fees on those off-chain economic transfers.

## Wallet and metadata updates

`edition.owner()` and `royaltyInfo()` resolve the current `auction.payoutWallet()`. The existing proposal/acceptance flow moves contract administration and future ERC-2981 reporting together. There is no second independent owner and no NFT `transferOwnership` entry point. Use the auction's two-step payout flow.

After rotation, also update **OpenSea Studio/royalty-registry settings and other marketplaces**. Already signed external orders/authorizations may retain their original fee recipient until cancelled, invalidated or expired; changing ERC-2981 cannot rewrite signed consideration. Cancel/recreate affected listings and verify a new sale pays the new wallet. The optional local marketplace's royalty pool still follows the current wallet automatically.

`contractURI()` returns `<metadataURI>contract.json`. Publish collection-level JSON there alongside `<base><id>.json` and retain the off-chain reveal service. `setMetadataURI` emits ERC-4906 `BatchMetadataUpdate` and `ContractURIUpdated`. Ownership detection, token metadata and off-chain creator settings are distinct mechanisms.

## Verified locally / still required

Local integration tests use the **actual verified Seaport 1.6 and OpenSea conduit runtimes**, plus unmodified verified SignedZone and registry source. Test-only signing keys produce SIP-7 authorizations locally. They cover paid direct/conduit sales, missing/fake/expired/mismatched authorization, royalty removal, token substitution, replay, approval-only bypasses, cleared authorization, another compatible processor, listing invalidation and payout rotation.

No public deployment, real OpenSea API signature, Studio activation, live listing or production marketplace certification is claimed. The previous long audit and mutation jobs were cancelled at the creator's request. Current targeted evidence is in [the integration review](../audit/ERC721C-INTEGRATION-2026-09-08.md); a complete audit of the revised source remains separate work.

## Primary references

- [Limit Break Creator Token Standards](https://github.com/limitbreakinc/creator-token-standards/tree/980a63b33591d568b6e04b45f37deba05a55f787)
- [OpenSea creator fee enforcement](https://docs.opensea.io/docs/creator-fee-enforcement)
- [OpenSea creator earnings setup and supported marketplace limits](https://support.opensea.io/en/articles/8867026-how-do-i-set-creator-earnings-on-opensea)
- [OpenSea contract-level metadata](https://docs.opensea.io/docs/contract-level-metadata)
