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

import json
import logging
import os
from tempfile import NamedTemporaryFile

import numpy as np
import tensorflow as tf
from google.cloud import storage

logger = logging.getLogger("vectorizer")


class SampleDataVectorizer:
    BUCKET = "cloud-samples-data"
    PREFIX = "ai-platform/flowers/"

    FLOWERS = ["daisy", "dandelion", "roses", "sunflowers", "tulips"]

    def __init__(self, flower: str, destination: str):
        self._flower = flower
        self._client = storage.Client()

        self._blobs = self._client.list_blobs(
            self.BUCKET, prefix=f"{self.PREFIX}{flower}/"
        )

        dst_bucket_name, dst_base = destination[5:].split("/", maxsplit=1)
        self._dst_bucket = self._client.bucket(dst_bucket_name)
        self._dst_base = dst_base

        self._model = tf.keras.applications.EfficientNetB0(
            include_top=False, pooling="avg"
        )

    def vectorize_and_upload(self) -> None:
        data = []

        for blob in self._blobs:
            name = blob.name.split("/")[-1]

            logger.info("downloading %s", name)
            raw = self._download_as_tensor(blob)

            logger.info("vectorizing %s", name)
            embedding = self._vectorize(raw)

            data.append(
                {
                    "id": f"{self._flower}/{name}",
                    "embedding": embedding,
                }
            )

        blob = self._dst_bucket.blob(f"{self._dst_base}/{self._flower}.json")
        with blob.open(mode="w") as f:
            for datapoint in data:
                f.write(json.dumps(datapoint) + "\n")

    def _download_as_tensor(self, blob: storage.Blob) -> tf.Tensor:
        with NamedTemporaryFile(prefix="vectorizer") as temp:
            blob.download_to_filename(temp.name)
            return tf.io.read_file(temp.name)

    def _vectorize(self, raw: tf.Tensor) -> list[float]:
        image = tf.image.decode_jpeg(raw, channels=3)
        return self._model.predict(np.array([image.numpy()]))[0].tolist()


def main(destination_root: str, task_index: int) -> None:
    flower = SampleDataVectorizer.FLOWERS[task_index]

    dir = "flowers"

    if task_index == len(SampleDataVectorizer.FLOWERS) - 1:
        # For updating indices
        dir = flower

    destination = os.path.join(destination_root, dir)

    vectorizer = SampleDataVectorizer(flower, destination)
    vectorizer.vectorize_and_upload()

    logger.info("finished successfully 🤗")


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    # e.g. gs://my-bucket/index01/embeddings
    destination = os.environ["DESTINATION_ROOT"]
    task_index = int(os.environ.get("CLOUD_RUN_TASK_INDEX", "0"))
    main(destination, task_index)
