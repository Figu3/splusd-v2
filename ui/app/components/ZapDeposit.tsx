"use client";

import { useState, useEffect, useCallback, useRef } from "react";
import {
  useAccount,
  useReadContracts,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { parseUnits, formatUnits, maxUint256 } from "viem";
import {
  SPLUSD_V2_ADDRESS,
  PLUSD_ADDRESS,
  USDT0_ADDRESS,
  ROUTER_ADDRESS,
  SPLUSD_V2_ABI,
  ROUTER_ABI,
  ERC20_ABI,
} from "@/lib/contracts";
import { plasma } from "@/lib/wagmi";

type Step =
  | "input"
  | "approving_usdt_zero" // reset USDT allowance to 0 (race condition fix)
  | "approving_usdt"
  | "minting"
  | "approving_plusd"
  | "depositing"
  | "done"
  | "error";

const MAX_RETRIES = 5;
const RETRY_DELAY_MS = 2000;

export function ZapDeposit() {
  const { address, isConnected, chain } = useAccount();
  const [amount, setAmount] = useState("");
  const [step, setStep] = useState<Step>("input");
  const [errorMessage, setErrorMessage] = useState("");

  // Track plUSD balance BEFORE mint to compute delta
  const plusdBalanceBeforeMint = useRef<bigint>(0n);
  // Track the actual minted amount (delta)
  const mintedPlusdAmount = useRef<bigint>(0n);
  // Retry counter for stale RPC reads
  const retryCount = useRef(0);

  const wrongChain = chain?.id !== plasma.id;

  // Read USDT balance, USDT allowance for Router, plUSD balance, plUSD allowance for Vault
  const { data: reads, refetch: refetchReads } = useReadContracts({
    contracts: [
      {
        address: USDT0_ADDRESS,
        abi: ERC20_ABI,
        functionName: "balanceOf",
        args: address ? [address] : undefined,
      },
      {
        address: USDT0_ADDRESS,
        abi: ERC20_ABI,
        functionName: "allowance",
        args: address ? [address, ROUTER_ADDRESS] : undefined,
      },
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

  const usdtBalance = reads?.[0]?.result as bigint | undefined;
  const usdtAllowance = reads?.[1]?.result as bigint | undefined;
  const plusdBalance = reads?.[2]?.result as bigint | undefined;

  // USDT0 has 6 decimals
  const parsedAmount = (() => {
    try {
      return amount ? parseUnits(amount, 6) : 0n;
    } catch {
      return 0n;
    }
  })();

  // Check if USDT allowance needs to be reset to 0 first (USDT race condition)
  const hasExistingUsdtAllowance =
    usdtAllowance !== undefined && usdtAllowance > 0n;
  const needsUsdtApproval =
    parsedAmount > 0n &&
    (usdtAllowance === undefined || usdtAllowance < parsedAmount);

  // ── Approve USDT to 0 (race condition fix) ──
  const {
    writeContract: writeApproveUsdtZero,
    data: approveUsdtZeroTxHash,
    isPending: isApproveUsdtZeroWriting,
    error: approveUsdtZeroError,
    reset: resetApproveUsdtZero,
  } = useWriteContract();

  const {
    isLoading: isApproveUsdtZeroConfirming,
    isSuccess: isApproveUsdtZeroConfirmed,
  } = useWaitForTransactionReceipt({ hash: approveUsdtZeroTxHash });

  // ── Approve USDT tx ──
  const {
    writeContract: writeApproveUsdt,
    data: approveUsdtTxHash,
    isPending: isApproveUsdtWriting,
    error: approveUsdtError,
    reset: resetApproveUsdt,
  } = useWriteContract();

  const {
    isLoading: isApproveUsdtConfirming,
    isSuccess: isApproveUsdtConfirmed,
  } = useWaitForTransactionReceipt({ hash: approveUsdtTxHash });

  // ── Mint tx (Router.mint) ──
  const {
    writeContract: writeMint,
    data: mintTxHash,
    isPending: isMintWriting,
    error: mintError,
    reset: resetMint,
  } = useWriteContract();

  const { isLoading: isMintConfirming, isSuccess: isMintConfirmed } =
    useWaitForTransactionReceipt({ hash: mintTxHash });

  // ── Approve plUSD tx ──
  const {
    writeContract: writeApprovePlusd,
    data: approvePlusdTxHash,
    isPending: isApprovePlusdWriting,
    error: approvePlusdError,
    reset: resetApprovePlusd,
  } = useWriteContract();

  const {
    isLoading: isApprovePlusdConfirming,
    isSuccess: isApprovePlusdConfirmed,
  } = useWaitForTransactionReceipt({ hash: approvePlusdTxHash });

  // ── Deposit tx (splUSD v2 vault) ──
  const {
    writeContract: writeDeposit,
    data: depositTxHash,
    isPending: isDepositWriting,
    error: depositError,
    reset: resetDeposit,
  } = useWriteContract();

  const { isLoading: isDepositConfirming, isSuccess: isDepositConfirmed } =
    useWaitForTransactionReceipt({ hash: depositTxHash });

  // ── Error detection: catch wallet rejections / tx failures ──
  useEffect(() => {
    const error =
      approveUsdtZeroError ||
      approveUsdtError ||
      mintError ||
      approvePlusdError ||
      depositError;
    if (error && step !== "input" && step !== "done" && step !== "error") {
      const msg = error.message?.includes("User rejected")
        ? "Transaction rejected in wallet"
        : error.message?.slice(0, 120) || "Transaction failed";
      setErrorMessage(msg);
      setStep("error");
    }
  }, [
    approveUsdtZeroError,
    approveUsdtError,
    mintError,
    approvePlusdError,
    depositError,
    step,
  ]);

  // ── Step transitions ──

  // After USDT zero-approval confirms → proceed to real approval
  useEffect(() => {
    if (isApproveUsdtZeroConfirmed && step === "approving_usdt_zero") {
      refetchReads();
      setStep("approving_usdt");
      writeApproveUsdt({
        address: USDT0_ADDRESS,
        abi: ERC20_ABI,
        functionName: "approve",
        args: [ROUTER_ADDRESS, parsedAmount],
      });
    }
  }, [isApproveUsdtZeroConfirmed, step, refetchReads, writeApproveUsdt, parsedAmount]);

  // After USDT approval confirms → go back to input so user can click mint
  useEffect(() => {
    if (isApproveUsdtConfirmed && step === "approving_usdt") {
      refetchReads();
      setStep("input");
    }
  }, [isApproveUsdtConfirmed, step, refetchReads]);

  // After mint confirms → compute delta and move to plUSD approval
  useEffect(() => {
    if (isMintConfirmed && step === "minting") {
      retryCount.current = 0;
      // Poll for updated plUSD balance with retries (RPC can lag)
      const pollForBalance = async () => {
        const result = await refetchReads();
        const newPlusdBalance = result.data?.[2]?.result as bigint | undefined;
        const beforeBalance = plusdBalanceBeforeMint.current;

        if (newPlusdBalance !== undefined && newPlusdBalance > beforeBalance) {
          // Got a real delta
          const delta = newPlusdBalance - beforeBalance;
          mintedPlusdAmount.current = delta;
          setStep("approving_plusd");
        } else if (retryCount.current < MAX_RETRIES) {
          retryCount.current += 1;
          setTimeout(pollForBalance, RETRY_DELAY_MS);
        } else {
          setErrorMessage(
            "Could not detect minted plUSD after mint. Your plUSD was minted but the deposit step failed to auto-continue. You can deposit manually via the vault."
          );
          setStep("error");
        }
      };
      // Small initial delay for RPC propagation
      setTimeout(pollForBalance, 1500);
    }
  }, [isMintConfirmed, step, refetchReads]);

  // Auto-trigger plUSD approval when entering that step
  useEffect(() => {
    if (
      step === "approving_plusd" &&
      !isApprovePlusdWriting &&
      !approvePlusdTxHash &&
      mintedPlusdAmount.current > 0n
    ) {
      writeApprovePlusd({
        address: PLUSD_ADDRESS,
        abi: ERC20_ABI,
        functionName: "approve",
        args: [SPLUSD_V2_ADDRESS, mintedPlusdAmount.current],
      });
    }
  }, [step, isApprovePlusdWriting, approvePlusdTxHash, writeApprovePlusd]);

  // After plUSD approval confirms → auto-deposit
  useEffect(() => {
    if (isApprovePlusdConfirmed && step === "approving_plusd") {
      refetchReads();
      setStep("depositing");
    }
  }, [isApprovePlusdConfirmed, step, refetchReads]);

  // Auto-trigger deposit when entering that step
  useEffect(() => {
    if (
      step === "depositing" &&
      !isDepositWriting &&
      !depositTxHash &&
      mintedPlusdAmount.current > 0n &&
      address
    ) {
      writeDeposit({
        address: SPLUSD_V2_ADDRESS,
        abi: SPLUSD_V2_ABI,
        functionName: "deposit",
        args: [mintedPlusdAmount.current, address],
      });
    }
  }, [step, isDepositWriting, depositTxHash, writeDeposit, address]);

  // After deposit confirms → done
  useEffect(() => {
    if (isDepositConfirmed && step === "depositing") {
      refetchReads();
      setStep("done");
    }
  }, [isDepositConfirmed, step, refetchReads]);

  // ── Handlers ──

  function handleApproveUsdt() {
    if (hasExistingUsdtAllowance && needsUsdtApproval) {
      // USDT race condition: reset to 0 first
      setStep("approving_usdt_zero");
      writeApproveUsdtZero({
        address: USDT0_ADDRESS,
        abi: ERC20_ABI,
        functionName: "approve",
        args: [ROUTER_ADDRESS, 0n],
      });
    } else {
      setStep("approving_usdt");
      writeApproveUsdt({
        address: USDT0_ADDRESS,
        abi: ERC20_ABI,
        functionName: "approve",
        args: [ROUTER_ADDRESS, parsedAmount],
      });
    }
  }

  function handleMint() {
    if (!address) return;
    // Snapshot plUSD balance BEFORE mint
    plusdBalanceBeforeMint.current = plusdBalance ?? 0n;
    mintedPlusdAmount.current = 0n;
    retryCount.current = 0;
    setStep("minting");
    writeMint({
      address: ROUTER_ADDRESS,
      abi: ROUTER_ABI,
      functionName: "mint",
      args: [USDT0_ADDRESS, parsedAmount, false, address],
    });
  }

  const handleReset = useCallback(() => {
    setAmount("");
    setStep("input");
    setErrorMessage("");
    plusdBalanceBeforeMint.current = 0n;
    mintedPlusdAmount.current = 0n;
    retryCount.current = 0;
    resetApproveUsdtZero();
    resetApproveUsdt();
    resetMint();
    resetApprovePlusd();
    resetDeposit();
    refetchReads();
  }, [
    resetApproveUsdtZero,
    resetApproveUsdt,
    resetMint,
    resetApprovePlusd,
    resetDeposit,
    refetchReads,
  ]);

  function handleMax() {
    if (usdtBalance) {
      setAmount(formatUnits(usdtBalance, 6));
    }
  }

  // ── Render: Not connected ──
  if (!isConnected) {
    return (
      <div className="bg-zinc-800/50 border border-zinc-700/50 rounded-xl p-8 text-center">
        <p className="text-zinc-400">Connect your wallet to zap deposit</p>
      </div>
    );
  }

  // ── Render: Wrong chain ──
  if (wrongChain) {
    return (
      <div className="bg-zinc-800/50 border border-red-700/50 rounded-xl p-8 text-center">
        <p className="text-red-400">
          Please switch to Plasma network (Chain ID: 9745)
        </p>
      </div>
    );
  }

  // ── Render: Error state ──
  if (step === "error") {
    return (
      <div className="bg-zinc-800/50 border border-red-700/50 rounded-xl p-8 text-center space-y-4">
        <div className="text-4xl">&#9888;</div>
        <p className="text-red-400 text-lg font-medium">Something went wrong</p>
        <p className="text-zinc-400 text-sm">{errorMessage}</p>
        <button
          onClick={handleReset}
          className="mt-4 px-6 py-2 bg-zinc-700 hover:bg-zinc-600 text-zinc-200 rounded-lg transition-colors cursor-pointer"
        >
          Start over
        </button>
      </div>
    );
  }

  // ── Render: Done ──
  if (step === "done") {
    return (
      <div className="bg-zinc-800/50 border border-green-700/50 rounded-xl p-8 text-center space-y-4">
        <div className="text-4xl">&#10003;</div>
        <p className="text-green-400 text-lg font-medium">
          Zap deposit successful!
        </p>
        <p className="text-zinc-400 text-sm font-mono">
          {amount} USDT0 zapped into splUSD v2 vault
        </p>
        {depositTxHash && (
          <a
            href={`https://plasmascan.to/tx/${depositTxHash}`}
            target="_blank"
            rel="noopener noreferrer"
            className="text-blue-400 hover:text-blue-300 text-sm underline"
          >
            View deposit on PlasmaExplorer
          </a>
        )}
        <button
          onClick={handleReset}
          className="mt-4 px-6 py-2 bg-zinc-700 hover:bg-zinc-600 text-zinc-200 rounded-lg transition-colors cursor-pointer"
        >
          Zap more
        </button>
      </div>
    );
  }

  // ── Computed state ──
  const isAmountValid = parsedAmount > 0n;
  const hasEnoughBalance =
    usdtBalance !== undefined && parsedAmount <= usdtBalance;

  const isBusy =
    isApproveUsdtZeroWriting ||
    isApproveUsdtZeroConfirming ||
    isApproveUsdtWriting ||
    isApproveUsdtConfirming ||
    isMintWriting ||
    isMintConfirming ||
    isApprovePlusdWriting ||
    isApprovePlusdConfirming ||
    isDepositWriting ||
    isDepositConfirming;

  const isAutoStep =
    step === "approving_plusd" || step === "depositing";

  // Step number for progress display
  const stepNumber =
    step === "depositing"
      ? 4
      : step === "approving_plusd"
        ? 3
        : step === "minting"
          ? 2
          : step === "approving_usdt" || step === "approving_usdt_zero"
            ? 1
            : 0;

  return (
    <div className="bg-zinc-800/50 border border-zinc-700/50 rounded-xl p-6 space-y-5">
      {/* Progress indicator */}
      {stepNumber > 0 && (
        <div className="flex items-center gap-2 text-xs text-zinc-400">
          {[
            "Approve USDT",
            "Mint plUSD",
            "Approve plUSD",
            "Deposit to vault",
          ].map((label, i) => (
            <div key={label} className="flex items-center gap-1">
              <div
                className={`w-5 h-5 rounded-full flex items-center justify-center text-[10px] font-bold ${
                  i + 1 < stepNumber
                    ? "bg-green-600 text-white"
                    : i + 1 === stepNumber
                      ? "bg-blue-600 text-white"
                      : "bg-zinc-700 text-zinc-500"
                }`}
              >
                {i + 1 < stepNumber ? "\u2713" : i + 1}
              </div>
              <span
                className={
                  i + 1 === stepNumber ? "text-blue-400" : "text-zinc-500"
                }
              >
                {label}
              </span>
              {i < 3 && (
                <span className="text-zinc-700 mx-1">&rarr;</span>
              )}
            </div>
          ))}
        </div>
      )}

      {/* Amount input */}
      <div>
        <label className="text-xs text-zinc-500 uppercase tracking-wide block mb-2">
          Amount (USDT0)
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
            disabled={!usdtBalance || isBusy}
            className="px-3 py-1 text-xs text-blue-400 hover:text-blue-300 bg-blue-900/20 hover:bg-blue-900/40 border border-blue-800/30 rounded-lg transition-colors disabled:opacity-50 cursor-pointer"
          >
            MAX
          </button>
        </div>
        <p className="text-xs text-zinc-500 mt-1.5 font-mono">
          Balance:{" "}
          {usdtBalance !== undefined
            ? Number(formatUnits(usdtBalance, 6)).toLocaleString(undefined, {
                maximumFractionDigits: 2,
              })
            : "\u2014"}{" "}
          USDT0
        </p>
      </div>

      {/* Flow description */}
      <div className="text-xs text-zinc-500 bg-zinc-900/50 rounded-lg p-3 space-y-1">
        <p className="text-zinc-400 font-medium">Zap flow:</p>
        <p>1. Approve USDT0 for Router</p>
        <p>2. Mint plUSD via Router (USDT0 &rarr; plUSD)</p>
        <p>3. Approve plUSD for splUSD v2 vault</p>
        <p>4. Deposit plUSD into splUSD v2 vault</p>
      </div>

      {/* Action buttons */}
      {isAutoStep ? (
        <div className="space-y-3">
          <button
            disabled
            className="w-full py-3 bg-zinc-700 text-zinc-400 font-medium rounded-lg cursor-not-allowed"
          >
            {step === "approving_plusd"
              ? isApprovePlusdWriting
                ? "Confirm plUSD approval in wallet..."
                : isApprovePlusdConfirming
                  ? "Approving plUSD..."
                  : "Preparing plUSD approval..."
              : isDepositWriting
                ? "Confirm deposit in wallet..."
                : isDepositConfirming
                  ? "Depositing into vault..."
                  : "Preparing deposit..."}
          </button>
          <button
            onClick={handleReset}
            className="w-full py-2 text-sm text-zinc-500 hover:text-zinc-300 transition-colors cursor-pointer"
          >
            Cancel
          </button>
        </div>
      ) : needsUsdtApproval ? (
        <button
          onClick={handleApproveUsdt}
          disabled={!isAmountValid || !hasEnoughBalance || isBusy}
          className="w-full py-3 bg-amber-600 hover:bg-amber-500 disabled:bg-zinc-700 disabled:text-zinc-500 text-white font-medium rounded-lg transition-colors disabled:cursor-not-allowed cursor-pointer"
        >
          {isApproveUsdtZeroWriting
            ? "Confirm reset approval in wallet..."
            : isApproveUsdtZeroConfirming
              ? "Resetting USDT0 allowance..."
              : isApproveUsdtWriting
                ? "Confirm in wallet..."
                : isApproveUsdtConfirming
                  ? "Approving USDT0..."
                  : `Step 1: Approve ${amount} USDT0`}
        </button>
      ) : (
        <button
          onClick={handleMint}
          disabled={!isAmountValid || !hasEnoughBalance || isBusy}
          className="w-full py-3 bg-blue-600 hover:bg-blue-500 disabled:bg-zinc-700 disabled:text-zinc-500 text-white font-medium rounded-lg transition-colors disabled:cursor-not-allowed cursor-pointer"
        >
          {isMintWriting
            ? "Confirm in wallet..."
            : isMintConfirming
              ? "Minting plUSD..."
              : `Step 2: Mint plUSD & Deposit to Vault`}
        </button>
      )}

      {/* Validation errors */}
      {isAmountValid && !hasEnoughBalance && (
        <p className="text-red-400 text-xs">Insufficient USDT0 balance</p>
      )}
    </div>
  );
}
