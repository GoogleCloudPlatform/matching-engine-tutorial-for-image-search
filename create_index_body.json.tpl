{
  "displayName": "Search index for flower images",
  "metadata": {
    "contentsDeltaUri": "gs://${PROJECT_ID}-flowers/embeddings/flowers",
    "config": {
      "dimensions": 1280,
      "approximateNeighborsCount": 100,
      "algorithmConfig": { "treeAhConfig": {} }
    }
  },
  "indexUpdateMethod": "STREAM_UPDATE"
}