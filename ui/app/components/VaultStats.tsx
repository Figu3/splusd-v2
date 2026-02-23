"use client";

import { useEffect, useState } from "react";
import { useReadContracts } from "wagmi";
import { formatUnits } from "viem";
import { SPLUSD_V2_ADDRESS, SPLUSD_V2_ABI } from "@/lib/contracts";

interface YieldData {
  apr: { "7d": number; "30d": number; sinceInception: number };
  yieldDonated: { "7d": string; "30d": string; total: string };
}

export function VaultStats() {
  const { data, isLoading } = useReadContracts({
    contracts: [
      {
        address: SPLUSD_V2_ADDRESS,
        abi: SPLUSD_V2_ABI,
        functionName: "totalAssets",
      },
      {
        address: SPLUSD_V2_ADDRESS,
        abi: SPLUSD_V2_ABI,
        functionName: "totalSupply",
      },
      {
        address: SPLUSD_V2_ADDRESS,
        abi: SPLUSD_V2_ABI,
        functionName: "convertToAssets",
        args: [BigInt(1e18)], // 1 share = ? assets
      },
    ],
  });

  const [yieldData, setYieldData] = useState<YieldData | null>(null);

  useEffect(() => {
    fetch("/api/yield")
      .then((res) => res.json())
      .then((d) => setYieldData(d))
      .catch(() => {}); // Silently fail — on-chain stats still show
  }, []);

  const totalAssets = data?.[0]?.result;
  const totalSupply = data?.[1]?.result;
  const sharePrice = data?.[2]?.result;

  if (isLoading) {
    return (
      <div className="space-y-4 animate-pulse">
        <div className="grid grid-cols-3 gap-4">
          {[1, 2, 3].map((i) => (
            <div key={i} className="bg-zinc-800/50 rounded-xl p-4 h-20" />
          ))}
        </div>
        <div className="grid grid-cols-3 gap-4">
          {[4, 5, 6].map((i) => (
            <div key={i} className="bg-zinc-800/50 rounded-xl p-4 h-20" />
          ))}
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* Vault metrics */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <StatCard
          label="Total Assets (plUSD)"
          value={totalAssets ? formatUnits(totalAssets, 18) : "—"}
        />
        <StatCard
          label="Total Shares (splUSD)"
          value={totalSupply ? formatUnits(totalSupply, 18) : "—"}
        />
        <StatCard
          label="Share Price (plUSD)"
          value={
            sharePrice
              ? Number(formatUnits(sharePrice, 18)).toFixed(6)
              : "—"
          }
        />
      </div>

      {/* APR & yield */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <StatCard
          label="APR (7d)"
          value={yieldData ? `${yieldData.apr["7d"]}%` : "—"}
          highlight
        />
        <StatCard
          label="APR (30d)"
          value={yieldData ? `${yieldData.apr["30d"]}%` : "—"}
          highlight
        />
        <StatCard
          label="Total Yield Donated"
          value={
            yieldData
              ? `${Number(yieldData.yieldDonated.total).toLocaleString()} plUSD`
              : "—"
          }
        />
      </div>
    </div>
  );
}

function StatCard({
  label,
  value,
  highlight = false,
}: {
  label: string;
  value: string;
  highlight?: boolean;
}) {
  return (
    <div className="bg-zinc-800/50 border border-zinc-700/50 rounded-xl p-4">
      <p className="text-xs text-zinc-500 uppercase tracking-wide">{label}</p>
      <p
        className={`text-lg font-mono mt-1 ${
          highlight ? "text-emerald-400" : "text-zinc-100"
        }`}
      >
        {value}
      </p>
    </div>
  );
}
