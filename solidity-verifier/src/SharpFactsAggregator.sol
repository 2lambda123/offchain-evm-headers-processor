// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";

import {IFactsRegistry} from "./interfaces/IFactsRegistry.sol";
import {Uint256Splitter} from "./lib/Uint256Splitter.sol";

///------------------
/// @title SharpFactsAggregator
/// @author Herodotus Dev
/// @notice Terminology:
/// `n` is the highest block number within the proving range
/// `r` is the number of blocks processed on a single SHARP job execution
/// ------------------
/// Example:
/// Blocks inside brackets are the ones processed during their SHARP job execution
//  7 [8 9 10] 11
/// n = 10
/// r = 3
/// `blockNMinusRPlusOneParentHash` = 8.parentHash (oldestHash)
/// `blockNPlusOneParentHash`       = 11.parentHash (newestHash)
/// ------------------
contract SharpFactsAggregator is Initializable, AccessControlUpgradeable {
    // Inline library to pack/unpack uin256 into 2 uint128 and vice versa
    using Uint256Splitter for uint256;

    // Access control
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant UNLOCKER_ROLE = keccak256("UNLOCKER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // Sharp Facts Registry
    address public FACTS_REGISTY;

    // Proving program hash
    bytes32 public PROGRAM_HASH;

    // Global aggregator state
    struct AggregatorState {
        bytes32 poseidonMmrRoot;
        bytes32 keccakMmrRoot;
        uint256 mmrSize;
        bytes32 continuableParentHash;
    }

    // Contract state
    AggregatorState public aggregatorState;

    // Block number to parent hash tracker
    mapping(uint256 => bytes32) public blockNumberToParentHash;

    bool public isOperatorRequired = true;

    // Cairo program's output
    struct JobOutput {
        uint256 fromBlockNumberHigh;
        uint256 toBlockNumberLow;
        bytes32 blockNPlusOneParentHashLow;
        bytes32 blockNPlusOneParentHashHigh;
        bytes32 blockNMinusRPlusOneParentHashLow;
        bytes32 blockNMinusRPlusOneParentHashHigh;
        bytes32 mmrPreviousRootPoseidon;
        bytes32 mmrPreviousRootKeccakLow;
        bytes32 mmrPreviousRootKeccakHigh;
        uint256 mmrPreviousSize;
        bytes32 mmrNewRootPoseidon;
        bytes32 mmrNewRootKeccakLow;
        bytes32 mmrNewRootKeccakHigh;
        uint256 mmrNewSize;
    }

    // Cairo program's output (packed)
    struct JobOutputPacked {
        uint256 blockNumbersPacked;
        bytes32 blockNPlusOneParentHash;
        bytes32 blockNMinusRPlusOneParentHash;
        bytes32 mmrPreviousRootPoseidon;
        bytes32 mmrPreviousRootKeccak;
        bytes32 mmrNewRootPoseidon;
        bytes32 mmrNewRootKeccak;
        uint256 mmrSizesPacked;
    }

    // Errors
    error AggregationPoseidonRootMismatch();
    error AggregationKeccakRootMismatch();
    error AggregationSizeMismatch();
    error AggregationErrorParentHashMismatch();
    error InvalidFact();
    error UnknownParentHash();
    error NotEnoughJobs();
    error NotEnoughBlockConfirmations();
    error TooMuchBlockConfirmations();
    error AggregationBlockMismatch();
    error GenesisBlockReached();

    // Events
    event NewRangeRegistered(
        uint256 targetBlock,
        bytes32 targetBlockParentHash
    );

    // Aggregation
    event Aggregate(
        uint256 fromBlockNumberHigh,
        uint256 toBlockNumberLow,
        bytes32 poseidonMmrRoot,
        bytes32 keccakMmrRoot,
        uint256 mmrSize,
        bytes32 continuableParentHash
    );

    /// @notice Initialize the contract
    function initialize(
        address factRegistry,
        bytes32 programHash,
        AggregatorState calldata initialAggregatorState
    ) public initializer {
        __AccessControl_init();

        // SHARP facts registry
        FACTS_REGISTY = factRegistry;

        // Proving program hash
        PROGRAM_HASH = programHash;

        aggregatorState = initialAggregatorState;

        _setRoleAdmin(OPERATOR_ROLE, OPERATOR_ROLE);
        _setRoleAdmin(UNLOCKER_ROLE, OPERATOR_ROLE);
        _setRoleAdmin(UPGRADER_ROLE, OPERATOR_ROLE);

        // Grant operator role to the contract deployer
        // to be able to define new aggregate ranges
        _grantRole(OPERATOR_ROLE, _msgSender());
        _grantRole(UNLOCKER_ROLE, _msgSender());
        _grantRole(UPGRADER_ROLE, _msgSender());
    }

    modifier onlyOperator() {
        if (isOperatorRequired) {
            require(
                hasRole(OPERATOR_ROLE, _msgSender()),
                "Caller is not an operator"
            );
        }
        _;
    }

    modifier onlyUnlocker() {
        require(
            hasRole(UNLOCKER_ROLE, _msgSender()),
            "Caller is not an unlocker"
        );
        _;
    }

    function setOperatorRequired(
        bool _isOperatorRequired
    ) external onlyUnlocker {
        isOperatorRequired = _isOperatorRequired;
    }

    /// @notice Extends the proving range to be able to process newer blocks
    function registerNewRange(
        uint256 blocksConfirmations
    ) external onlyOperator {
        if (blocksConfirmations < 20) {
            revert NotEnoughBlockConfirmations();
        }
        if (blocksConfirmations > 255) {
            revert TooMuchBlockConfirmations();
        }

        uint256 targetBlock = block.number - blocksConfirmations;
        bytes32 targetBlockParentHash = blockhash(targetBlock - 1);
        if (targetBlockParentHash == bytes32(0)) {
            revert UnknownParentHash();
        }

        blockNumberToParentHash[targetBlock] = targetBlockParentHash;

        // Initialize `continuableParentHash` if it's the very first aggregation
        if (
            aggregatorState.mmrSize == 1 &&
            aggregatorState.continuableParentHash == bytes32(0)
        ) {
            aggregatorState.continuableParentHash = targetBlockParentHash;
        }

        emit NewRangeRegistered(targetBlock, targetBlockParentHash);
    }

    /// @notice Aggregate SHARP jobs outputs (min. 2) to update the global aggregator state
    function aggregateSharpJobs(
        uint256 rightBoundStartBlock,
        JobOutputPacked[] calldata outputs
    ) external {
        if (outputs.length < 1) {
            revert NotEnoughJobs();
        }

        bytes32 rightBoundStartBlockParentHash = bytes32(0);
        // Start from a different block than the current state if `rightBoundStartBlock` is specified
        if (rightBoundStartBlock != 0) {
            rightBoundStartBlockParentHash = blockNumberToParentHash[
                rightBoundStartBlock
            ];
            if (rightBoundStartBlockParentHash == bytes32(0)) {
                revert UnknownParentHash();
            }
        }

        // Ensure the first job is correctly linked with the current state
        JobOutputPacked calldata firstOutput = outputs[0];
        ensureContinuable(rightBoundStartBlockParentHash, firstOutput);

        if (outputs.length > 1) {
            // Iterate over the jobs outputs (aside from first and last)
            // and ensure jobs are correctly linked
            for (uint256 i = 0; i < outputs.length - 1; ++i) {
                JobOutputPacked calldata curOutput = outputs[i];
                JobOutputPacked calldata nextOutput = outputs[i + 1];

                ensureValidFact(curOutput);
                ensureConsecutiveJobs(curOutput, nextOutput);
            }
        }

        JobOutputPacked calldata lastOutput = outputs[outputs.length - 1];
        ensureValidFact(lastOutput);

        // We save the latest output in the contract state for future calls
        (, uint256 mmrNewSize) = lastOutput.mmrSizesPacked.split128();
        aggregatorState.poseidonMmrRoot = lastOutput.mmrNewRootPoseidon;
        aggregatorState.keccakMmrRoot = lastOutput.mmrNewRootKeccak;
        aggregatorState.mmrSize = mmrNewSize;
        aggregatorState.continuableParentHash = lastOutput
            .blockNMinusRPlusOneParentHash;

        (uint256 fromBlock, ) = firstOutput.blockNumbersPacked.split128();
        (, uint256 toBlock) = lastOutput.blockNumbersPacked.split128();

        emit Aggregate(
            fromBlock,
            toBlock,
            lastOutput.mmrNewRootPoseidon,
            lastOutput.mmrNewRootKeccak,
            mmrNewSize,
            lastOutput.blockNMinusRPlusOneParentHash
        );
    }

    /// @notice Ensures the fact is registered on SHARP Facts Registry
    function ensureValidFact(JobOutputPacked memory output) internal view {
        (uint256 fromBlock, uint256 toBlock) = output
            .blockNumbersPacked
            .split128();

        (uint256 mmrPreviousSize, uint256 mmrNewSize) = output
            .mmrSizesPacked
            .split128();
        (
            uint256 blockNPlusOneParentHashLow,
            uint256 blockNPlusOneParentHashHigh
        ) = uint256(output.blockNPlusOneParentHash).split128();
        (
            uint256 blockNMinusRPlusOneParentHashLow,
            uint256 blockNMinusRPlusOneParentHashHigh
        ) = uint256(output.blockNMinusRPlusOneParentHash).split128();

        (
            uint256 mmrPreviousRootKeccakLow,
            uint256 mmrPreviousRootKeccakHigh
        ) = uint256(output.mmrPreviousRootKeccak).split128();
        (uint256 mmrNewRootKeccakLow, uint256 mmrNewRootKeccakHigh) = uint256(
            output.mmrNewRootKeccak
        ).split128();

        uint256[] memory outputs = new uint256[](14);
        outputs[0] = fromBlock;
        outputs[1] = toBlock;
        outputs[2] = blockNPlusOneParentHashLow;
        outputs[3] = blockNPlusOneParentHashHigh;
        outputs[4] = blockNMinusRPlusOneParentHashLow;
        outputs[5] = blockNMinusRPlusOneParentHashHigh;
        outputs[6] = uint256(output.mmrPreviousRootPoseidon);
        outputs[7] = mmrPreviousRootKeccakLow;
        outputs[8] = mmrPreviousRootKeccakHigh;
        outputs[9] = mmrPreviousSize;
        outputs[10] = uint256(output.mmrNewRootPoseidon);
        outputs[11] = mmrNewRootKeccakLow;
        outputs[12] = mmrNewRootKeccakHigh;
        outputs[13] = mmrNewSize;

        // We hash the output
        bytes32 outputHash = keccak256(abi.encodePacked(outputs));
        // We compute the deterministic fact bytes32 value
        bytes32 fact = keccak256(abi.encode(PROGRAM_HASH, outputHash));

        // We ensure this fact has been registered on SHARP Facts Registry
        if (!IFactsRegistry(FACTS_REGISTY).isValid(fact)) {
            revert InvalidFact();
        }
    }

    /// @notice Ensures the job output is correctly linked with the current contract storage
    function ensureContinuable(
        bytes32 rightBoundStartParentHash,
        JobOutputPacked memory output
    ) internal view {
        (uint256 mmrPreviousSize, ) = output.mmrSizesPacked.split128();

        if (output.mmrPreviousRootPoseidon != aggregatorState.poseidonMmrRoot)
            revert AggregationPoseidonRootMismatch();

        if (output.mmrPreviousRootKeccak != aggregatorState.keccakMmrRoot)
            revert AggregationKeccakRootMismatch();

        if (mmrPreviousSize != aggregatorState.mmrSize)
            revert AggregationSizeMismatch();

        if (
            rightBoundStartParentHash != bytes32(0) &&
            output.blockNPlusOneParentHash != rightBoundStartParentHash
        ) {
            revert AggregationErrorParentHashMismatch();
        } else if (rightBoundStartParentHash == bytes32(0)) {
            if (
                output.blockNPlusOneParentHash !=
                aggregatorState.continuableParentHash
            ) revert AggregationErrorParentHashMismatch();
        }
    }

    /// @notice Ensures the job outputs are correctly linked
    function ensureConsecutiveJobs(
        JobOutputPacked memory output,
        JobOutputPacked memory nextOutput
    ) internal pure {
        (, uint256 toBlock) = output.blockNumbersPacked.split128();

        // Cannot aggregate further than the genesis block
        if (toBlock == 0) {
            revert GenesisBlockReached();
        }

        (uint256 nextFromBlock, ) = nextOutput.blockNumbersPacked.split128();

        if (toBlock - 1 != nextFromBlock) revert AggregationBlockMismatch();

        (, uint256 outputMmrNewSize) = output.mmrSizesPacked.split128();
        (uint256 nextOutputMmrPreviousSize, ) = nextOutput
            .mmrSizesPacked
            .split128();

        if (output.mmrNewRootPoseidon != nextOutput.mmrPreviousRootPoseidon)
            revert AggregationPoseidonRootMismatch();

        if (output.mmrNewRootKeccak != nextOutput.mmrPreviousRootKeccak)
            revert AggregationKeccakRootMismatch();

        if (outputMmrNewSize != nextOutputMmrPreviousSize)
            revert AggregationSizeMismatch();

        if (
            output.blockNMinusRPlusOneParentHash !=
            nextOutput.blockNPlusOneParentHash
        ) revert AggregationErrorParentHashMismatch();
    }

    /// @dev Helper function to verify a fact based on a job output
    function verifyFact(uint256[] memory outputs) public view returns (bool) {
        bytes32 outputHash = keccak256(abi.encodePacked(outputs));
        bytes32 fact = keccak256(abi.encode(PROGRAM_HASH, outputHash));

        bool isValidFact = IFactsRegistry(FACTS_REGISTY).isValid(fact);
        return isValidFact;
    }

    /// @notice Returns the current aggregator state
    function getAggregatorState() public view returns (AggregatorState memory) {
        return aggregatorState;
    }
}
