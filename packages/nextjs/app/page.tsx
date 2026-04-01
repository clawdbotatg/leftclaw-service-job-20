"use client";

import { useState } from "react";
import { useAccount } from "wagmi";
import { useScaffoldReadContract } from "~~/hooks/scaffold-eth";
import { StakingPanel } from "~~/components/treasury/StakingPanel";
import { CapacityPanel } from "~~/components/treasury/CapacityPanel";
import { BuybackPanel } from "~~/components/treasury/BuybackPanel";
import { BurnPanel } from "~~/components/treasury/BurnPanel";
import { RebalancePanel } from "~~/components/treasury/RebalancePanel";
import type { NextPage } from "next";

type Tab = "staking" | "buyback" | "burn" | "rebalance";

const Home: NextPage = () => {
  const { address: connectedAddress, isConnected } = useAccount();
  const [activeTab, setActiveTab] = useState<Tab>("staking");

  const { data: isOperator } = useScaffoldReadContract({
    contractName: "TreasuryManagerV2",
    functionName: "isOperator",
    args: [connectedAddress],
  });

  const { data: owner } = useScaffoldReadContract({
    contractName: "TreasuryManagerV2",
    functionName: "owner",
  });

  const tabs: { id: Tab; label: string; icon: string }[] = [
    { id: "staking", label: "Staking", icon: "🥩" },
    { id: "buyback", label: "Buyback", icon: "💰" },
    { id: "burn", label: "Burn", icon: "🔥" },
    { id: "rebalance", label: "Rebalance", icon: "♻️" },
  ];

  return (
    <div className="flex flex-col items-center grow">
      {/* Header */}
      <div className="w-full bg-gradient-to-r from-base-300 to-base-200 py-8 px-4">
        <div className="max-w-6xl mx-auto">
          <h1 className="text-3xl font-bold mb-2">
            🏦 ₸USD Treasury Manager
          </h1>
          <p className="text-base-content/70 text-lg">
            Operated by AMI — Artificial Monetary Intelligence
          </p>

          {/* Connection status */}
          <div className="flex items-center gap-4 mt-4 flex-wrap">
            {isConnected ? (
              <>
                <div className="badge badge-lg">
                  {connectedAddress?.slice(0, 6)}...{connectedAddress?.slice(-4)}
                </div>
                {isOperator && (
                  <div className="badge badge-success badge-lg gap-1">
                    ✓ Operator
                  </div>
                )}
                {connectedAddress === owner && (
                  <div className="badge badge-primary badge-lg gap-1">
                    👑 Owner
                  </div>
                )}
                {!isOperator && connectedAddress !== owner && (
                  <div className="badge badge-ghost badge-lg">
                    Viewer (Permissionless actions available)
                  </div>
                )}
              </>
            ) : (
              <div className="badge badge-warning badge-lg">
                Connect wallet to interact
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Main content */}
      <div className="w-full max-w-6xl px-4 py-6">
        {/* Tab navigation */}
        <div className="tabs tabs-boxed mb-6 flex justify-center">
          {tabs.map(tab => (
            <button
              key={tab.id}
              className={`tab tab-lg ${activeTab === tab.id ? "tab-active" : ""}`}
              onClick={() => setActiveTab(tab.id)}
            >
              <span className="mr-1">{tab.icon}</span> {tab.label}
            </button>
          ))}
        </div>

        {/* Two-column layout */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Main panel — 2/3 width */}
          <div className="lg:col-span-2">
            {activeTab === "staking" && <StakingPanel />}
            {activeTab === "buyback" && <BuybackPanel />}
            {activeTab === "burn" && <BurnPanel />}
            {activeTab === "rebalance" && <RebalancePanel />}
          </div>

          {/* Sidebar — capacity panel */}
          <div className="lg:col-span-1">
            <CapacityPanel />

            {/* Contract info */}
            <div className="card bg-base-100 shadow-xl mt-6">
              <div className="card-body">
                <h2 className="card-title text-lg">📋 Contract Info</h2>
                <div className="text-sm space-y-2">
                  <div>
                    <span className="text-base-content/60">Network:</span>
                    <span className="ml-2 font-semibold">Base</span>
                  </div>
                  <div>
                    <span className="text-base-content/60">Staking:</span>
                    <span className="ml-2 font-mono text-xs">0x2a70...89A</span>
                  </div>
                  <div>
                    <span className="text-base-content/60">₸USD:</span>
                    <span className="ml-2 font-mono text-xs">0xcb8D...c76</span>
                  </div>
                  <div>
                    <span className="text-base-content/60">Slippage:</span>
                    <span className="ml-2 font-semibold">3%</span>
                  </div>
                  <div>
                    <span className="text-base-content/60">Cooldown:</span>
                    <span className="ml-2 font-semibold">60 min</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Home;
