"use client";

import { useState } from "react";
import { formatEther, parseEther } from "viem";
import { useAccount } from "wagmi";
import { useScaffoldReadContract, useScaffoldWriteContract } from "~~/hooks/scaffold-eth";

const POOL_COUNT = 6; // Pools 0-5

export const StakingPanel = () => {
  const { address } = useAccount();
  const [selectedPool, setSelectedPool] = useState<number>(0);
  const [stakeAmount, setStakeAmount] = useState("");
  const [activeTab, setActiveTab] = useState<"stake" | "unstake">("stake");

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
    try {
      await writeStake({
        functionName: "stake",
        args: [parseEther(stakeAmount), BigInt(selectedPool)],
      });
      setStakeAmount("");
    } catch (e) {
      console.error("Stake failed:", e);
    }
  };

  const handleUnstake = async () => {
    try {
      await writeUnstake({
        functionName: "unstake",
        args: [BigInt(selectedPool)],
      });
    } catch (e) {
      console.error("Unstake failed:", e);
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
  const { data: poolInfo } = useScaffoldReadContract({
    contractName: "StakingContract",
    functionName: "poolInfo",
    args: [BigInt(poolId)],
  });

  if (!poolInfo) {
    return (
      <div className="bg-base-200 rounded-lg p-3 mb-4 animate-pulse">
        <div className="h-4 bg-base-300 rounded w-3/4 mb-2"></div>
        <div className="h-4 bg-base-300 rounded w-1/2"></div>
      </div>
    );
  }

  const [
    , // stakingToken
    , // rewardToken
    , // lastRewardTimestamp
    , // accRewardPerShare
    , // startTimestamp
    endTimestamp,
    , // precision
    totalStaked,
    totalRewards,
    , // feeCollector
  ] = poolInfo;

  const totalStakedFormatted = formatEther(totalStaked);
  const totalRewardsFormatted = formatEther(totalRewards);
  const endDate = new Date(Number(endTimestamp) * 1000);
  const isActive = Number(endTimestamp) > Date.now() / 1000;

  return (
    <div className="bg-base-200 rounded-lg p-4 mb-4">
      <div className="grid grid-cols-2 gap-2 text-sm">
        <div>
          <span className="text-base-content/60">Total Staked:</span>
          <p className="font-mono font-semibold">
            {Number(totalStakedFormatted).toLocaleString(undefined, { maximumFractionDigits: 2 })} ₸USD
          </p>
        </div>
        <div>
          <span className="text-base-content/60">Total Rewards:</span>
          <p className="font-mono font-semibold">
            {Number(totalRewardsFormatted).toLocaleString(undefined, { maximumFractionDigits: 2 })} ₸USD
          </p>
        </div>
        <div>
          <span className="text-base-content/60">Status:</span>
          <p>
            <span className={`badge ${isActive ? "badge-success" : "badge-error"} badge-sm`}>
              {isActive ? "Active" : "Ended"}
            </span>
          </p>
        </div>
        <div>
          <span className="text-base-content/60">End Date:</span>
          <p className="font-mono text-xs">{endDate.toLocaleDateString()}</p>
        </div>
      </div>
    </div>
  );
};

export default StakingPanel;
