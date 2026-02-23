import { createPublicClient, http, formatUnits, parseAbiItem, defineChain } from "viem";
import { SPLUSD_V2_ADDRESS, SPLUSD_V2_ABI } from "@/lib/contracts";

const plasma = defineChain({
  id: 9745,
  name: "Plasma",
  nativeCurrency: { name: "ETH", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: ["https://plasma.drpc.org"] } },
  blockExplorers: { default: { name: "PlasmaExplorer", url: "https://plasmascan.to" } },
});

const ONE_SHARE = BigInt(1e18);
const SECONDS_PER_YEAR = 365.25 * 24 * 3600;
const CACHE_TTL_MS = 5 * 60 * 1000; // 5 minutes

const YIELD_DONATED_EVENT = parseAbiItem(
  "event YieldDonated(address indexed donor, uint256 amount)"
);

// In-memory cache
let cache: { data: YieldResponse; timestamp: number } | null = null;

interface YieldResponse {
  vault: {
    address: string;
    chain: string;
    chainId: number;
  };
  sharePrice: string;
  totalAssets: string;
  totalSupply: string;
  apr: {
    "7d": number;
    "30d": number;
    sinceInception: number;
  };
  yieldDonated: {
    "7d": string;
    "30d": string;
    total: string;
  };
  totalYieldEvents: number;
  lastUpdated: string;
}

export async function GET() {
  try {
    if (cache && Date.now() - cache.timestamp < CACHE_TTL_MS) {
      return Response.json(cache.data, { headers: corsHeaders() });
    }

    const client = createPublicClient({
      chain: plasma,
      transport: http("https://plasma.drpc.org"),
    });

    // 1. Read current on-chain state
    const [totalAssets, totalSupply, sharePrice, latestBlock] = await Promise.all([
      client.readContract({
        address: SPLUSD_V2_ADDRESS,
        abi: SPLUSD_V2_ABI,
        functionName: "totalAssets",
      }),
      client.readContract({
        address: SPLUSD_V2_ADDRESS,
        abi: SPLUSD_V2_ABI,
        functionName: "totalSupply",
      }),
      client.readContract({
        address: SPLUSD_V2_ADDRESS,
        abi: SPLUSD_V2_ABI,
        functionName: "convertToAssets",
        args: [ONE_SHARE],
      }),
      client.getBlock({ blockTag: "latest" }),
    ]);

    // 2. Estimate block time to calculate lookback ranges
    const currentBlockNum = latestBlock.number;
    const refBlockNum = currentBlockNum > 1000n ? currentBlockNum - 1000n : 0n;
    const refBlock = await client.getBlock({ blockNumber: refBlockNum });

    const blockTimeSec =
      Number(latestBlock.timestamp - refBlock.timestamp) /
      Number(currentBlockNum - refBlockNum);

    const blocksPerDay = Math.floor(86400 / blockTimeSec);

    // 3. Get YieldDonated events for the last ~90 days (covers all relevant periods)
    const lookbackBlocks = BigInt(blocksPerDay * 90);
    const fromBlock = currentBlockNum > lookbackBlocks ? currentBlockNum - lookbackBlocks : 0n;

    const yieldEvents = await client.getLogs({
      address: SPLUSD_V2_ADDRESS,
      event: YIELD_DONATED_EVENT,
      fromBlock,
      toBlock: "latest",
    });

    // 4. Get block timestamps for each unique event block
    const blockTimestamps = new Map<bigint, number>();
    const uniqueBlocks = [...new Set(yieldEvents.map((e) => e.blockNumber))];

    // Batch in groups of 10 to avoid hammering RPC
    for (let i = 0; i < uniqueBlocks.length; i += 10) {
      const batch = uniqueBlocks.slice(i, i + 10);
      const blocks = await Promise.all(
        batch.map((bn) => client.getBlock({ blockNumber: bn }))
      );
      blocks.forEach((b) => blockTimestamps.set(b.number, Number(b.timestamp)));
    }

    // 5. Calculate yield sums for each time period
    const now = Number(latestBlock.timestamp);
    const periods = {
      "7d": 7 * 86400,
      "30d": 30 * 86400,
      total: now, // effectively all time
    } as const;

    const yieldByPeriod: Record<string, bigint> = {};
    let earliestEventTimestamp = now;

    for (const [label, seconds] of Object.entries(periods)) {
      const cutoff = now - seconds;
      yieldByPeriod[label] = yieldEvents
        .filter((e) => {
          const ts = blockTimestamps.get(e.blockNumber) ?? 0;
          if (ts < earliestEventTimestamp) earliestEventTimestamp = ts;
          return ts >= cutoff;
        })
        .reduce((sum, e) => sum + (e.args.amount ?? 0n), 0n);
    }

    // 6. Calculate APR for each period
    //    APR = (yieldDonated / totalAssets) * (secondsPerYear / periodSeconds) * 100
    const totalAssetsNum = Number(formatUnits(totalAssets as bigint, 18));

    function calcApr(yieldAmount: bigint, periodSeconds: number): number {
      if (totalAssetsNum <= 0 || periodSeconds <= 0) return 0;
      const yieldNum = Number(formatUnits(yieldAmount, 18));
      return (yieldNum / totalAssetsNum) * (SECONDS_PER_YEAR / periodSeconds) * 100;
    }

    const apr7d = calcApr(yieldByPeriod["7d"], periods["7d"]);
    const apr30d = calcApr(yieldByPeriod["30d"], periods["30d"]);

    // Since inception: use share price approach (more accurate)
    //   inception share price = 1.0, current = convertToAssets(1e18) / 1e18
    const sharePriceNum = Number(formatUnits(sharePrice as bigint, 18));
    const inceptionSeconds =
      yieldEvents.length > 0 ? now - earliestEventTimestamp : 0;
    const sinceInceptionApr =
      inceptionSeconds > 86400 // need at least 1 day of history
        ? ((sharePriceNum - 1) / 1) * (SECONDS_PER_YEAR / inceptionSeconds) * 100
        : 0;

    // 7. Build response
    const result: YieldResponse = {
      vault: {
        address: SPLUSD_V2_ADDRESS,
        chain: "plasma",
        chainId: 9745,
      },
      sharePrice: sharePriceNum.toFixed(8),
      totalAssets: Number(formatUnits(totalAssets as bigint, 18)).toFixed(2),
      totalSupply: Number(formatUnits(totalSupply as bigint, 18)).toFixed(2),
      apr: {
        "7d": round(apr7d, 2),
        "30d": round(apr30d, 2),
        sinceInception: round(sinceInceptionApr, 2),
      },
      yieldDonated: {
        "7d": Number(formatUnits(yieldByPeriod["7d"], 18)).toFixed(2),
        "30d": Number(formatUnits(yieldByPeriod["30d"], 18)).toFixed(2),
        total: Number(formatUnits(yieldByPeriod["total"], 18)).toFixed(2),
      },
      totalYieldEvents: yieldEvents.length,
      lastUpdated: new Date().toISOString(),
    };

    cache = { data: result, timestamp: Date.now() };
    return Response.json(result, { headers: corsHeaders() });
  } catch (error) {
    console.error("Yield API error:", error);
    return Response.json(
      { error: "Failed to fetch yield data" },
      { status: 500, headers: corsHeaders() }
    );
  }
}

// Support preflight requests
export async function OPTIONS() {
  return new Response(null, { status: 204, headers: corsHeaders() });
}

function corsHeaders(): HeadersInit {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    "Cache-Control": "public, s-maxage=300, stale-while-revalidate=60",
  };
}

function round(value: number, decimals: number): number {
  const factor = 10 ** decimals;
  return Math.round(value * factor) / factor;
}
