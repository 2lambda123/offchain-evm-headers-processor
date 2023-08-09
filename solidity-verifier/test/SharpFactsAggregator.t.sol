// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/SharpFactsAggregator.sol";
import "../src/lib/Uint256Splitter.sol";

contract SharpFactsAggregatorTest is Test {
    using Uint256Splitter for uint256;

    uint256 latestBlockNumber;

    SharpFactsAggregator public sharpFactsAggregator;

    event Aggregate(
        uint256 fromBlockNumberHigh,
        uint256 toBlockNumberLow,
        bytes32 poseidonMmrRoot,
        bytes32 keccakMmrRoot,
        uint256 mmrSize,
        bytes32 continuableParentHash
    );

    // poseidon_hash("brave new world")
    bytes32 public constant POSEIDON_MMR_INITIAL_ROOT =
        0x02241b3b7f1c4b9cf63e670785891de91f7237b1388f6635c1898ae397ad32dd;

    // keccak_hash("brave new world")
    bytes32 public constant KECCAK_MMR_INITIAL_ROOT =
        0xce92cc894a17c107be8788b58092c22cd0634d1489ca0ce5b4a045a1ce31b168;

    function setUp() public {
        // The config hereunder must be specified in `foundry.toml`:
        // [rpc_endpoints]
        // goerli="GOERLI_RPC_URL"
        vm.createSelectFork(vm.rpcUrl("goerli"));

        latestBlockNumber = block.number;

        SharpFactsAggregator.AggregatorState
            memory initialAggregatorState = SharpFactsAggregator
                .AggregatorState({
                    poseidonMmrRoot: POSEIDON_MMR_INITIAL_ROOT,
                    keccakMmrRoot: KECCAK_MMR_INITIAL_ROOT,
                    mmrSize: 1,
                    continuableParentHash: bytes32(0)
                });

        sharpFactsAggregator = new SharpFactsAggregator();

        // Ensure roles were not granted
        assertFalse(
            sharpFactsAggregator.hasRole(
                keccak256("OPERATOR_ROLE"),
                address(this)
            )
        );
        assertFalse(
            sharpFactsAggregator.hasRole(
                keccak256("UNLOCKER_ROLE"),
                address(this)
            )
        );
        assertFalse(
            sharpFactsAggregator.hasRole(
                keccak256("UPGRADER_ROLE"),
                address(this)
            )
        );

        sharpFactsAggregator.initialize(
            // Sharp Facts Registry (Goërli)
            0xAB43bA48c9edF4C2C4bB01237348D1D7B28ef168,
            // Program hash (prover)
            bytes32(
                uint(
                    0x21876b34efae7a9a59580c4fb0bfc7971aecebce6669a475171fe0423c0a784
                )
            ),
            // Initial aggregator state (empty trees)
            initialAggregatorState
        );

        // Ensure roles were successfuly granted
        assertTrue(
            sharpFactsAggregator.hasRole(
                keccak256("OPERATOR_ROLE"),
                address(this)
            )
        );
        assertTrue(
            sharpFactsAggregator.hasRole(
                keccak256("UNLOCKER_ROLE"),
                address(this)
            )
        );
        assertTrue(
            sharpFactsAggregator.hasRole(
                keccak256("UPGRADER_ROLE"),
                address(this)
            )
        );
    }

    function testVerifyInvalidFact() public {
        // Fake output
        uint256[] memory outputs = new uint256[](1);
        outputs[0] = 4242424242;

        assertFalse(sharpFactsAggregator.verifyFact(outputs));
    }

    function ensureGlobalStateCorrectness(
        SharpFactsAggregator.JobOutputPacked memory output
    ) internal view {
        (
            bytes32 poseidonMmrRoot,
            bytes32 keccakMmrRoot,
            uint256 mmrSize,
            bytes32 continuableParentHash
        ) = sharpFactsAggregator.aggregatorState();

        (, uint256 mmrNewSize) = output.mmrSizesPacked.split128();

        assert(poseidonMmrRoot == output.mmrNewRootPoseidon);
        assert(keccakMmrRoot == output.mmrNewRootKeccak);
        assert(mmrSize == mmrNewSize);
        assert(continuableParentHash == output.blockNMinusRPlusOneParentHash);
    }

    function testRealAggregateJobsFFI() public {
        vm.makePersistent(address(sharpFactsAggregator));

        uint256 firstRangeStartChildBlock = 20;
        uint256 secondRangeStartChildBlock = 30;

        uint256 pastBlockStart = firstRangeStartChildBlock + 50;
        // Start at block no. 70
        vm.rollFork(pastBlockStart);

        sharpFactsAggregator.registerNewRange(
            pastBlockStart - firstRangeStartChildBlock - 1
        );

        sharpFactsAggregator.registerNewRange(
            pastBlockStart - secondRangeStartChildBlock - 1
        );

        (
            bytes32 poseidonMmrRoot,
            bytes32 keccakMmrRoot,
            uint256 mmrSize,
            bytes32 continuableParentHash
        ) = sharpFactsAggregator.aggregatorState(); // Get initialized tree state

        string[] memory inputs = new string[](3);
        inputs[0] = "node";
        inputs[1] = "./helpers/compute-outputs.js";
        inputs[2] = "helpers/outputs_batch_alpha.json";
        bytes memory output = vm.ffi(inputs);

        SharpFactsAggregator.JobOutputPacked[] memory outputs = abi.decode(
            output,
            (SharpFactsAggregator.JobOutputPacked[])
        );

        SharpFactsAggregator.JobOutputPacked memory firstOutput = outputs[0];
        assert(mmrSize == 1); // New tree, with genesis element "brave new world" only
        assert(continuableParentHash == firstOutput.blockNPlusOneParentHash);
        assert(poseidonMmrRoot == firstOutput.mmrPreviousRootPoseidon);
        assert(keccakMmrRoot == firstOutput.mmrPreviousRootKeccak);

        vm.rollFork(latestBlockNumber);

        sharpFactsAggregator.aggregateSharpJobs(0, outputs);
        ensureGlobalStateCorrectness(outputs[outputs.length - 1]);

        string[] memory inputsExtended = new string[](3);
        inputsExtended[0] = "node";
        inputsExtended[1] = "./helpers/compute-outputs.js";
        inputsExtended[2] = "helpers/outputs_batch_alpha_extended.json";
        bytes memory outputExtended = vm.ffi(inputsExtended);

        SharpFactsAggregator.JobOutputPacked[] memory outputsExtended = abi
            .decode(outputExtended, (SharpFactsAggregator.JobOutputPacked[]));

        sharpFactsAggregator.aggregateSharpJobs(
            secondRangeStartChildBlock + 1,
            outputsExtended
        );
        ensureGlobalStateCorrectness(
            outputsExtended[outputsExtended.length - 1]
        );
    }
}