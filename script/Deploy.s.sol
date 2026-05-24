// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/AgentForge.sol";

contract DeployAgentForge is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        AgentForge forge = new AgentForge();
        console.log("AgentForge deployed at:", address(forge));

        vm.stopBroadcast();
    }
}
