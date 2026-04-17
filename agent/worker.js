/**
 * AgentForge — Autonomous Agent Worker
 * 
 * Monitors TaskBoard for new tasks, claims them, executes, and submits results.
 * This is the "agent" half of the Open Agents demo.
 * 
 * Usage:
 *   PRIVATE_KEY=0x... RPC_URL=https://... CONTRACT=0x... node agent/worker.js
 */

const { ethers } = require("ethers");

// ─── Config ───────────────────────────────────────────────

const PRIVATE_KEY = process.env.PRIVATE_KEY;
const RPC_URL = process.env.RPC_URL || "https://rpc.sepolia.org";
const CONTRACT_ADDRESS = process.env.CONTRACT;

if (!PRIVATE_KEY || !CONTRACT_ADDRESS) {
    console.error("Set PRIVATE_KEY and CONTRACT env vars");
    process.exit(1);
}

const CONTRACT_ABI = [
    "function registerAgent(string _metadataURI) external",
    "function claimTask(uint256 _taskId) external",
    "function completeTask(uint256 _taskId, string _resultHash) external",
    "function tasks(uint256) view returns (uint256 id, address poster, string description, string resultHash, uint256 bounty, uint8 status, address claimedBy, uint256 createdAt, uint256 completedAt)",
    "function taskCount() view returns (uint256)",
    "function agents(address) view returns (address owner, string metadataURI, uint256 completedTasks, uint256 reputation, bool registered)",
    "event TaskCreated(uint256 indexed taskId, address indexed poster, string description, uint256 bounty)",
    "event TaskClaimed(uint256 indexed taskId, address indexed agent)",
];

// ─── Agent Logic ──────────────────────────────────────────

class AgentForgeWorker {
    constructor() {
        this.provider = new ethers.JsonRpcProvider(RPC_URL);
        this.wallet = new ethers.Wallet(PRIVATE_KEY, this.provider);
        this.contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, this.wallet);
        this.processing = new Set(); // Track tasks we're working on
    }

    async start() {
        console.log(`🤖 Agent worker starting...`);
        console.log(`   Wallet: ${this.wallet.address}`);
        console.log(`   Contract: ${CONTRACT_ADDRESS}`);

        // Register as agent if not already
        await this.ensureRegistered();

        // Listen for new tasks
        this.contract.on("TaskCreated", async (taskId, poster, description, bounty) => {
            const id = Number(taskId);
            console.log(`\n📋 New task #${id}: "${description}" (${ethers.formatEther(bounty)} ETH)`);
            
            if (!this.processing.has(id)) {
                await this.tryClaimTask(id);
            }
        });

        console.log("\n👂 Listening for new tasks...\n");

        // Also check for existing open tasks
        await this.scanExistingTasks();
    }

    async ensureRegistered() {
        const agent = await this.contract.agents(this.wallet.address);
        if (agent.registered) {
            console.log("✅ Already registered as agent");
            return;
        }

        console.log("📝 Registering as agent...");
        const tx = await this.contract.registerAgent(
            "ipfs://QmAgentForgeWorker-v1"
        );
        await tx.wait();
        console.log("✅ Registered!");
    }

    async scanExistingTasks() {
        const count = await this.contract.taskCount();
        console.log(`📊 Found ${count} total tasks, checking for open ones...`);

        for (let i = 0; i < Number(count); i++) {
            const task = await this.contract.tasks(i);
            // status 0 = Open
            if (Number(task.status) === 0 && !this.processing.has(i)) {
                console.log(`📋 Open task #${i}: "${task.description}"`);
                await this.tryClaimTask(i);
            }
        }
    }

    async tryClaimTask(taskId) {
        this.processing.add(taskId);
        try {
            console.log(`⚡ Claiming task #${taskId}...`);
            const tx = await this.contract.claimTask(taskId);
            await tx.wait();
            console.log(`✅ Claimed task #${taskId}`);

            // Execute the task
            await this.executeTask(taskId);
        } catch (e) {
            console.error(`❌ Failed to claim task #${taskId}:`, e.message);
            this.processing.delete(taskId);
        }
    }

    async executeTask(taskId) {
        try {
            const task = await this.contract.tasks(taskId);
            console.log(`🧠 Executing task #${taskId}: "${task.description}"`);

            // ─── AI Processing Placeholder ─────────────
            // In production, this would call an LLM, fetch data, etc.
            // For the hackathon demo, we simulate agent work.
            
            const result = await this.simulateAgentWork(task.description);
            console.log(`📤 Result: ${result}`);

            // Submit result on-chain
            console.log(`⛓️ Submitting result on-chain...`);
            const tx = await this.contract.completeTask(taskId, result);
            await tx.wait();
            console.log(`💰 Task #${taskId} completed! Bounty released.`);

        } catch (e) {
            console.error(`❌ Task #${taskId} execution failed:`, e.message);
        } finally {
            this.processing.delete(taskId);
        }
    }

    /**
     * Simulates AI agent work. Replace with real LLM calls for production.
     */
    async simulateAgentWork(description) {
        // Simulate processing time
        await new Promise(r => setTimeout(r, 2000));

        // Generate a fake IPFS CID as the "result"
        const hash = ethers.keccak256(
            ethers.toUtf8Bytes(description + Date.now().toString())
        );
        return `ipfs://Qm${hash.slice(2, 48)}`;
    }
}

// ─── Main ─────────────────────────────────────────────────

const worker = new AgentForgeWorker();
worker.start().catch(console.error);
