.DEFAULT_GOAL := l 

# Variable
contract_name:= "FixedRateStrategy"
eth_rpc := https://speedy-nodes-nyc.moralis.io/cede2bf2868b0e93070abef2/eth/mainnet

# Install
install:; yarn && forge install
clean:; rm -rf build/

# Utils
l:;		yarn lint && forge build

# require mythril docker image
myth:
	forge flatten src/$(contract_name).sol > flat/$(contract_name).sol
	docker run -v $(shell pwd):/tmp mythril/myth analyze /tmp/flat/$(contract_name).sol

# Forge
test:; 		forge test  -vvv --match-contract "FixedRateStrategyTest" # --gas-report 
test-fork:; forge test -vvv --fork-url $(eth_rpc) --match-contract "IntegrationTest"

