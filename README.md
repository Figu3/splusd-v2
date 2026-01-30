# splUSD v2

ERC4626-compliant staking vault for plUSD on Plasma.

## Overview

splUSD v2 is a simplified staking mechanism where:
- Users deposit **plUSD** and receive **splUSD** shares
- Admin periodically donates yield from Midas vault
- Share value increases over time (auto-compounding)
- No lockups - instant deposits and withdrawals

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        splUSD v2 Flow                           │
└─────────────────────────────────────────────────────────────────┘

                    ┌─────────────────┐
                    │   Midas Vault   │  (Earns yield externally)
                    └────────┬────────┘
                             │
                             │ Admin withdraws yield periodically
                             ▼
┌─────────────────┐    ┌─────────────────┐
│  User deposits  │    │  Admin donates  │
│     plUSD       │    │   yield (plUSD) │
└────────┬────────┘    └────────┬────────┘
         │                      │
         ▼                      ▼
    ┌─────────────────────────────────────┐
    │         splUSD v2 Vault             │
    │           (ERC4626)                 │
    ├─────────────────────────────────────┤
    │  • deposit(plUSD) → mint splUSD     │
    │  • withdraw(plUSD) ← burn splUSD    │
    │  • donateYield(plUSD) → ↑ share val │
    └─────────────────────────────────────┘
```

## Contracts

| Contract | Description |
|----------|-------------|
| `SplUSDv2.sol` | Main ERC4626 vault contract |
| `ISplUSDv2.sol` | Interface for external integrations |

## Development

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)

### Build

```bash
forge build
```

### Test

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test file
forge test --match-path test/SplUSDv2.t.sol

# Run invariant tests
forge test --match-path test/SplUSDv2.invariant.t.sol

# Run fuzz tests
forge test --match-path test/SplUSDv2.fuzz.t.sol

# Run with coverage
forge coverage
```

### Deploy

1. Copy `.env.example` to `.env` and fill in values:
```bash
cp .env.example .env
```

2. Deploy to Plasma mainnet:
```bash
source .env
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url $PLASMA_RPC_URL \
  --broadcast \
  --verify
```

## Security Features

- **Inflation Attack Protection**: Initial seed deposit burned to `0xdead` prevents first depositor attacks
- **Minimal Code**: ~37 lines of custom code on top of battle-tested OpenZeppelin ERC4626
- **SafeERC20**: All token operations use SafeERC20 wrapper
- **No Admin Keys**: No pause, no ownership - fully immutable after deployment

## Key Functions

### User Functions

| Function | Description |
|----------|-------------|
| `deposit(assets, receiver)` | Deposit plUSD, receive splUSD shares |
| `withdraw(assets, receiver, owner)` | Withdraw plUSD by burning shares |
| `redeem(shares, receiver, owner)` | Redeem shares for plUSD |

### Yield Functions

| Function | Description |
|----------|-------------|
| `donateYield(amount)` | Anyone can inject yield to increase share value |

### View Functions

| Function | Description |
|----------|-------------|
| `totalAssets()` | Total plUSD in vault |
| `convertToShares(assets)` | Preview plUSD → splUSD conversion |
| `convertToAssets(shares)` | Preview splUSD → plUSD conversion |
| `maxDeposit(owner)` | Max depositable |
| `maxWithdraw(owner)` | Max withdrawable |

## Addresses

### Plasma Mainnet

| Contract | Address |
|----------|---------|
| plUSD | [`0xf91c31299E998C5127Bc5F11e4a657FC0cF358CD`](https://plasmascan.to/address/0xf91c31299E998C5127Bc5F11e4a657FC0cF358CD) |
| splUSD v1 (deprecated) | [`0x616185600989Bf8339b58aC9e539d49536598343`](https://plasmascan.to/address/0x616185600989Bf8339b58aC9e539d49536598343) |
| splUSD v2 | [`0x63C6798DD4C3fAFD6d787cDaFf85FEED82Da8442`](https://plasmascan.to/address/0x63C6798DD4C3fAFD6d787cDaFf85FEED82Da8442) |

## License

MIT
