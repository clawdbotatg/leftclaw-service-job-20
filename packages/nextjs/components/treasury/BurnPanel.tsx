"use client";

import { useState } from "react";
import { parseEther } from "viem";
import { useAccount } from "wagmi";
import { useScaffoldReadContract, useScaffoldWriteContract } from "~~/hooks/scaffold-eth";

export const BurnPanel = () => {
  const { address } = useAccount();
  const [amount, setAmount] = useState("");

  const { data: isOperator } = useScaffoldReadContract({
    contractName: "TreasuryManagerV2",
    functionName: "isOperator",
    args: [address],
  });

  const { data: cooldownRemaining } = useScaffoldReadContract({
    contractName: "TreasuryManagerV2",
    functionName: "getCooldownRemaining",
  });

  const { writeContractAsync, isMining } = useScaffoldWriteContract("TreasuryManagerV2");

  const hasCooldown = cooldownRemaining !== undefined && cooldownRemaining > 0n;

  const handleBurn = async () => {
    if (!amount) return;
    try {
      await writeContractAsync({
        functionName: "burn",
        args: [parseEther(amount)],
      });
      setAmount("");
    } catch (e) {
      console.error("Burn failed:", e);
    }
  };

  return (
    <div className="card bg-base-100 shadow-xl">
      <div className="card-body">
        <h2 className="card-title text-2xl mb-4">
          🔥 Burn ₸USD
          {!isOperator && <span className="badge badge-warning ml-2">Operator Only</span>}
        </h2>

        <div className="form-control mb-4">
          <label className="label">
            <span className="label-text font-semibold">Amount to Burn (₸USD)</span>
            <span className="label-text-alt">Max: 100M per tx</span>
          </label>
          <input
            type="text"
            placeholder="0.0"
            className="input input-bordered w-full"
            value={amount}
            onChange={e => setAmount(e.target.value)}
          />
        </div>

        {hasCooldown && (
          <div className="alert alert-warning mb-4">
            <span>⏳ Cooldown active — {Math.ceil(Number(cooldownRemaining || 0n) / 60)}m remaining</span>
          </div>
        )}

        <div className="alert alert-error mb-4 opacity-70">
          <span>⚠️ Burn is irreversible. Tokens are sent to 0xdead.</span>
        </div>

        <button
          className={`btn btn-error w-full ${isMining ? "loading" : ""}`}
          disabled={!isOperator || isMining || !amount || hasCooldown}
          onClick={handleBurn}
        >
          {isMining ? "Burning..." : "Burn ₸USD"}
        </button>
      </div>
    </div>
  );
};

export default BurnPanel;
