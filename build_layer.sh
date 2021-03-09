#!/bin/bash
#
# This script builds AWS lambda layers that contain the packages in the 
# requirements.txt file.
#
# The dependency size is optimized by removing some unnecessary files from 
# site-packages (__pycache__, *.pyc, tests...).
#
# Prerequisities: Install the AWS cli, jq, and Docker
#
# Usage:
#   ./build_layer.sh
#
# Inspired by model-zoo scripts - https://github.com/model-zoo/scikit-learn-lambda

set -e
set -o pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

echo
read -p "Which directory should I build? " DIRECTORY_NAME

cd $DIRECTORY_NAME
cp ../install-pip-packages.sh .

BUILD_CACHE_DIR="${SCRIPT_DIR}/${DIRECTORY_NAME}/build"
OUTPUT_CSV="layers.csv"

REQUIREMENTS=$(tr '\n' ' ' < requirements.txt)

echo "Will install requirements: ${REQUIREMENTS}"

echo
read -p "Input layer name : " LAYER_NAME

echo "Will use layer name: ${LAYER_NAME}"

# Clean out the build cache.
rm -rf ${BUILD_CACHE_DIR}/*

for arg in "$@"
do
    case $arg in
        --python=*) declare -a PYTHON_VERSIONS=("${arg#*=}") shift;;
        --region=*) declare -a REGIONS=("${arg#*=}") shift;;
        --output-csv=*) declare OUTPUT_CSV="${arg#*=}" shift;;
        --public) declare PUBLIC=true shift;;
        *) echo "ERROR: Invalid argument ${arg}" && exit 1;;
    esac
done

if [ -f ${OUTPUT_CSV} ]; then
    echo
    echo "Warning: output CSV file ${OUTPUT_CSV} will be overwritten!"
    read -p "Are you sure (y/n)? " choice
    case "$choice" in
      y|Y ) echo "yes";;
      n|N ) exit 1;;
      * ) exit 1;;
    esac
fi
OUTPUT_CSV=$(realpath ${OUTPUT_CSV})

echo
if [ -z "$PYTHON_VERSIONS" ]
then
    declare -a PYTHON_VERSIONS=("3.8")
fi
echo "Using Python version(s) $PYTHON_VERSIONS"

if [ -z "$REGIONS" ]
then
    declare -a REGIONS=("eu-west-2")
fi
echo "Publishing to region(s) $REGIONS"

read -p "Are you sure (y/n)? " choice
case "$choice" in
    y|Y ) echo "yes";;
    n|N ) exit 1;;
    * ) exit 1;;
esac

mkdir -p ${BUILD_CACHE_DIR}
rm -rf ${BUILD_CACHE_DIR}/*
echo "Python version,region,arn" > "${OUTPUT_CSV}"

for p in "${PYTHON_VERSIONS[@]}"
do
    echo "Building layer for python $p ..."
    docker run \
        -v ${SCRIPT_DIR}/${DIRECTORY_NAME}:/var/task \
        --user $(id -u):$(id -g) \
        "lambci/lambda:build-python$p" \
        /var/task/install-pip-packages.sh "${REQUIREMENTS}" /var/task/build/python/lib/python${p}/site-packages

    layer_name=$(echo "python-${p}-${LAYER_NAME}" | tr '.' '-')
    echo "Layer name to publish - ${layer_name}"

    zip_name="${layer_name}.zip"
    echo "Zip filename - ${zip_name}"

    cd ${BUILD_CACHE_DIR} 

    zip -r9 ${zip_name} python
    cd ..

    for r in "${REGIONS[@]}";
    do
        echo
        echo "Publishing layer to ${r} ..."
        layer_version_info=$(aws lambda publish-layer-version \
            --region "${r}" \
            --layer-name "${layer_name}" \
            --zip-file "fileb://${BUILD_CACHE_DIR}/${zip_name}" \
            --compatible-runtimes "python${p}" \
            --license-info MIT)
        layer_arn=$(echo ${layer_version_info} | jq -r ".LayerArn")

        echo "Created layer: ${layer_version_info}"
        if [ "${PUBLIC}" = true ]; then
            layer_version_number=$(echo ${layer_version_info} | jq -r ".Version")
            layer_version_policy=$(aws lambda add-layer-version-permission \
                --region "${r}" \
                --layer-name ${layer_name} \
                --statement-id public-statement \
                --action lambda:GetLayerVersion \
                --principal "*" \
                --version-number "${layer_version_number}" | jq)
            echo "Added layer version policy: ${layer_version_policy}"
        fi

        echo "${p},${r},${layer_arn}:${layer_version_number}" >> "${OUTPUT_CSV}"
    done

    echo
    echo "Library size ..."
    du -sh ${BUILD_CACHE_DIR}

    # Clean out cache for the next layer.
    rm -rf ${BUILD_CACHE_DIR}/*

done

rm -rf ${BUILD_CACHE_DIR}