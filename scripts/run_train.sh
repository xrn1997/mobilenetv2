#!/usr/bin/env bash
# Copyright 2020 Huawei Technologies Co., Ltd
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ============================================================================

run_ascend()
{
    if [ $# = 6 ] ; then
        PRETRAINED_CKPT=""
        FREEZE_LAYER="none"
        FILTER_HEAD="False"
    elif [ $# = 8 ] ; then
        PRETRAINED_CKPT=$7
        FREEZE_LAYER=$8
        FILTER_HEAD="False"
    elif [ $# = 9 ] ; then
        PRETRAINED_CKPT=$7
        FREEZE_LAYER=$8
        FILTER_HEAD=$9
    else
        echo "Usage:
              Ascend: sh run_train.sh Ascend [CONFIG_FILE] [DEVICE_NUM] [VISIABLE_DEVICES(0,1,2,3,4,5,6,7)] [RANK_TABLE_FILE] [DATASET_PATH] [CKPT_PATH](optional) [FREEZE_LAYER](optional) [FILTER_HEAD](optional)
              Ascend: sh run_train.sh Ascend [CONFIG_FILE] [DEVICE_NUM] [VISIABLE_DEVICES(0,1,2,3,4,5,6,7)] [RANK_TABLE_FILE] [DATASET_PATH]"
        exit 1
    fi;

    if [ $3 -lt 1 ] || [ $3 -gt 8 ]
    then
        echo "error: DEVICE_NUM=$3 is not in (1-8)"
    exit 1
    fi

    if [ ! -d $6 ] && [ ! -f $6 ]
    then
        echo "error: DATASET_PATH=$6 is not a directory or file"
    exit 1
    fi
    BASEPATH=$(cd "`dirname $0`" || exit; pwd)
    CONFIG_FILE="${BASEPATH}/../$2"

    VISIABLE_DEVICES=$4
    IFS="," read -r -a CANDIDATE_DEVICE <<< "$VISIABLE_DEVICES"
    if [ ${#CANDIDATE_DEVICE[@]} -ne $3 ]
    then
        echo "error: DEVICE_NUM=$3 is not equal to the length of VISIABLE_DEVICES=$4"
    exit 1
    fi
    export PYTHONPATH=${BASEPATH}:$PYTHONPATH
    export RANK_TABLE_FILE=$5
    export RANK_SIZE=$3
    if [ -d "../train" ];
    then
        rm -rf ../train
    fi
    mkdir ../train
    cd ../train || exit
    RUN_DISTRIBUTE=True
    if [ $3 -eq 1 ] ; then
        RUN_DISTRIBUTE=False
        export DEVICE_ID=${CANDIDATE_DEVICE[0]}
        export RANK_ID=0
        nohup python ${BASEPATH}/../train.py \
            --run_distribute=$RUN_DISTRIBUTE \
            --config_path=$CONFIG_FILE \
            --platform=$1 \
            --dataset_path=$6 \
            --pretrain_ckpt=$PRETRAINED_CKPT \
            --freeze_layer=$FREEZE_LAYER \
            --filter_head=$FILTER_HEAD \
            &> ../train.log &
        exit 1
    fi
    cpus=`cat /proc/cpuinfo| grep "processor"| wc -l`
    avg=`expr $cpus \/ $RANK_SIZE`
    gap=`expr $avg \- 1`
    for((i=0; i<${RANK_SIZE}; i++))
    do
        start=`expr $i \* $avg`
        end=`expr $start \+ $gap`
        cmdopt=$start"-"$end
        export DEVICE_ID=${CANDIDATE_DEVICE[i]}
        export RANK_ID=$i
        rm -rf ./rank$i
        mkdir ./rank$i
        cp ../*.py ./rank$i
        cp ../*.yaml ./rank$i
        cp -r ../src ./rank$i
        cd ./rank$i || exit
        echo "start training for rank $RANK_ID, device $DEVICE_ID"
        env > env.log
        taskset -c $cmdopt python train.py \
            --run_distribute=$RUN_DISTRIBUTE \
            --config_path=$CONFIG_FILE \
            --platform=$1 \
            --dataset_path=$6 \
            --pretrain_ckpt=$PRETRAINED_CKPT \
            --freeze_layer=$FREEZE_LAYER \
            --filter_head=$FILTER_HEAD \
            &> log$i.log & 
        cd ..
    done
}

run_gpu()
{
    if [ $# = 4 ] ; then
        PRETRAINED_CKPT=""
        FREEZE_LAYER="none"
        FILTER_HEAD="False"
    elif [ $# = 6 ] ; then
        PRETRAINED_CKPT=$5
        FREEZE_LAYER=$6
        FILTER_HEAD="False"
    elif [ $# = 7 ] ; then
        PRETRAINED_CKPT=$5
        FREEZE_LAYER=$6
        FILTER_HEAD=$7
    else
        echo "Usage:
              GPU: sh run_train.sh GPU [DEVICE_NUM] [VISIABLE_DEVICES(0,1,2,3,4,5,6,7)] [DATASET_PATH] [CKPT_PATH](optional) [FREEZE_LAYER](optional) [FILTER_HEAD](optional)
              GPU: sh run_train.sh GPU [DEVICE_NUM] [VISIABLE_DEVICES(0,1,2,3,4,5,6,7)] [DATASET_PATH]"
        exit 1
    fi;

    if [ ! -d $4 ]
    then
        echo "error: DATASET_PATH=$4 is not a directory"
    exit 1
    fi

    BASEPATH=$(cd "`dirname $0`" || exit; pwd)
    CONFIG_FILE="${BASEPATH}/../default_config_gpu.yaml"

    export PYTHONPATH=${BASEPATH}:$PYTHONPATH
    if [ -d "../train" ];
    then
        rm -rf ../train
    fi
    mkdir ../train
    cd ../train || exit

    export CUDA_VISIBLE_DEVICES="$3"

    if [ $2 -eq 1 ] ; then
        RUN_DISTRIBUTE=False
        nohup python ${BASEPATH}/../train.py \
        --config_path=$CONFIG_FILE \
        --platform=$1 \
        --run_distribute=$RUN_DISTRIBUTE \
        --dataset_path=$4 \
        --pretrain_ckpt=$PRETRAINED_CKPT \
        --freeze_layer=$FREEZE_LAYER \
        --filter_head=$FILTER_HEAD \
        &> ../train.log &
        exit 1
    elif [ $2 -gt 1 ] && [ $2 -le 8 ] ; then
        RUN_DISTRIBUTE=True
    else
        echo "error: DEVICE_NUM=$2 is not in (1-8)"
        exit 1
    fi;

    mpirun -n $2 --allow-run-as-root --output-filename log_output --merge-stderr-to-stdout \
    python ${BASEPATH}/../train.py \
        --config_path=$CONFIG_FILE \
        --platform=$1 \
        --run_distribute=$RUN_DISTRIBUTE \
        --dataset_path=$4 \
        --pretrain_ckpt=$PRETRAINED_CKPT \
        --freeze_layer=$FREEZE_LAYER \
        --filter_head=$FILTER_HEAD \
        &> ../train.log &  # dataset train folder
}

run_cpu()
{
    if [ $# = 2 ] ; then
        PRETRAINED_CKPT=""
        FREEZE_LAYER="none"
        FILTER_HEAD="False"
    elif [ $# = 4 ] ; then
        PRETRAINED_CKPT=$3
        FREEZE_LAYER=$4
        FILTER_HEAD="False"
    elif [ $# = 5 ] ; then
        PRETRAINED_CKPT=$3
        FREEZE_LAYER=$4
        FILTER_HEAD=$5
    else
        echo "Usage:
              CPU: sh run_train.sh CPU [DATASET_PATH]
              CPU: sh run_train.sh CPU [DATASET_PATH] [CKPT_PATH](optional) [FREEZE_LAYER](optional) [FILTER_HEAD](optional)"
        exit 1
    fi;
    if [ ! -d $2 ]
    then
        echo "error: DATASET_PATH=$2 is not a directory"
    exit 1
    fi

    BASEPATH=$(cd "`dirname $0`" || exit; pwd)
    CONFIG_FILE="${BASEPATH}/../default_config_cpu.yaml"

    export PYTHONPATH=${BASEPATH}:$PYTHONPATH
    if [ -d "../train" ];
    then
        rm -rf ../train
    fi
    mkdir ../train
    cd ../train || exit

    python ${BASEPATH}/../train.py \
        --config_path=$CONFIG_FILE \
        --platform=$1 \
        --dataset_path=$2 \
        --pretrain_ckpt=$PRETRAINED_CKPT \
        --freeze_layer=$FREEZE_LAYER \
        --filter_head=$FILTER_HEAD \
        &> ../train.log &  # dataset train folder
}

if [ $1 = "Ascend" ] ; then
    run_ascend "$@"
elif [ $1 = "GPU" ] ; then
    run_gpu "$@"
elif [ $1 = "CPU" ] ; then
    run_cpu "$@"
else
    echo "Unsupported platform."
fi;
