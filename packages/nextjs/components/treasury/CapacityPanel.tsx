"use client";

import { formatUnits } from "viem";
import { useScaffoldReadContract } from "~~/hooks/scaffold-eth";

export const CapacityPanel = () => {
  // Cooldown remaining
  const { data: cooldownRemaining } = useScaffoldReadContract({
    contractName: "TreasuryManagerV2",
    functionName: "getCooldownRemaining",
  });

  // Get operator
  const { data: operator } = useScaffoldReadContract({
    contractName: "TreasuryManagerV2",
    functionName: "operator",
  });

  // Daily used for BuybackWETH
  const { data: dailyUsedWETH } = useScaffoldReadContract({
    contractName: "TreasuryManagerV2",
    functionName: "getOperatorDailyUsed",
    args: [operator, 0], // ActionType.BuybackWETH = 0
  });

  // Daily used for Stake
  const { data: dailyUsedStake } = useScaffoldReadContract({
    contractName: "TreasuryManagerV2",
    functionName: "getOperatorDailyUsed",
    args: [operator, 3], // ActionType.Stake = 3
  });

  // Daily used for Burn
  const { data: dailyUsedBurn } = useScaffoldReadContract({
    contractName: "TreasuryManagerV2",
    functionName: "getOperatorDailyUsed",
    args: [operator, 2], // ActionType.Burn = 2
  });

  // Caps
  const { data: capsWETH } = useScaffoldReadContract({
    contractName: "TreasuryManagerV2",
    functionName: "getOperatorCaps",
    args: [0], // BuybackWETH
  });

  const { data: capsStake } = useScaffoldReadContract({
    contractName: "TreasuryManagerV2",
    functionName: "getOperatorCaps",
    args: [3], // Stake
  });

  const { data: capsBurn } = useScaffoldReadContract({
    contractName: "TreasuryManagerV2",
    functionName: "getOperatorCaps",
    args: [2], // Burn
  });

  const hasCooldown = cooldownRemaining !== undefined && cooldownRemaining > 0n;
  const cooldownMinutes = cooldownRemaining ? Math.ceil(Number(cooldownRemaining) / 60) : 0;
  const cooldownSeconds = cooldownRemaining ? Number(cooldownRemaining) % 60 : 0;

  const formatCap = (used: bigint | undefined, cap: readonly [bigint, bigint] | undefined, unit: string, decimals = 18) => {
    const usedVal = used ? Number(formatUnits(used, decimals)) : 0;
    const capVal = cap ? Number(formatUnits(cap[1], decimals)) : 0;
    const percentage = capVal > 0 ? (usedVal / capVal) * 100 : 0;

    return { usedVal, capVal, percentage, unit };
  };

  const wethCap = formatCap(dailyUsedWETH, capsWETH, "ETH");
  const stakeCap = formatCap(dailyUsedStake, capsStake, "₸USD");
  const burnCap = formatCap(dailyUsedBurn, capsBurn, "₸USD");

  return (
    <div className="card bg-base-100 shadow-xl">
      <div className="card-body">
        <h2 className="card-title text-2xl mb-4">📊 Capacity</h2>

        {/* Cooldown */}
        <div className="mb-4">
          <div className="flex justify-between items-center mb-1">
            <span className="font-semibold">Operator Cooldown</span>
            <span className={`badge ${hasCooldown ? "badge-warning" : "badge-success"}`}>
              {hasCooldown ? `${cooldownMinutes}m ${cooldownSeconds}s` : "Ready ✓"}
            </span>
          </div>
          {hasCooldown && (
            <progress
              className="progress progress-warning w-full"
              value={3600 - Number(cooldownRemaining || 0n)}
              max={3600}
            />
          )}
        </div>

        {/* Daily caps */}
        <div className="space-y-3">
          <CapBar label="Buyback (WETH)" {...wethCap} />
          <CapBar label="Stake (₸USD)" {...stakeCap} />
          <CapBar label="Burn (₸USD)" {...burnCap} />
        </div>

        {/* Operator address */}
        <div className="mt-4 pt-4 border-t border-base-300">
          <span className="text-xs text-base-content/60">Operator: </span>
          <span className="font-mono text-xs">{operator ? `${operator.slice(0, 6)}...${operator.slice(-4)}` : "Not set"}</span>
        </div>
      </div>
    </div>
  );
};

const CapBar = ({
  label,
  usedVal,
  capVal,
  percentage,
  unit,
}: {
  label: string;
  usedVal: number;
  capVal: number;
  percentage: number;
  unit: string;
}) => {
  const getColor = () => {
    if (percentage >= 90) return "progress-error";
    if (percentage >= 70) return "progress-warning";
    return "progress-success";
  };

  return (
    <div>
      <div className="flex justify-between text-sm mb-1">
        <span>{label}</span>
        <span className="font-mono">
          {usedVal.toLocaleString(undefined, { maximumFractionDigits: 4 })} / {capVal.toLocaleString(undefined, { maximumFractionDigits: 0 })} {unit}
        </span>
      </div>
      <progress className={`progress ${getColor()} w-full`} value={percentage} max={100} />
    </div>
  );
};

export default CapacityPanel;
