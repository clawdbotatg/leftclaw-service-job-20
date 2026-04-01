"use client";

import { useState } from "react";
import { parseEther } from "viem";
import { useAccount } from "wagmi";
import { useScaffoldReadContract, useScaffoldWriteContract } from "~~/hooks/scaffold-eth";

export const RebalancePanel = () => {
  const { address } = useAccount();
  const [token, setToken] = useState("");
  const [amount, setAmount] = useState("");
  const [mode, setMode] = useState<"operator" | "permissionless">("permissionless");

  const { data: isOperator } = useScaffoldReadContract({
    contractName: "TreasuryManagerV2",
    functionName: "isOperator",
    args: [address],
  });

  const { data: cooldownRemaining } = useScaffoldReadContract({
    contractName: "TreasuryManagerV2",
    functionName: "getCooldownRemaining",
  });

  const { data: registeredTokens } = useScaffoldReadContract({
    contractName: "TreasuryManagerV2",
    functionName: "getRegisteredTokens",
  });

  const { writeContractAsync, isMining } = useScaffoldWriteContract("TreasuryManagerV2");

  const hasCooldown = cooldownRemaining !== undefined && cooldownRemaining > 0n;

  const handleRebalance = async () => {
    if (!token || !amount) return;
    try {
      if (mode === "operator") {
        await writeContractAsync({
          functionName: "rebalance",
          args: [token as `0x${string}`, parseEther(amount)],
        });
      } else {
        await writeContractAsync({
          functionName: "permissionlessRebalance",
          args: [token as `0x${string}`, parseEther(amount)],
        });
      }
      setAmount("");
    } catch (e) {
      console.error("Rebalance failed:", e);
    }
  };

  return (
    <div className="card bg-base-100 shadow-xl">
      <div className="card-body">
        <h2 className="card-title text-2xl mb-4">
          ♻️ Rebalance
        </h2>

        {/* Mode selector */}
        <div className="tabs tabs-boxed mb-4">
          <button
            className={`tab ${mode === "permissionless" ? "tab-active" : ""}`}
            onClick={() => setMode("permissionless")}
          >
            Permissionless
          </button>
          <button
            className={`tab ${mode === "operator" ? "tab-active" : ""}`}
            onClick={() => setMode("operator")}
          >
            Operator
          </button>
        </div>

        {mode === "permissionless" && (
          <div className="alert alert-info mb-4">
            <span>Anyone can call permissionless rebalance when unlock conditions are met (ROI ≥ 1000%, 14-day inactivity).</span>
          </div>
        )}

        {/* Token address */}
        <div className="form-control mb-4">
          <label className="label">
            <span className="label-text font-semibold">Token Address</span>
          </label>
          {registeredTokens && registeredTokens.length > 0 ? (
            <select
              className="select select-bordered w-full"
              value={token}
              onChange={e => setToken(e.target.value)}
            >
              <option value="">Select token...</option>
              {registeredTokens.map(t => (
                <option key={t} value={t}>
                  {t.slice(0, 6)}...{t.slice(-4)}
                </option>
              ))}
            </select>
          ) : (
            <input
              type="text"
              placeholder="0x..."
              className="input input-bordered w-full"
              value={token}
              onChange={e => setToken(e.target.value)}
            />
          )}
        </div>

        {/* Amount */}
        <div className="form-control mb-4">
          <label className="label">
            <span className="label-text font-semibold">Amount (tokens)</span>
            {mode === "permissionless" && (
              <span className="label-text-alt">Max 5% of unlocked per tx</span>
            )}
          </label>
          <input
            type="text"
            placeholder="0.0"
            className="input input-bordered w-full"
            value={amount}
            onChange={e => setAmount(e.target.value)}
          />
        </div>

        {/* Unlock info for permissionless */}
        {mode === "permissionless" && token && (
          <UnlockInfo token={token as `0x${string}`} />
        )}

        {mode === "operator" && hasCooldown && (
          <div className="alert alert-warning mb-4">
            <span>⏳ Cooldown active — {Math.ceil(Number(cooldownRemaining || 0n) / 60)}m remaining</span>
          </div>
        )}

        <div className="bg-base-200 rounded-lg p-3 mb-4 text-sm">
          <p>75% → ₸USD buyback (stays in contract)</p>
          <p>25% → USDC to owner</p>
        </div>

        <button
          className={`btn w-full ${mode === "operator" ? "btn-primary" : "btn-success"} ${isMining ? "loading" : ""}`}
          disabled={
            (mode === "operator" && (!isOperator || hasCooldown)) ||
            isMining ||
            !token ||
            !amount
          }
          onClick={handleRebalance}
        >
          {isMining ? "Processing..." : `${mode === "operator" ? "Operator" : "Permissionless"} Rebalance`}
        </button>
      </div>
    </div>
  );
};

const UnlockInfo = ({ token }: { token: `0x${string}` }) => {
  const { data: unlockData } = useScaffoldReadContract({
    contractName: "TreasuryManagerV2",
    functionName: "getUnlockPercentage",
    args: [token],
  });

  if (!unlockData) return null;

  const [unlocked, unlockBps] = unlockData;
  const unlockPercent = Number(unlockBps) / 100;

  return (
    <div className="bg-base-200 rounded-lg p-3 mb-4">
      <div className="flex justify-between items-center">
        <span className="text-sm">Unlock Status:</span>
        <span className={`badge ${unlocked ? "badge-success" : "badge-error"}`}>
          {unlocked ? `${unlockPercent.toFixed(1)}% Unlocked` : "Locked"}
        </span>
      </div>
      {!unlocked && (
        <p className="text-xs text-base-content/60 mt-1">
          Requires: ROI ≥ 1000% + 14 days inactivity
        </p>
      )}
    </div>
  );
};

export default RebalancePanel;
