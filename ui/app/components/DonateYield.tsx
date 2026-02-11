"use client";

import { useState, useEffect } from "react";
import {
  useAccount,
  useReadContracts,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { parseUnits, formatUnits } from "viem";
import {
  SPLUSD_V2_ADDRESS,
  PLUSD_ADDRESS,
  SPLUSD_V2_ABI,
  ERC20_ABI,
} from "@/lib/contracts";
import { plasma } from "@/lib/wagmi";

type Step = "input" | "approving" | "donating" | "done";

export function DonateYield() {
  const { address, isConnected, chain } = useAccount();
  const [amount, setAmount] = useState("");
  const [step, setStep] = useState<Step>("input");

  const wrongChain = chain?.id !== plasma.id;

  // Read plUSD balance and allowance
  const { data: reads, refetch: refetchReads } = useReadContracts({
    contracts: [
      {
        address: PLUSD_ADDRESS,
        abi: ERC20_ABI,
        functionName: "balanceOf",
        args: address ? [address] : undefined,
      },
      {
        address: PLUSD_ADDRESS,
        abi: ERC20_ABI,
        functionName: "allowance",
        args: address ? [address, SPLUSD_V2_ADDRESS] : undefined,
      },
    ],
    query: { enabled: !!address },
  });

  const balance = reads?.[0]?.result as bigint | undefined;
  const allowance = reads?.[1]?.result as bigint | undefined;

  const parsedAmount = (() => {
    try {
      return amount ? parseUnits(amount, 18) : 0n;
    } catch {
      return 0n;
    }
  })();

  const needsApproval =
    parsedAmount > 0n && (allowance === undefined || allowance < parsedAmount);

  // Approve tx
  const {
    writeContract: writeApprove,
    data: approveTxHash,
    isPending: isApproveWriting,
    reset: resetApprove,
  } = useWriteContract();

  const { isLoading: isApproveConfirming, isSuccess: isApproveConfirmed } =
    useWaitForTransactionReceipt({ hash: approveTxHash });

  // Donate tx
  const {
    writeContract: writeDonate,
    data: donateTxHash,
    isPending: isDonateWriting,
    reset: resetDonate,
  } = useWriteContract();

  const { isLoading: isDonateConfirming, isSuccess: isDonateConfirmed } =
    useWaitForTransactionReceipt({ hash: donateTxHash });

  // After approval confirmed, move to donate step
  useEffect(() => {
    if (isApproveConfirmed && step === "approving") {
      refetchReads();
      setStep("input");
    }
  }, [isApproveConfirmed, step, refetchReads]);

  // After donate confirmed
  useEffect(() => {
    if (isDonateConfirmed && step === "donating") {
      setStep("done");
      refetchReads();
    }
  }, [isDonateConfirmed, step, refetchReads]);

  function handleApprove() {
    setStep("approving");
    writeApprove({
      address: PLUSD_ADDRESS,
      abi: ERC20_ABI,
      functionName: "approve",
      args: [SPLUSD_V2_ADDRESS, parsedAmount],
    });
  }

  function handleDonate() {
    setStep("donating");
    writeDonate({
      address: SPLUSD_V2_ADDRESS,
      abi: SPLUSD_V2_ABI,
      functionName: "donateYield",
      args: [parsedAmount],
    });
  }

  function handleReset() {
    setAmount("");
    setStep("input");
    resetApprove();
    resetDonate();
    refetchReads();
  }

  function handleMax() {
    if (balance) {
      setAmount(formatUnits(balance, 18));
    }
  }

  if (!isConnected) {
    return (
      <div className="bg-zinc-800/50 border border-zinc-700/50 rounded-xl p-8 text-center">
        <p className="text-zinc-400">Connect your wallet to donate yield</p>
      </div>
    );
  }

  if (wrongChain) {
    return (
      <div className="bg-zinc-800/50 border border-red-700/50 rounded-xl p-8 text-center">
        <p className="text-red-400">
          Please switch to Plasma network (Chain ID: 9745)
        </p>
      </div>
    );
  }

  if (step === "done") {
    return (
      <div className="bg-zinc-800/50 border border-green-700/50 rounded-xl p-8 text-center space-y-4">
        <div className="text-4xl">&#10003;</div>
        <p className="text-green-400 text-lg font-medium">
          Yield donated successfully!
        </p>
        <p className="text-zinc-400 text-sm font-mono">
          {amount} plUSD donated to splUSD v2 vault
        </p>
        {donateTxHash && (
          <a
            href={`https://plasmascan.to/tx/${donateTxHash}`}
            target="_blank"
            rel="noopener noreferrer"
            className="text-blue-400 hover:text-blue-300 text-sm underline"
          >
            View on PlasmaExplorer
          </a>
        )}
        <button
          onClick={handleReset}
          className="mt-4 px-6 py-2 bg-zinc-700 hover:bg-zinc-600 text-zinc-200 rounded-lg transition-colors cursor-pointer"
        >
          Donate more
        </button>
      </div>
    );
  }

  const isAmountValid = parsedAmount > 0n;
  const hasEnoughBalance = balance !== undefined && parsedAmount <= balance;
  const isBusy =
    isApproveWriting ||
    isApproveConfirming ||
    isDonateWriting ||
    isDonateConfirming;

  return (
    <div className="bg-zinc-800/50 border border-zinc-700/50 rounded-xl p-6 space-y-5">
      {/* Amount input */}
      <div>
        <label className="text-xs text-zinc-500 uppercase tracking-wide block mb-2">
          Amount (plUSD)
        </label>
        <div className="flex gap-2">
          <input
            type="text"
            inputMode="decimal"
            placeholder="0.0"
            value={amount}
            onChange={(e) => {
              const val = e.target.value;
              if (/^[0-9]*\.?[0-9]*$/.test(val)) setAmount(val);
            }}
            disabled={isBusy}
            className="flex-1 bg-zinc-900 border border-zinc-700 rounded-lg px-4 py-3 text-lg font-mono text-zinc-100 placeholder-zinc-600 focus:outline-none focus:border-blue-500 disabled:opacity-50"
          />
          <button
            onClick={handleMax}
            disabled={!balance || isBusy}
            className="px-3 py-1 text-xs text-blue-400 hover:text-blue-300 bg-blue-900/20 hover:bg-blue-900/40 border border-blue-800/30 rounded-lg transition-colors disabled:opacity-50 cursor-pointer"
          >
            MAX
          </button>
        </div>
        <p className="text-xs text-zinc-500 mt-1.5 font-mono">
          Balance:{" "}
          {balance !== undefined
            ? Number(formatUnits(balance, 18)).toLocaleString(undefined, {
                maximumFractionDigits: 4,
              })
            : "—"}{" "}
          plUSD
        </p>
      </div>

      {/* Allowance info */}
      {isAmountValid && (
        <div className="text-xs text-zinc-500 font-mono">
          Allowance:{" "}
          {allowance !== undefined
            ? Number(formatUnits(allowance, 18)).toLocaleString(undefined, {
                maximumFractionDigits: 4,
              })
            : "—"}{" "}
          plUSD
          {needsApproval && (
            <span className="text-amber-400 ml-2">
              (approval needed)
            </span>
          )}
        </div>
      )}

      {/* Action buttons */}
      {needsApproval ? (
        <button
          onClick={handleApprove}
          disabled={!isAmountValid || !hasEnoughBalance || isBusy}
          className="w-full py-3 bg-amber-600 hover:bg-amber-500 disabled:bg-zinc-700 disabled:text-zinc-500 text-white font-medium rounded-lg transition-colors disabled:cursor-not-allowed cursor-pointer"
        >
          {isApproveWriting
            ? "Confirm in wallet..."
            : isApproveConfirming
              ? "Approving..."
              : `Approve ${amount} plUSD`}
        </button>
      ) : (
        <button
          onClick={handleDonate}
          disabled={!isAmountValid || !hasEnoughBalance || isBusy}
          className="w-full py-3 bg-blue-600 hover:bg-blue-500 disabled:bg-zinc-700 disabled:text-zinc-500 text-white font-medium rounded-lg transition-colors disabled:cursor-not-allowed cursor-pointer"
        >
          {isDonateWriting
            ? "Confirm in wallet..."
            : isDonateConfirming
              ? "Donating yield..."
              : `Donate ${isAmountValid ? amount : "—"} plUSD`}
        </button>
      )}

      {/* Validation errors */}
      {isAmountValid && !hasEnoughBalance && (
        <p className="text-red-400 text-xs">Insufficient plUSD balance</p>
      )}
    </div>
  );
}
