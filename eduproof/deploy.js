const fs = require('fs');
const path = require('path');
const solc = require('solc');
const { ethers } = require('ethers');

async function main() {
    const contractPath = path.resolve(__dirname, 'contracts', 'SoulboundDiplomas.sol');
    const source = fs.readFileSync(contractPath, 'utf8');

    const input = {
        language: 'Solidity',
        sources: {
            'SoulboundDiplomas.sol': {
                content: source,
            },
        },
        settings: {
            optimizer: {
                enabled: true,
                runs: 200
            },
            evmVersion: 'paris',
            outputSelection: {
                '*': {
                    '*': ['abi', 'evm.bytecode'],
                },
            },
        },
    };

    console.log('Compiling...');
    const output = JSON.parse(solc.compile(JSON.stringify(input)));

    if (output.errors) {
        output.errors.forEach(err => console.error(err.formattedMessage));
    }

    const contractData = output.contracts['SoulboundDiplomas.sol']['SoulboundDiplomas'];
    const abi = contractData.abi;
    const bytecode = contractData.evm.bytecode.object;

    // Connect to Ganache
    const provider = new ethers.JsonRpcProvider('http://localhost:8545');

    const wallet = new ethers.Wallet('0x6f2eeb0b12edb7a87f147bb1725010f05eda1aea3a2af6063f92fe53ea251f5a', provider); // Account (0)

    console.log('Deploying...');
    const factory = new ethers.ContractFactory(abi, bytecode, wallet);
    const contract = await factory.deploy({
        gasLimit: 6000000
    });
    await contract.waitForDeployment();

    const address = await contract.getAddress();
    console.log('Contract deployed to:', address);

    // Save ABI and Address for Frontend
    fs.writeFileSync('ui/contract-info.js', `
        const contractAddress = "${address}";
        const contractABI = ${JSON.stringify(abi)};
    `);
    console.log('Contract info saved to ui/contract-info.js');

    // Automatically update the HTML cache buster string natively
    try {
        let htmlContent = fs.readFileSync('ui/index.html', 'utf8');
        htmlContent = htmlContent.replace(/contract-info\.js\?v=[^"']*/g, 'contract-info.js?v=' + Date.now());
        fs.writeFileSync('ui/index.html', htmlContent);
        console.log('Successfully updated cache-buster in index.html to ensure live contract data is fetched.');
    } catch (e) {
        console.error('Failed to update cache buster:', e);
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
