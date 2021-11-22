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
"""
eval.
"""
import time
import os
from mindspore import nn
from mindspore.train.model import Model
from src.dataset import create_dataset
from src.models import define_net, load_ckpt
from src.utils import context_device_init
from src.model_utils.config import config
from src.model_utils.moxing_adapter import moxing_wrapper
from src.model_utils.device_adapter import get_device_id, get_device_num

config.is_training = config.is_training_eval

# def modelarts_process():
#     """ modelarts process """
#     def unzip(zip_file, save_dir):
#         import zipfile
#         s_time = time.time()
#         if not os.path.exists(os.path.join(save_dir, config.modelarts_dataset_unzip_name)):
#             zip_isexist = zipfile.is_zipfile(zip_file)
#             if zip_isexist:
#                 fz = zipfile.ZipFile(zip_file, 'r')
#                 data_num = len(fz.namelist())
#                 print("Extract Start...")
#                 print("unzip file num: {}".format(data_num))
#                 data_print = int(data_num / 100) if data_num > 100 else 1
#                 i = 0
#                 for file in fz.namelist():
#                     if i % data_print == 0:
#                         print("unzip percent: {}%".format(int(i * 100 / data_num)), flush=True)
#                     i += 1
#                     fz.extract(file, save_dir)
#                 print("cost time: {}min:{}s.".format(int((time.time() - s_time) / 60),\
#                     int(int(time.time() - s_time) % 60)))
#                 print("Extract Done")
#             else:
#                 print("This is not zip.")
#         else:
#             print("Zip has been extracted.")
#
#     if config.need_modelarts_dataset_unzip:
#         zip_file_1 = os.path.join(config.data_path, config.modelarts_dataset_unzip_name + ".zip")
#         save_dir_1 = os.path.join(config.data_path)
#
#         sync_lock = "/tmp/unzip_sync.lock"
#
#         # Each server contains 8 devices as most
#         if get_device_id() % min(get_device_num(), 8) == 0 and not os.path.exists(sync_lock):
#             print("Zip file path: ", zip_file_1)
#             print("Unzip file save dir: ", save_dir_1)
#             unzip(zip_file_1, save_dir_1)
#             print("===Finish extract data synchronization===")
#             try:
#                 os.mknod(sync_lock)
#             except IOError:
#                 pass
#
#         while True:
#             if os.path.exists(sync_lock):
#                 break
#             time.sleep(1)
#
#         print("Device: {}, Finish sync unzip data from {} to {}.".format(get_device_id(), zip_file_1, save_dir_1))
#         print("#" * 200, os.listdir(save_dir_1))
#         print("#" * 200, os.listdir(os.path.join(config.data_path, config.modelarts_dataset_unzip_name)))
#
#         config.dataset_path = os.path.join(config.data_path, config.modelarts_dataset_unzip_name)
#     config.pretrain_ckpt = os.path.join(config.output_path, config.pretrain_ckpt)


# @moxing_wrapper(pre_process=modelarts_process)
def eval_mobilenetv2():
    config.dataset_path = os.path.join(config.dataset_path, 'val')
    print('\nconfig: \n', config)
    if not config.device_id:
        config.device_id = get_device_id()
    context_device_init(config)
    _, _, net = define_net(config, config.is_training)

    load_ckpt(net, config.pretrain_ckpt)

    dataset = create_dataset(dataset_path=config.dataset_path, do_train=False, config=config)
    step_size = dataset.get_dataset_size()
    if step_size == 0:
        raise ValueError("The step_size of dataset is zero. Check if the images count of eval dataset is more \
            than batch_size in config.py")

    net.set_train(False)

    loss = nn.SoftmaxCrossEntropyWithLogits(sparse=True, reduction='mean')
    model = Model(net, loss_fn=loss, metrics={'acc'})

    res = model.eval(dataset)
    print(f"result:{res}\npretrain_ckpt={config.pretrain_ckpt}")

if __name__ == '__main__':
    eval_mobilenetv2()
