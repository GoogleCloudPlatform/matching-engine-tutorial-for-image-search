# Vertex AI Matching Engine Tutorial on Cloud Shell

In this tutorial, you will build an application for similar image search using [Vertex AI Matching Engine](https://cloud.google.com/vertex-ai/docs/matching-engine/overview), which provides high-scale, low-latency Approximate Nearest Neighbor search.

## Choose a project

First, select the Google Cloud project that you want to use for this tutorial and click **Start**.

<walkthrough-project-setup />

## Configure the project

Configure your Google Cloud project with `gcloud`.

```bash
gcloud config set project "<walkthrough-project-id />"
```

If your Cloud Shell is disconnected, reconnect Cloud Shell and run this command again.

## Tutorial Overview

1. Apply Terraform
   * Create resources required for this tutorial by Terraform
2. Build embeddings
   * Generate embedding vectors of sample image data set, format them for Vertex AI Matching Engine index, and upload them to Cloud Storage
   * Use [Cloud Run jobs](https://cloud.google.com/run/docs/create-jobs) for this process
3. Create and deploy a Matching Engine index
   * Create a Matching Engine index and deploy it to an index endpoint
4. Run search queries
   * Search similar images querying the deployed index
5. Update the index
   * Add new image embeddings to the index and run query again

## Download and check sample images

<walkthrough-tutorial-duration duration="3"></walkthrough-tutorial-duration>

Let's download and display sample images that you will use in this tutorial. Sample images are 5 kinds of flowers: daisy, dandelion, roses, sunflowers and tulips.

First, create a directory for images.

```bash
mkdir -p ~/data/flowers/{daisy,dandelion,roses,sunflowers,tulips}
```

Download images from public Cloud Storage.

```bash
gsutil -m cp "gs://cloud-samples-data/ai-platform/flowers/daisy/*.jpg" ~/data/flowers/daisy/
gsutil -m cp "gs://cloud-samples-data/ai-platform/flowers/dandelion/*.jpg" ~/data/flowers/dandelion/
gsutil -m cp "gs://cloud-samples-data/ai-platform/flowers/roses/*.jpg" ~/data/flowers/roses/
gsutil -m cp "gs://cloud-samples-data/ai-platform/flowers/sunflowers/*.jpg" ~/data/flowers/sunflowers/
gsutil -m cp "gs://cloud-samples-data/ai-platform/flowers/tulips/*.jpg" ~/data/flowers/tulips/
```

Display one of the images on Cloud Shell Editor.

```bash
cloudshell open ~/data/flowers/daisy/100080576_f52e8ee070_n.jpg
```

Cloud Shell Editor shows the image.

In this tutorial, you will search similar images using Matching Engine index built on vectors of these images.

## Apply Terraform

<walkthrough-tutorial-duration duration="5"></walkthrough-tutorial-duration>

Let's apply Terraform and create resources needed for this tutorial. The resources includes:

* Cloud Storage bucket for storing the embeddings
* VPC for deploying the Matching Engine index endpoint
* Compute engine instance for executing the search query

<walkthrough-editor-open-file filePath="./terraform/main.tf">See Terraform code</walkthrough-editor-open-file>

Move to `terraform` directory and initialize Terraform.

```bash
cd terraform
terraform init
```

Confirm the plan.

```bash
TF_VAR_project_id="<walkthrough-project-id />" terraform plan
```

Apply them.

```bash
TF_VAR_project_id="<walkthrough-project-id />" terraform apply -auto-approve
```

Return to the original directory.

```bash
cd ..
```

## Generate embeddings

<walkthrough-tutorial-duration duration="15"></walkthrough-tutorial-duration>

In this section, you will generate embeddings of sample images and upload them to Cloud Storage as the Matching Engine format. You will run Cloud Run jobs named Vectorizer for this process because it needs more computing resources than [Cloud Shell](https://cloud.google.com/shell/docs/how-cloud-shell-works).

<walkthrough-editor-open-file filePath="./vectorizer/main.py">See Vectorizer code</walkthrough-editor-open-file>

Build a Docker image for Vectorizer on [Cloud Build](https://cloud.google.com/build) and push it to [Artifact Registry](https://cloud.google.com/artifact-registry).

```bash
cd vectorizer
gcloud builds submit \
  --tag "us-central1-docker.pkg.dev/<walkthrough-project-id />/vectorizer/vectorizer:v1"
```

Create the Vectorizer job on Cloud Run and execute it.

```bash
gcloud beta run jobs create \
  vectorizer \
  --image "us-central1-docker.pkg.dev/<walkthrough-project-id />/vectorizer/vectorizer:v1"  \
  --cpu 4 \
  --memory 2Gi \
  --parallelism 2 \
  --region us-central1 \
  --service-account "vectorizer@<walkthrough-project-id />.iam.gserviceaccount.com" \
  --tasks 2 \
  --set-env-vars "DESTINATION_ROOT=gs://<walkthrough-project-id />-flowers/embeddings" \
  --set-env-vars "^@^FLOWERS=daisy,roses" \
  --execute-now
```

You can see the job status on [console](https://console.cloud.google.com/run/jobs?project={{project-id}}). When the job finishes, let's check the embeddings on Cloud Storage.

```bash
gsutil cat gs://<walkthrough-project-id />-flowers/embeddings/flowers/daisy.json | head -1
```

Each line includes an embeddings as a JSON like:

```json
{
  "id": "daisy/100080576_f52e8ee070_n.jpg",
  "embedding": [
    -0.07144428789615631,
    ...
  ]
}
```

Return to the original directory.

```bash
cd ..
```

## Create and deploy an index

<walkthrough-tutorial-duration duration="60"></walkthrough-tutorial-duration>

You will create a Matching Engine index and deploy it to an index endpoint in this section.

Matching Engine index is a vector database which has a data structure needed to provide high performance similarity-matching service. You can create an index with some [configuration of algorithm](https://cloud.google.com/vertex-ai/docs/matching-engine/create-manage-index#index-metadata-file) and [formatted initial dataset](https://cloud.google.com/vertex-ai/docs/matching-engine/match-eng-setup#input-data-format).

In this tutorial, you will create an index for streaming updates and update the index with streaming updates. At this time, though indexes for batch updates can be created by [gcloud](https://cloud.google.com/vertex-ai/docs/matching-engine/create-manage-index#create_index-gcloud), indexes for streaming updates cannot, so you have to [call Vertex AI API](https://cloud.google.com/vertex-ai/docs/matching-engine/create-manage-index#create-stream).

Create an index using curl command.

```bash
PROJECT_ID="<walkthrough-project-id />" \
  envsubst < create_index_body.json.tpl | \
  curl -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  "https://us-central1-aiplatform.googleapis.com/v1/projects/<walkthrough-project-id />/locations/us-central1/indexes" \
  -d @-
```

Creating this index typically takes about 1 hour. You can see the job status on [Console](https://console.cloud.google.com/vertex-ai/matching-engine/indexes?project={{project-id}}).

Next, create an index endpoint. Index endpoint is a resource which serves API to run ANN query. Index endpoints can be accessed from deployed VPC.

```bash
project_number=$(gcloud projects describe "<walkthrough-project-id />" --format "value(projectNumber)")
gcloud ai index-endpoints create \
  --display-name "Endpoint for flower search" \
  --network "projects/${project_number}/global/networks/flowers-search" \
  --region us-central1
```

Deploy the built index to the index endpoint.

```bash
index_endpoint_id="$(gcloud ai index-endpoints list --region us-central1 --format  "value(name)" | cut -d/ -f6)"
INDEX_ID="$(gcloud ai indexes list --region us-central1 --format "value(name)")" \
  envsubst < deploy_index_body.json.tpl | \
  curl -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  "https://us-central1-aiplatform.googleapis.com/v1/projects/<walkthrough-project-id />/locations/us-central1/indexEndpoints/$index_endpoint_id:deployIndex" \
  -d @-
```

Deploying this index typically takes 30 or 40 minutes. You can see the job status on Console.

## Run search queries

<walkthrough-tutorial-duration duration="5"></walkthrough-tutorial-duration>

In this section, you'll find similar images by querying the index through a Compute Engine instance, which has been created by Terraform, to access the index endpoint from the deployed VPC.

Choose an image to search for its similar images.

```bash
image_path="daisy/100080576_f52e8ee070_n.jpg"
```

Check the image on Cloud Shell Editor.

```bash
cloudshell open ~/data/flowers/$image_path
```

Search for similar images running Python code on a Compute Engine instance by `gcloud compute ssh` command. This Python code builds embedding in the same way as Vectorizer, and calls search query API on the specified index endpoint. If you see a prompt like `Enter passphrase for key`, enter your SSH passphrase.

<walkthrough-editor-open-file filePath="./searcher/main.py">Se Searcher code</walkthrough-editor-open-file>

```bash
gcloud compute ssh query-runner \
  --zone us-central1-b \
  -- \
  python3 /opt/code/searcher/main.py \
  --index_endpoint_name="$(gcloud ai index-endpoints list --region us-central1 --format "value(name)")" \
  --deployed_index_id=flowers_search_index \
  --image_path="/opt/flowers/$image_path"
```

You should see an output like this.

```
daisy/100080576_f52e8ee070_n.jpg: distance=77.32962799072266
daisy/3275951182_d27921af97_n.jpg: distance=66.36679077148438
daisy/15207766_fc2f1d692c_n.jpg: distance=65.5926742553711
daisy/437859108_173fb33c98.jpg: distance=64.13462829589844
daisy/2509545845_99e79cb8a2_n.jpg: distance=63.66404724121094
```

Each line gives a similar image. `distance` is the similarity.

Check the results.

```bash
cloudshell open ~/data/flowers/daisy/3275951182_d27921af97_n.jpg
```

As the index contains the queried image, the result includes the same image.

## Search for tulips

<walkthrough-tutorial-duration duration="3"></walkthrough-tutorial-duration>

The index you created hasn't had tulip images yet. You'll see what happens in such a case.

Choose a tulip image.

```bash
image_path="tulips/100930342_92e8746431_n.jpg"
```

Check this tulip.

```bash
cloudshell open ~/data/flowers/$image_path
```

Search for similar images.

```bash
gcloud compute ssh query-runner \
  --zone us-central1-b \
  -- \
  python3 /opt/code/searcher/main.py \
  --index_endpoint_name="$(gcloud ai index-endpoints list --region us-central1 --format "value(name)")" \
  --deployed_index_id=flowers_search_index \
  --image_path="/opt/flowers/$image_path"
```

You should see an output like this.

```
roses/12338444334_72fcc2fc58_m.jpg: distance=95.5372085571289
roses/6363951285_a802238d4e.jpg: distance=91.57391357421875
roses/5863698305_04a4277401_n.jpg: distance=91.4017562866211
roses/9216324117_5fa1e2bc25_n.jpg: distance=91.11756896972656
roses/4558025386_2c47314528.jpg: distance=90.17410278320312
```

These images are the similar images of the tulip. Check the results.

```bash
cloudshell open ~/data/flowers/roses/12338444334_72fcc2fc58_m.jpg
```

## Deploy Updater

<walkthrough-tutorial-duration duration="12"></walkthrough-tutorial-duration>

You created an index for streaming updates earlier. If you update your index through [streaming updates](https://cloud.google.com/vertex-ai/docs/matching-engine/update-rebuild-index#update_an_index_using_streaming_updates), you'll be able to get new images as search results in a few seconds.

You'll update your index through streaming updates in this section. Updater is a HTTP service to add a new image to an index through streaming updates. Receiving a path of the new flower image, Updater generates an embedding of the new image and add the image embedding to an index, calling [upsertDatapoints](https://cloud.google.com/vertex-ai/docs/reference/rest/v1/projects.locations.indexes/upsertDatapoints) API.

<walkthrough-editor-open-file filePath="./updater/main.py">See Updater code</walkthrough-editor-open-file>

Build and push a Docker image for Updater.

```bash
cd updater
gcloud builds submit \
  --tag "us-central1-docker.pkg.dev/<walkthrough-project-id />/updater/updater:v1"
```

Create updater service on Cloud Run.

```bash
gcloud run deploy \
  updater \
  --image "us-central1-docker.pkg.dev/<walkthrough-project-id />/updater/updater:v1"  \
  --cpu 4 \
  --memory 2Gi \
  --region us-central1 \
  --service-account "updater@<walkthrough-project-id />.iam.gserviceaccount.com" \
  --set-env-vars="INDEX_NAME=$(gcloud ai indexes list --region us-central1 --format 'value(name)')"
```

Return to the original directory.

```bash
cd ..
```

## Streaming updates

<walkthrough-tutorial-duration duration="5"></walkthrough-tutorial-duration>

This is the last section. You'll send an update request to Updater and see what happens to search results after streaming updates.

Choose another tulip image.

```bash
image_path="tulips/8908097235_c3e746d36e_n.jpg"
```

Add this image to the index through Updater.

```bash
url="$(gcloud run services describe updater --region us-central1 --format 'value(status.url)')"
body="{\"name\":\"$image_path\"}"
curl -X POST \
  -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  -H "Content-Type: application/json" \
  "$url/embeddings" \
  -d "$body"
```

Search for similar images with the tulip image.

```bash
image_path="tulips/100930342_92e8746431_n.jpg"
gcloud compute ssh query-runner \
  --zone us-central1-b \
  -- \
  python3 /opt/code/searcher/main.py \
  --index_endpoint_name="$(gcloud ai index-endpoints list --region us-central1 --format "value(name)")" \
  --deployed_index_id=flowers_search_index \
  --image_path="/opt/flowers/$image_path"
```

As the index has updated, you can see the new results like this.

```
tulips/8908097235_c3e746d36e_n.jpg: distance=110.92547607421875
roses/12338444334_72fcc2fc58_m.jpg: distance=95.5372085571289
roses/6363951285_a802238d4e.jpg: distance=91.57391357421875
roses/5863698305_04a4277401_n.jpg: distance=91.4017562866211
roses/9216324117_5fa1e2bc25_n.jpg: distance=91.11756896972656
```

Let's check the results in Cloud Shell Editor.

```bash
cloudshell open ~/data/flowers/tulips/8908097235_c3e746d36e_n.jpg
```

## Congratulations

Well done!

<walkthrough-conclusion-trophy />

Don't forget to delete the resources for the tutorial or your tutorial project.
