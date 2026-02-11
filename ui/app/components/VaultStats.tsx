"use client";

import { useReadContracts } from "wagmi";
import { formatUnits } from "viem";
import { SPLUSD_V2_ADDRESS, SPLUSD_V2_ABI } from "@/lib/contracts";

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

  const totalAssets = data?.[0]?.result;
  const totalSupply = data?.[1]?.result;
  const sharePrice = data?.[2]?.result;

  if (isLoading) {
    return (
      <div className="grid grid-cols-3 gap-4 animate-pulse">
        {[1, 2, 3].map((i) => (
          <div key={i} className="bg-zinc-800/50 rounded-xl p-4 h-20" />
        ))}
      </div>
    );
  }

  return (
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
        value={sharePrice ? Number(formatUnits(sharePrice, 18)).toFixed(6) : "—"}
      />
    </div>
  );
}

function StatCard({ label, value }: { label: string; value: string }) {
  return (
    <div className="bg-zinc-800/50 border border-zinc-700/50 rounded-xl p-4">
      <p className="text-xs text-zinc-500 uppercase tracking-wide">{label}</p>
      <p className="text-lg font-mono text-zinc-100 mt-1">{value}</p>
    </div>
  );
}
