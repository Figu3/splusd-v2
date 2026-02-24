# splUSD v2 — UI

Next.js frontend + yield API for the splUSD v2 ERC4626 vault on Plasma.

## Development

```bash
npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000).

## API

`GET /api/yield` — returns live vault stats and APR:

```json
{
  "sharePrice": "1.00345678",
  "totalAssets": "125000.00",
  "totalSupply": "124567.89",
  "apr": { "7d": 5.23, "30d": 4.87, "sinceInception": 4.95 },
  "yieldDonated": { "7d": "234.56", "30d": "1023.45", "total": "1523.78" }
}
```

## Docker

```bash
docker build -t splusd-v2-ui .
docker run -p 3000:3000 splusd-v2-ui
```

## Stack

- Next.js 16, React 19, TypeScript
- viem + wagmi (Plasma chain, ID 9745)
- Tailwind CSS 4
