// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Clones} from "openzeppelin-contracts/contracts/proxy/Clones.sol";
import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";

import {SharpFactsAggregator} from "../src/SharpFactsAggregator.sol";

/// @title AggregatorsFactory
/// @author Herodotus Dev
/// @notice A factory contract for creating new SharpFactsAggregator contracts
///         and upgrading new one's starter template
contract AggregatorsFactory is AccessControl {
    // Blank contract template address
    address public _template;

    // Timelock mechanism for upgrades proposals
    struct UpgradeProposalTimelock {
        uint256 timestamp;
        address newTemplate;
    }

    // Upgrades timelocks
    mapping(uint256 => UpgradeProposalTimelock) public upgrades;

    // Upgrades tracker
    uint256 public upgradesCount;

    // Delay before an upgrade can be performed
    uint256 public constant DELAY = 3 days;

    // Aggregators indexing
    uint256 public aggregatorsCount;

    // Aggregators by id
    mapping(uint256 => address) public aggregatorsById;

    // Access control
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // Default roots for new aggregators:
    // poseidon_hash("brave new world")
    bytes32 public constant POSEIDON_MMR_INITIAL_ROOT =
        0x02241b3b7f1c4b9cf63e670785891de91f7237b1388f6635c1898ae397ad32dd;

    // keccak_hash("brave new world")
    bytes32 public constant KECCAK_MMR_INITIAL_ROOT =
        0xce92cc894a17c107be8788b58092c22cd0634d1489ca0ce5b4a045a1ce31b168;

    // Events
    event UpgradeProposal(address newTemplate);
    event Upgrade(address oldTemplate, address newTemplate);
    event AggregatorCreation(address aggregator, uint256 aggregatorId);

    /// Creates a new Factory contract and grants OPERATOR_ROLE to the deployer
    /// @param template The address of the template contract to clone
    constructor(address template) {
        _template = template;

        _setRoleAdmin(OPERATOR_ROLE, OPERATOR_ROLE);
        _grantRole(OPERATOR_ROLE, _msgSender());
    }

    /// @notice Reverts if the caller is not an operator
    modifier onlyOperator() {
        require(
            hasRole(OPERATOR_ROLE, _msgSender()),
            "Caller is not an operator"
        );
        _;
    }

    /**
     * Creates a new aggregator contract by cloning the template contract
     * @param sharpFactsRegistry The address of the SharpFactsRegistry contract
     * @param programHash The hash of the program to compute facts from
     * @param aggregatorId The id of an existing aggregator to attach to (0 for none)
     */
    function createAggregator(
        address sharpFactsRegistry,
        bytes32 programHash,
        uint256 aggregatorId
    ) external onlyOperator returns (address) {
        SharpFactsAggregator.AggregatorState memory initialAggregatorState;

        if (aggregatorId != 0) {
            // Attach from existing aggregator
            require(aggregatorId <= aggregatorsCount, "Invalid aggregator ID");

            address existingAggregatorAddr = aggregatorsById[aggregatorId];
            require(
                existingAggregatorAddr != address(0),
                "Aggregator not found"
            );

            SharpFactsAggregator existingAggregator = SharpFactsAggregator(
                existingAggregatorAddr
            );
            initialAggregatorState = existingAggregator.getAggregatorState();
        } else {
            // Create a new aggregator (detach from existing ones)
            initialAggregatorState = SharpFactsAggregator.AggregatorState({
                poseidonMmrRoot: POSEIDON_MMR_INITIAL_ROOT,
                keccakMmrRoot: KECCAK_MMR_INITIAL_ROOT,
                mmrSize: 1,
                continuableParentHash: bytes32(0)
            });
        }

        // Initialize the newly created aggregator
        bytes memory data = abi.encodeWithSignature(
            "initialize(address,bytes32,(bytes32,bytes32,uint256,bytes32))",
            sharpFactsRegistry,
            programHash,
            initialAggregatorState
        );

        // Clone the template contract
        address clone = Clones.clone(_template);

        // The data is the encoded initialize function (with initial parameters)
        (bool success, ) = clone.call(data);

        require(success, "Aggregator initialization failed");

        aggregatorsById[++aggregatorsCount] = clone;

        emit AggregatorCreation(clone, aggregatorsCount);

        return clone;
    }

    /**
     * Proposes an upgrade to the template (blank aggregator) contract
     * @param newTemplate The address of the new template contract to use for future aggregators
     */
    function proposeUpgrade(address newTemplate) external onlyOperator {
        upgrades[++upgradesCount] = UpgradeProposalTimelock(
            block.timestamp + DELAY,
            newTemplate
        );

        emit UpgradeProposal(newTemplate);
    }

    /**
     * Upgrades the template (blank aggregator) contract
     * @param updateId The id of the upgrade proposal to execute
     */
    function upgrade(uint256 updateId) external onlyOperator {
        require(updateId <= upgradesCount, "Invalid updateId");

        uint256 timeLockTimestamp = upgrades[updateId].timestamp;
        require(timeLockTimestamp != 0, "TimeLock not set");
        require(block.timestamp >= timeLockTimestamp, "TimeLock not expired");

        address oldTemplate = _template;
        _template = upgrades[updateId].newTemplate;

        // Clear timelock
        upgrades[updateId] = UpgradeProposalTimelock(0, address(0));

        emit Upgrade(oldTemplate, _template);
    }
}