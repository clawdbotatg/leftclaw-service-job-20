"use client";

import { useState } from "react";
import { parseEther } from "viem";
import { useAccount } from "wagmi";
import { useScaffoldReadContract, useScaffoldWriteContract } from "~~/hooks/scaffold-eth";

const POOL_COUNT = 6; // Pools 0-5

export const StakingPanel = () => {
  const { address } = useAccount();
  const [selectedPool, setSelectedPool] = useState<number>(0);
  const [stakeAmount, setStakeAmount] = useState("");
  const [activeTab, setActiveTab] = useState<"stake" | "unstake">("stake");
  const [error, setError] = useState<string | null>(null);

  // Check if connected wallet is operator
  const { data: isOperator } = useScaffoldReadContract({
    contractName: "TreasuryManagerV2",
    functionName: "isOperator",
    args: [address],
  });

  // Get cooldown remaining
  const { data: cooldownRemaining } = useScaffoldReadContract({
    contractName: "TreasuryManagerV2",
    functionName: "getCooldownRemaining",
  });

  // Write contracts
  const { writeContractAsync: writeStake, isMining: isStaking } = useScaffoldWriteContract("TreasuryManagerV2");
  const { writeContractAsync: writeUnstake, isMining: isUnstaking } = useScaffoldWriteContract("TreasuryManagerV2");

  const handleStake = async () => {
    if (!stakeAmount) return;
    const parsed = Number(stakeAmount);
    if (isNaN(parsed) || parsed <= 0) {
      setError("Enter a valid positive number");
      return;
    }
    setError(null);
    try {
      await writeStake({
        functionName: "stake",
        args: [parseEther(stakeAmount), BigInt(selectedPool)],
      });
      setStakeAmount("");
    } catch (e: any) {
      setError(e?.shortMessage || e?.message || "Stake failed");
    }
  };

  const handleUnstake = async () => {
    setError(null);
    try {
      await writeUnstake({
        functionName: "unstake",
        args: [BigInt(selectedPool)],
      });
    } catch (e: any) {
      setError(e?.shortMessage || e?.message || "Unstake failed");
    }
  };

  const hasCooldown = cooldownRemaining !== undefined && cooldownRemaining > 0n;
  const cooldownMinutes = cooldownRemaining ? Math.ceil(Number(cooldownRemaining) / 60) : 0;

  return (
    <div className="card bg-base-100 shadow-xl">
      <div className="card-body">
        <h2 className="card-title text-2xl mb-4">
          🥩 Staking
          {!isOperator && <span className="badge badge-warning ml-2">Operator Only</span>}
        </h2>

        {/* Tab selector */}
        <div className="tabs tabs-boxed mb-4">
          <button
            className={`tab ${activeTab === "stake" ? "tab-active" : ""}`}
            onClick={() => setActiveTab("stake")}
          >
            Stake ₸USD
          </button>
          <button
            className={`tab ${activeTab === "unstake" ? "tab-active" : ""}`}
            onClick={() => setActiveTab("unstake")}
          >
            Unstake
          </button>
        </div>

        {/* Pool selector */}
        <div className="form-control mb-4">
          <label className="label">
            <span className="label-text font-semibold">Select Pool</span>
          </label>
          <select
            className="select select-bordered w-full"
            value={selectedPool}
            onChange={e => setSelectedPool(Number(e.target.value))}
          >
            {Array.from({ length: POOL_COUNT }, (_, i) => (
              <option key={i} value={i}>
                Pool {i}
              </option>
            ))}
          </select>
        </div>

        {error && (
          <div className="alert alert-error mb-4">
            <span>{error}</span>
          </div>
        )}

        {/* Pool info display */}
        <PoolInfo poolId={selectedPool} />

        {activeTab === "stake" ? (
          <>
            {/* Stake amount input */}
            <div className="form-control mb-4">
              <label className="label">
                <span className="label-text font-semibold">Amount (₸USD)</span>
              </label>
              <input
                type="text"
                placeholder="0.0"
                className="input input-bordered w-full"
                value={stakeAmount}
                onChange={e => setStakeAmount(e.target.value)}
              />
            </div>

            {/* Cooldown warning */}
            {hasCooldown && (
              <div className="alert alert-warning mb-4">
                <span>⏳ Cooldown active — {cooldownMinutes}m remaining</span>
              </div>
            )}

            {/* Stake button */}
            <button
              className={`btn btn-primary w-full ${isStaking ? "loading" : ""}`}
              disabled={!isOperator || isStaking || !stakeAmount || hasCooldown}
              onClick={handleStake}
            >
              {isStaking ? "Staking..." : `Stake ₸USD into Pool ${selectedPool}`}
            </button>
          </>
        ) : (
          <>
            {/* Unstake info */}
            <div className="alert alert-info mb-4">
              <span>Unstake withdraws your <strong>full balance + rewards</strong> from the selected pool. No cooldown required.</span>
            </div>

            {/* Unstake button */}
            <button
              className={`btn btn-secondary w-full ${isUnstaking ? "loading" : ""}`}
              disabled={!isOperator || isUnstaking}
              onClick={handleUnstake}
            >
              {isUnstaking ? "Unstaking..." : `Unstake from Pool ${selectedPool}`}
            </button>
          </>
        )}
      </div>
    </div>
  );
};

// Sub-component for pool info
const PoolInfo = ({ poolId }: { poolId: number }) => {
  return (
    <div className="bg-base-200 rounded-lg p-4 mb-4">
      <div className="text-sm">
        <span className="text-base-content/60">Selected:</span>
        <span className="ml-2 font-semibold">Pool {poolId}</span>
        <p className="text-xs text-base-content/50 mt-1">
          Staking contract: 0x2a70...89A
        </p>
      </div>
    </div>
  );
};

export default StakingPanel;
