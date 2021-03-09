# lambda-layers

Scripts to build python AWS Lambda layers and publish to AWS for use.

This also prunes the packages to remove some of the heavy weight of some large libaries such as pandas or scipy.

Inspired by the [model-zoo scripts](https://github.com/model-zoo/scikit-learn-lambda).

## Prerequisites

- AWS CLI
- jq
- Docker

## Instructions

1. Create a separate directory structure for each main layer you wish to create.
1. Within this directory include a requirements.txt file that includes the production pip dependencies to install
1. From the project root run the `build_layer.sh` script
1. The resulting `layers.csv` file gives the results and ARN for the layer.

## Licence

MIT Licence. Use completely at your own risk. No liability assumed.
