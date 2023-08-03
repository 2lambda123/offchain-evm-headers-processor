"use strict";
var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
var __generator = (this && this.__generator) || function (thisArg, body) {
    var _ = { label: 0, sent: function() { if (t[0] & 1) throw t[1]; return t[1]; }, trys: [], ops: [] }, f, y, t, g;
    return g = { next: verb(0), "throw": verb(1), "return": verb(2) }, typeof Symbol === "function" && (g[Symbol.iterator] = function() { return this; }), g;
    function verb(n) { return function (v) { return step([n, v]); }; }
    function step(op) {
        if (f) throw new TypeError("Generator is already executing.");
        while (g && (g = 0, op[0] && (_ = 0)), _) try {
            if (f = 1, y && (t = op[0] & 2 ? y["return"] : op[0] ? y["throw"] || ((t = y["return"]) && t.call(y), 0) : y.next) && !(t = t.call(y, op[1])).done) return t;
            if (y = 0, t) op = [op[0] & 2, t.value];
            switch (op[0]) {
                case 0: case 1: t = op; break;
                case 4: _.label++; return { value: op[1], done: false };
                case 5: _.label++; y = op[1]; op = [0]; continue;
                case 7: op = _.ops.pop(); _.trys.pop(); continue;
                default:
                    if (!(t = _.trys, t = t.length > 0 && t[t.length - 1]) && (op[0] === 6 || op[0] === 2)) { _ = 0; continue; }
                    if (op[0] === 3 && (!t || (op[1] > t[0] && op[1] < t[3]))) { _.label = op[1]; break; }
                    if (op[0] === 6 && _.label < t[1]) { _.label = t[1]; t = op; break; }
                    if (t && _.label < t[2]) { _.label = t[2]; _.ops.push(op); break; }
                    if (t[2]) _.ops.pop();
                    _.trys.pop(); continue;
            }
            op = body.call(thisArg, _);
        } catch (e) { op = [6, e]; y = 0; } finally { f = t = 0; }
        if (op[0] & 5) throw op[1]; return { value: op[0] ? op[1] : void 0, done: true };
    }
};
Object.defineProperty(exports, "__esModule", { value: true });
var fs = require("fs");
var BN = require("bn.js");
var ethers_1 = require("ethers");
function parseArgs(argv) {
    var outputsFileName = argv[2];
    if (!outputsFileName) {
        throw new Error("Missing outputs file name");
    }
    return {
        outputsFileName: outputsFileName,
    };
}
function loadJSONFile(filePath) {
    var jsonString = fs.readFileSync(filePath, "utf-8");
    var jsonData = JSON.parse(jsonString);
    return jsonData.map(function (output) { return ({
        blockNPlusOneParentHashLow: output.block_n_plus_one_parent_hash_low.toString(),
        blockNPlusOneParentHashHigh: output.block_n_plus_one_parent_hash_high.toString(),
        blockNMinusRPlusOneParentHashLow: output.block_n_minus_r_plus_one_parent_hash_low.toString(),
        blockNMinusRPlusOneParentHashHigh: output.block_n_minus_r_plus_one_parent_hash_high.toString(),
        mmrLastRootPoseidon: output.mmr_last_root_poseidon.toString(),
        mmrLastRootKeccakLow: output.mmr_last_root_keccak_low.toString(),
        mmrLastRootKeccakHigh: output.mmr_last_root_keccak_high.toString(),
        mmrLastLen: output.mmr_last_len.toString(),
        newMmrRootPoseidon: output.new_mmr_root_poseidon.toString(),
        newMmrRootKeccakLow: output.new_mmr_root_keccak_low.toString(),
        newMmrRootKeccakHigh: output.new_mmr_root_keccak_high.toString(),
        newMmrLen: output.new_mmr_len.toString(),
    }); });
}
// merges two uint128s (low, high) into one uint256.
// @param lower The lower uint128.
// @param upper The upper uint128.
function merge128(lower, upper) {
    // Create BN instances
    var lowerBN = new BN(lower);
    var upperBN = new BN(upper);
    // Shift upper by 128 bits to the left
    var shiftedUpper = upperBN.shln(128);
    // return (upper << 128) | lower
    return ethers_1.BigNumber.from(shiftedUpper.or(lowerBN).toString(10)).toHexString();
}
function bigNumberToHex32(value) {
    // Convert the BigNumber to a bytes array
    var valueBytes = ethers_1.utils.arrayify(value);
    // Calculate the number of bytes short of 32 we are
    var padding = new Uint8Array(32 - valueBytes.length);
    // Concatenate the padding and valueBytes
    var paddedValueBytes = ethers_1.utils.concat([padding, valueBytes]);
    // Convert to a hexadecimal string
    var hex = ethers_1.utils.hexlify(paddedValueBytes);
    return hex;
}
function numberStringToBytes32(numberAsString) {
    // Convert the number string to a BigNumber
    var numberAsBigNumber = ethers_1.BigNumber.from(numberAsString);
    // Convert the BigNumber to a zero-padded hex string
    var hexString = ethers_1.utils.hexZeroPad(numberAsBigNumber.toHexString(), 32);
    return hexString;
}
function main() {
    return __awaiter(this, void 0, void 0, function () {
        var outputsFileName, outputs, jobsOutputsPacked, jobsOutputs, types, encoder;
        return __generator(this, function (_a) {
            outputsFileName = parseArgs(process.argv).outputsFileName;
            outputs = loadJSONFile(outputsFileName);
            jobsOutputsPacked = outputs.map(function (output) {
                return ({
                    blockNPlusOneParentHash: merge128(output.blockNPlusOneParentHashLow, output.blockNPlusOneParentHashHigh),
                    blockNMinusRPlusOneParentHash: merge128(output.blockNMinusRPlusOneParentHashLow, output.blockNMinusRPlusOneParentHashHigh),
                    mmrPreviousRootPoseidon: bigNumberToHex32(ethers_1.BigNumber.from(output.mmrLastRootPoseidon)),
                    mmrPreviousRootKeccak: merge128(output.mmrLastRootKeccakLow, output.mmrLastRootKeccakHigh),
                    mmrNewRootPoseidon: bigNumberToHex32(ethers_1.BigNumber.from(output.newMmrRootPoseidon)),
                    mmrNewRootKeccak: merge128(output.newMmrRootKeccakLow, output.newMmrRootKeccakHigh),
                    mmrSizesPacked: merge128(output.mmrLastLen, output.newMmrLen),
                });
            });
            jobsOutputs = jobsOutputsPacked.map(function (output) { return Object.values(output); });
            types = [
                "bytes32",
                "bytes32",
                "bytes32",
                "bytes32",
                "bytes32",
                "bytes32",
                "uint256", // mmrLastLen + newMmrLen
            ];
            encoder = new ethers_1.utils.AbiCoder();
            console.log(encoder.encode(["tuple(".concat(types.join(), ")[]")], [jobsOutputs]));
            return [2 /*return*/];
        });
    });
}
main().catch(console.error);
