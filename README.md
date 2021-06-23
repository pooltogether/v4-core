# PoolTogether Contracts Template

[![Coverage Status](https://coveralls.io/repos/github/pooltogether/<NAME_OF_NEW_REPO>/badge.svg?branch=master)](https://coveralls.io/github/pooltogether/pooltogether-proxy-factory?branch=master)

![Tests](https://github.com/pooltogether/<NAME_OF_NEW_REPO>/actions/workflows/main.yml/badge.svg)

# Usage
1. Clone this repo 
1. Create repo using Github GUI
1. Set remote repo (`git remote add origin git@github.com:pooltogether/<NAME_OF_NEW_REPO>.git`),
1. Checkout a new branch (`git checkout -b name_of_new_branch`) 
1. Begin implementing as approriate.
1. Update this README


# Preset Packages
## Generic Proxy Factory
The minimal proxy factory is a powerful pattern used throughout PoolTogethers smart contracts. A [typescript package](https://www.npmjs.com/package/@pooltogether/pooltogether-proxy-factory-package) is available to use a generic deployed instance. This is typically used in the deployment script. 


## Generic Registry
The [generic registry](https://www.npmjs.com/package/@pooltogether/pooltogether-generic-registry) is a iterable singly linked list data structure that is commonly used throughout PoolTogethers contracts. Consider using this where appropriate or deploying in a seperate repo such as the (Prize Pool Registry)[https://github.com/pooltogether/pooltogether-prizepool-registry.



# Installation
Install the repo and dependencies by running:
`yarn`

## Deployment
These contracts can be deployed to a network by running:
`yarn deploy <networkName>`

# Testing
Run the unit tests locally with:
`yarn test`

## Coverage
Generate the test coverage report with:
`yarn coverage`