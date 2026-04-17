// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title AgentForge
 * @notice On-chain marketplace where AI agents register, claim tasks, execute autonomously, and get paid.
 * @dev Built for ETHGlobal Open Agents Hackathon 2026
 */

contract AgentForge {
    // ─── State ──────────────────────────────────────────

    struct Agent {
        address owner;
        string metadataURI; // IPFS or URL with agent capabilities
        uint256 completedTasks;
        uint256 reputation;  // simple +1 per completed task
        bool registered;
    }

    enum TaskStatus { Open, Claimed, Completed, Cancelled }

    struct Task {
        uint256 id;
        address poster;
        string description;
        string resultHash;   // IPFS hash of agent's output
        uint256 bounty;
        TaskStatus status;
        address claimedBy;   // agent address
        uint256 createdAt;
        uint256 completedAt;
    }

    mapping(address => Agent) public agents;
    mapping(uint256 => Task) public tasks;
    mapping(address => uint256[]) public agentTaskHistory; // agent => task IDs

    uint256 public taskCount;
    uint256 public agentCount;

    address public owner;
    uint256 public platformFeePercent = 2; // 2% platform fee

    // ─── Events ─────────────────────────────────────────

    event AgentRegistered(address indexed agent, string metadataURI);
    event TaskCreated(uint256 indexed taskId, address indexed poster, string description, uint256 bounty);
    event TaskClaimed(uint256 indexed taskId, address indexed agent);
    event TaskCompleted(uint256 indexed taskId, address indexed agent, string resultHash);
    event TaskCancelled(uint256 indexed taskId);
    event BountyReleased(uint256 indexed taskId, address indexed agent, uint256 amount);

    // ─── Modifiers ──────────────────────────────────────

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlyRegisteredAgent() {
        require(agents[msg.sender].registered, "Agent not registered");
        _;
    }

    // ─── Constructor ────────────────────────────────────

    constructor() {
        owner = msg.sender;
    }

    // ─── Agent Functions ────────────────────────────────

    /**
     * @notice Register as an autonomous agent on-chain
     * @param _metadataURI Link to agent capabilities/config (IPFS or URL)
     */
    function registerAgent(string calldata _metadataURI) external {
        require(!agents[msg.sender].registered, "Already registered");
        require(bytes(_metadataURI).length > 0, "Metadata URI required");

        agents[msg.sender] = Agent({
            owner: msg.sender,
            metadataURI: _metadataURI,
            completedTasks: 0,
            reputation: 0,
            registered: true
        });
        agentCount++;

        emit AgentRegistered(msg.sender, _metadataURI);
    }

    /**
     * @notice Update agent metadata (capabilities, model info, etc.)
     */
    function updateAgentMetadata(string calldata _metadataURI) external onlyRegisteredAgent {
        agents[msg.sender].metadataURI = _metadataURI;
    }

    // ─── Task Functions ─────────────────────────────────

    /**
     * @notice Post a new task with ETH bounty
     * @param _description Human-readable task description
     */
    function createTask(string calldata _description) external payable {
        require(msg.value > 0, "Bounty must be > 0");
        require(bytes(_description).length > 0, "Description required");

        uint256 taskId = taskCount++;
        tasks[taskId] = Task({
            id: taskId,
            poster: msg.sender,
            description: _description,
            resultHash: "",
            bounty: msg.value,
            status: TaskStatus.Open,
            claimedBy: address(0),
            createdAt: block.timestamp,
            completedAt: 0
        });

        emit TaskCreated(taskId, msg.sender, _description, msg.value);
    }

    /**
     * @notice Agent claims an open task
     * @param _taskId The task to claim
     */
    function claimTask(uint256 _taskId) external onlyRegisteredAgent {
        Task storage task = tasks[_taskId];
        require(task.status == TaskStatus.Open, "Task not open");
        require(task.poster != msg.sender, "Cannot claim own task");

        task.status = TaskStatus.Claimed;
        task.claimedBy = msg.sender;

        emit TaskClaimed(_taskId, msg.sender);
    }

    /**
     * @notice Agent completes a claimed task and submits result hash
     * @param _taskId The completed task
     * @param _resultHash IPFS hash or URL of the agent's output
     */
    function completeTask(uint256 _taskId, string calldata _resultHash) external onlyRegisteredAgent {
        Task storage task = tasks[_taskId];
        require(task.status == TaskStatus.Claimed, "Task not claimed");
        require(task.claimedBy == msg.sender, "Not your task");
        require(bytes(_resultHash).length > 0, "Result hash required");

        task.status = TaskStatus.Completed;
        task.resultHash = _resultHash;
        task.completedAt = block.timestamp;

        // Update agent stats
        agents[msg.sender].completedTasks++;
        agents[msg.sender].reputation++;

        agentTaskHistory[msg.sender].push(_taskId);

        emit TaskCompleted(_taskId, msg.sender, _resultHash);

        // Auto-release bounty
        _releaseBounty(_taskId);
    }

    /**
     * @notice Task poster cancels an open/unclaimed task and gets refund
     */
    function cancelTask(uint256 _taskId) external {
        Task storage task = tasks[_taskId];
        require(task.poster == msg.sender, "Not your task");
        require(task.status == TaskStatus.Open, "Can only cancel open tasks");

        task.status = TaskStatus.Cancelled;
        uint256 refund = task.bounty;
        task.bounty = 0;

        (bool sent, ) = payable(msg.sender).call{value: refund}("");
        require(sent, "Refund failed");

        emit TaskCancelled(_taskId);
    }

    // ─── Internal ───────────────────────────────────────

    function _releaseBounty(uint256 _taskId) internal {
        Task storage task = tasks[_taskId];
        uint256 amount = task.bounty;
        require(amount > 0, "No bounty");

        task.bounty = 0;

        // Platform fee
        uint256 fee = (amount * platformFeePercent) / 100;
        uint256 payout = amount - fee;

        // Pay agent
        (bool sentAgent, ) = payable(task.claimedBy).call{value: payout}("");
        require(sentAgent, "Agent payout failed");

        // Pay platform
        if (fee > 0) {
            (bool sentFee, ) = payable(owner).call{value: fee}("");
            require(sentFee, "Fee payout failed");
        }

        emit BountyReleased(_taskId, task.claimedBy, payout);
    }

    // ─── View Functions ─────────────────────────────────

    function getAgent(address _agent) external view returns (Agent memory) {
        return agents[_agent];
    }

    function getTask(uint256 _taskId) external view returns (Task memory) {
        return tasks[_taskId];
    }

    function getAgentHistory(address _agent) external view returns (uint256[] memory) {
        return agentTaskHistory[_agent];
    }

    // ─── Admin ──────────────────────────────────────────

    function setPlatformFee(uint256 _feePercent) external onlyOwner {
        require(_feePercent <= 10, "Max 10%");
        platformFeePercent = _feePercent;
    }

    function withdraw() external onlyOwner {
        (bool sent, ) = payable(owner).call{value: address(this).balance}("");
        require(sent, "Withdraw failed");
    }

    // Accept ETH
    receive() external payable {}
}
