# PONZIRAMID (PONZIRAM)

A fixed-supply ERC-20 token for an IdentityMD custom-token launch on Ethereum (chain id 1).

| Property        | Value                                                    |
| --------------- | -------------------------------------------------------- |
| Contract        | `PonziramidToken` (`src/PonziramidToken.sol`)            |
| Name            | `PONZIRAMID`                                             |
| Symbol          | `PONZIRAM`                                               |
| Decimals        | 18                                                       |
| Total supply    | 1,000,000,000 tokens = `1000000000000000000000000000` minor units |
| Constructor     | no arguments                                             |
| Minted to       | `msg.sender` of the constructor, once                    |
| Compiler        | solc 0.8.26, optimizer on (200 runs), `bytecode_hash = "none"` |

## Behaviour

- The constructor credits the whole supply to the deployer and emits a single `Transfer(0x0, deployer, supply)`.
- `totalSupply()` is a constant. There is no `mint`, no `burn`, no owner, no pause, no blocklist, no fee on
  transfer, no upgrade path, no `delegatecall` and no `selfdestruct`.
- `transfer`, `approve` and `transferFrom` behave as in OpenZeppelin's ERC20 v5: failures revert with
  ERC-6093 custom errors instead of returning `false`; a `type(uint256).max` allowance is unlimited and is
  not decremented; transfers to the zero address are refused; `approve` sets the allowance to exactly
  the value given.
- Every transfer moves exactly the amount requested, so the launch flows (factory to distributor, seed
  into the Uniswap v4 pool, claims, swaps) arrive whole without any exemption list.
- The contract refuses ETH (no `receive` or `fallback`).

## Launch parameters (decided by the launch, not open questions)

- Chain: Ethereum mainnet, chain id 1.
- Deployer: IdentityMD's `ProjectFactory.launchCustom`, which runs the constructor and therefore receives the
  supply. The factory then forwards 10% to the launch's MerkleDistributor, seeds the pool with 88%
  (`poolBps = 8800`) at an opening cap of 2,500 IMD (`initialMarketCapWei = 2500000000000000000000`), and sends
  the remaining 2% to `0x8308f73729e457eca1134a5c65aa3825ab79921c` (`remainderTo`).
- Pool: paired with IMD (`0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`), fee 12500 (1.25%), tick spacing 60.
- `launch.json` is written by the manifest step after acceptance. For reference, its token entry is
  `contract: "PonziramidToken"`, `name: "PONZIRAMID"`, `symbol: "PONZIRAM"`, `decimals: 18`,
  `constructorArgs: []`, `totalSupply: "1000000000000000000000000000"`, with no application contracts.

## Assumptions

- "The deployer" in the brief is whoever runs the constructor. In the launch that is the factory, which is
  what the admission floor requires (supply minted to `msg.sender`, held whole by the factory after every
  constructor). No address is hard-coded.
- No constants were left open by the brief: name, symbol, supply and decimals are all given. Nothing in
  this token is a fee, tax or price, so nothing was chosen on the requester's behalf.
- The token does not implement EIP-2612 `permit`. Approvals are on-chain `approve` calls only.

## After launch

There is nothing for the owner to set: the contract has no owner and no settable storage. Operational
responsibilities that remain:

- **Explorer verification.** Verify `src/PonziramidToken.sol` on Etherscan with the pinned settings
  (solc 0.8.26, optimizer 200 runs, EVM `cancun`, metadata hash none) once the launch has deployed it.
  This belongs to the network's deployer, not to this task.
- **Allowance hygiene.** Holders changing a non-zero allowance should set it to zero first, as with any
  standard ERC-20 `approve`.
- **Burning.** There is no burn function. A holder who wants to destroy tokens can only send them to an
  address nobody controls; `totalSupply()` will not change.
- **Independent review.** Tests passing are not an audit. A separate adversarial review is expected before
  release, as for any launch.

## Repository layout

```
foundry.toml             compiler pins and build settings (bytecode_hash = "none", no ffi, no fs access)
remappings.txt           forge-std/ -> lib/forge-std/src/
src/PonziramidToken.sol  the token
test/PonziramidToken.t.sol
lib/forge-std/           forge-std v1.11.0, vendored as ordinary files (MIT / Apache-2.0)
```

## Build and test

```
forge build
forge test
forge fmt --check
```

The verifier runs fuzz tests with `FOUNDRY_FUZZ_SEED=0xff5bc2aa190753db7072e9b0be9ff7502652ed7bf35d294d799b7d4c972fbe98`;
the suite passes with that seed. Tests read no environment variables and do not depend on the calling address.

## Security notes

Checked against the eth-security reference supplied with the task: no reentrancy surface (no external
calls), no unchecked arithmetic that can wrap (the two `unchecked` blocks are guarded by the preceding
balance and allowance checks), no `tx.origin`, no `delegatecall`, no `selfdestruct`, no proxy, no owner,
no oracle or randomness. Slither and Mythril were not run; they are not provided on this machine.
