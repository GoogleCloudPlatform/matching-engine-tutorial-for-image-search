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

import numpy as np
import tensorflow as tf
from google.cloud.aiplatform.matching_engine import MatchingEngineIndexEndpoint


def main(index_endpoint_name: str, deployed_index_id: str, image_path: str) -> None:
    print("===== Started making vector =====")

    model = tf.keras.applications.EfficientNetB0(include_top=False, pooling="avg")

    raw = tf.io.read_file(image_path)
    image = tf.image.decode_jpeg(raw, channels=3)
    image = tf.image.resize(image, [224, 224])

    vector = model.predict(np.array([image.numpy()]))[0].tolist()

    # https://github.com/googleapis/python-aiplatform/blob/v1.22.0/google/cloud/aiplatform/matching_engine/matching_engine_index_endpoint.py#L85
    endpoint = MatchingEngineIndexEndpoint(index_endpoint_name=index_endpoint_name)

    print("===== Started query =====")
    # https://github.com/googleapis/python-aiplatform/blob/v1.22.0/google/cloud/aiplatform/matching_engine/matching_engine_index_endpoint.py#L902
    res = endpoint.match(
        deployed_index_id=deployed_index_id, queries=[vector], num_neighbors=5
    )
    print("===== Finished query =====")

    for neighbor in res[0]:
        print(f"{neighbor.id}: distance={neighbor.distance}")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--index_endpoint_name", type=str, required=True)
    parser.add_argument("--deployed_index_id", type=str, required=True)
    parser.add_argument("--image_path", type=str, required=True)
    args = parser.parse_args()

    main(
        index_endpoint_name=args.index_endpoint_name,
        deployed_index_id=args.deployed_index_id,
        image_path=args.image_path,
    )
