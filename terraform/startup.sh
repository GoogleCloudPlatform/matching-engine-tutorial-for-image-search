#!/usr/bin/env bash
# Copyright 2023 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


echo 'PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION="python"' >> /etc/environment

apt-get update
apt-get -y install python3-pip git
pip3 install tensorflow google-cloud-aiplatform

gsutil -m cp -r gs://cloud-samples-data/ai-platform/flowers /opt/

git clone https://github.com/GoogleCloudPlatform/matching-engine-tutorial-for-image-search /opt/code
