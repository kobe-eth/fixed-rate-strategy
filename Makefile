.DEFAULT_GOAL := l 
# Variable
contract_name:= "FixedRateStrategy"
install:; yarn && forge install
clean:; rm -rf build/
# Utils
l:;		yarn lint && forge build
# require mythril docker image
myth:
	forge flatten src/$(contract_name).sol > flat/$(contract_name).sol
	docker run -v $(shell pwd):/tmp mythril/myth analyze /tmp/flat/$(contract_name).sol
# Forge
test:; 		forge test  -vvv # --gas-report
