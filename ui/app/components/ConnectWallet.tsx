"use client";

import { useAccount, useConnect, useDisconnect } from "wagmi";
import { plasma } from "@/lib/wagmi";

export function ConnectWallet() {
  const { address, isConnected, chain } = useAccount();
  const { connect, connectors } = useConnect();
  const { disconnect } = useDisconnect();

  if (isConnected && address) {
    const wrongChain = chain?.id !== plasma.id;
    return (
      <div className="flex items-center gap-3">
        {wrongChain && (
          <span className="text-xs text-red-400 bg-red-900/30 px-2 py-1 rounded">
            Wrong network - switch to Plasma
          </span>
        )}
        <span className="text-sm text-zinc-400 font-mono">
          {address.slice(0, 6)}...{address.slice(-4)}
        </span>
        <button
          onClick={() => disconnect()}
          className="px-3 py-1.5 text-sm bg-zinc-800 hover:bg-zinc-700 text-zinc-300 rounded-lg border border-zinc-700 transition-colors cursor-pointer"
        >
          Disconnect
        </button>
      </div>
    );
  }

  return (
    <div className="flex gap-2">
      {connectors.map((connector) => (
        <button
          key={connector.uid}
          onClick={() => connect({ connector })}
          className="px-4 py-2 bg-blue-600 hover:bg-blue-500 text-white rounded-lg font-medium transition-colors cursor-pointer"
        >
          Connect {connector.name}
        </button>
      ))}
    </div>
  );
}
