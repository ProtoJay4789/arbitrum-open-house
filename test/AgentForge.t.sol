// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AgentForge.sol";

contract AgentForgeTest is Test {
    AgentForge forge;

    address owner = makeAddr("owner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address agent1 = makeAddr("agent1");

    function setUp() public {
        // Deploy from a proper owner address
        vm.prank(owner);
        forge = new AgentForge();
        // Fund test addresses
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(agent1, 100 ether);
        vm.deal(owner, 100 ether);
    }

    // ─── Agent Registration ─────────────────────────────

    function test_RegisterAgent() public {
        vm.prank(agent1);
        forge.registerAgent("ipfs://QmAgent1Metadata");

        AgentForge.Agent memory agent = forge.getAgent(agent1);
        assertTrue(agent.registered);
        assertEq(agent.metadataURI, "ipfs://QmAgent1Metadata");
        assertEq(forge.agentCount(), 1);
    }

    function test_RevertRegisterDuplicate() public {
        vm.prank(agent1);
        forge.registerAgent("ipfs://QmAgent1");

        vm.prank(agent1);
        vm.expectRevert("Already registered");
        forge.registerAgent("ipfs://QmAgent1v2");
    }

    // ─── Task Creation ──────────────────────────────────

    function test_CreateTask() public {
        vm.prank(alice);
        forge.createTask{value: 0.1 ether}("Summarize this article");

        assertEq(forge.taskCount(), 1);

        AgentForge.Task memory task = forge.getTask(0);
        assertEq(task.poster, alice);
        assertEq(task.bounty, 0.1 ether);
        assertEq(uint8(task.status), uint8(AgentForge.TaskStatus.Open));
    }

    function test_RevertCreateTaskNoBounty() public {
        vm.prank(alice);
        vm.expectRevert("Bounty must be > 0");
        forge.createTask("Free work pls");
    }

    // ─── Task Claiming ──────────────────────────────────

    function test_ClaimTask() public {
        vm.prank(alice);
        forge.createTask{value: 0.05 ether}("Fetch latest ETH price");

        vm.prank(agent1);
        forge.registerAgent("ipfs://QmAgent1");

        vm.prank(agent1);
        forge.claimTask(0);

        AgentForge.Task memory task = forge.getTask(0);
        assertEq(uint8(task.status), uint8(AgentForge.TaskStatus.Claimed));
        assertEq(task.claimedBy, agent1);
    }

    function test_RevertClaimByUnregistered() public {
        vm.prank(alice);
        forge.createTask{value: 0.05 ether}("Do something");

        vm.prank(bob);
        vm.expectRevert("Agent not registered");
        forge.claimTask(0);
    }

    // ─── Task Completion + Bounty Release ───────────────

    function test_CompleteTaskAndReleaseBounty() public {
        // Setup
        vm.prank(agent1);
        forge.registerAgent("ipfs://QmAgent1");

        vm.prank(alice);
        forge.createTask{value: 1 ether}("Analyze this data");

        vm.prank(agent1);
        forge.claimTask(0);

        // Track balances
        uint256 agentBefore = agent1.balance;

        // Complete
        vm.prank(agent1);
        forge.completeTask(0, "ipfs://QmResultHash123");

        // Verify task
        AgentForge.Task memory task = forge.getTask(0);
        assertEq(uint8(task.status), uint8(AgentForge.TaskStatus.Completed));
        assertEq(task.resultHash, "ipfs://QmResultHash123");
        assertEq(task.bounty, 0);

        // Verify agent stats
        AgentForge.Agent memory agent = forge.getAgent(agent1);
        assertEq(agent.completedTasks, 1);
        assertEq(agent.reputation, 1);

        // Verify payout (1 ETH - 2% fee = 0.98 ETH)
        assertEq(agent1.balance - agentBefore, 0.98 ether);
    }

    // ─── Cancellation ───────────────────────────────────

    function test_CancelOpenTask() public {
        vm.prank(alice);
        forge.createTask{value: 0.5 ether}("Task I don't need anymore");

        uint256 aliceBefore = alice.balance;

        vm.prank(alice);
        forge.cancelTask(0);

        AgentForge.Task memory task = forge.getTask(0);
        assertEq(uint8(task.status), uint8(AgentForge.TaskStatus.Cancelled));
        assertEq(alice.balance - aliceBefore, 0.5 ether);
    }

    function test_RevertCancelClaimedTask() public {
        vm.prank(agent1);
        forge.registerAgent("ipfs://QmAgent1");

        vm.prank(alice);
        forge.createTask{value: 0.1 ether}("Task already claimed");

        vm.prank(agent1);
        forge.claimTask(0);

        vm.prank(alice);
        vm.expectRevert("Can only cancel open tasks");
        forge.cancelTask(0);
    }

    // ─── Full Flow ──────────────────────────────────────

    function test_FullAgentLifecycle() public {
        // 1. Register agent
        vm.prank(agent1);
        forge.registerAgent("ipfs://QmAgentFull");

        // 2. Create task
        vm.prank(alice);
        forge.createTask{value: 0.2 ether}("Fetch and summarize top 5 DeFi yields");

        // 3. Agent claims
        vm.prank(agent1);
        forge.claimTask(0);

        // 4. Agent completes
        vm.prank(agent1);
        forge.completeTask(0, "ipfs://QmDefiYieldsSummary");

        // 5. Verify history
        uint256[] memory history = forge.getAgentHistory(agent1);
        assertEq(history.length, 1);
        assertEq(history[0], 0);

        // 6. Create and complete another task
        vm.prank(alice);
        forge.createTask{value: 0.3 ether}("Monitor whale wallet activity");

        vm.prank(agent1);
        forge.claimTask(1);

        vm.prank(agent1);
        forge.completeTask(1, "ipfs://QmWhaleTracker");

        // 7. Check reputation grew
        AgentForge.Agent memory agent = forge.getAgent(agent1);
        assertEq(agent.completedTasks, 2);
        assertEq(agent.reputation, 2);

        history = forge.getAgentHistory(agent1);
        assertEq(history.length, 2);
    }
}
