# Cloud Shell で試す Vertex AI Matching Engine

このチュートリアルでは [Vertex AI Matching Engine](https://cloud.google.com/vertex-ai/docs/matching-engine/overview?hl=ja) の近似再近傍探索を利用して類似画像検索を体験します。

## プロジェクトの選択

ハンズオンを行う Google Cloud プロジェクトを選択して **Start** をクリックしてください。

<walkthrough-project-setup />

## プロジェクトの設定

gcloud でプロジェクトを設定してください。

```bash
gcloud config set project "<walkthrough-project-id />"
```

## チュートリアルの流れ

1. Terraform の実行
   * Terraform を実行してチュートリアルに必要な各リソースを作成します
2. エンベディングの作成
   * サンプルの画像データのベクトル表現 (エンベディング) を生成し、インデックス作成に必要なフォーマットで Cloud Storage にアップロードします
   * これらの処理には [Cloud Run jobs](https://cloud.google.com/run/docs/create-jobs?hl=ja) を使います
3. Matching Engine インデックスの作成とデプロイ
   * Matching Engine のインデックスを作成して、それをインデックス エンドポイントにデプロイします
4. 検索クエリの実行と確認
   * 作成したインデックスを利用して、類似画像の検索クエリを実行します
5. インデックスの更新と確認
   * インデックスに新しい画像ベクトルを追加して検索クエリを実行します

## サンプル画像データのダウンロードと確認

<walkthrough-tutorial-duration duration="3"></walkthrough-tutorial-duration>

このチュートリアルで使うサンプル画像データを Cloud Shell にダウンロードして確認します。サンプルデータは花の画像で、daisy, dandelion, roses, sunflowers, tulips の 5 つの種類の花の画像が含まれています。

画像用のディレクトリを作成します。

```bash
mkdir -p ~/data/flowers/{daisy,dandelion,roses,sunflowers,tulips}
```

Cloud Storage からダウンロードします。

```bash
gsutil -m cp "gs://cloud-samples-data/ai-platform/flowers/daisy/*.jpg" ~/data/flowers/daisy/
gsutil -m cp "gs://cloud-samples-data/ai-platform/flowers/dandelion/*.jpg" ~/data/flowers/dandelion/
gsutil -m cp "gs://cloud-samples-data/ai-platform/flowers/roses/*.jpg" ~/data/flowers/roses/
gsutil -m cp "gs://cloud-samples-data/ai-platform/flowers/sunflowers/*.jpg" ~/data/flowers/sunflowers/
gsutil -m cp "gs://cloud-samples-data/ai-platform/flowers/tulips/*.jpg" ~/data/flowers/tulips/
```

画像を 1 枚確認します。

```bash
cloudshell open ~/data/flowers/daisy/100080576_f52e8ee070_n.jpg
```

Cloud Shell Editor で画像が表示されます。

このチュートリアルではこれらの画像をベクトルとして表現して Matching Engine での類似画像検索を行います。

## Terraform の実行

<walkthrough-tutorial-duration duration="5"></walkthrough-tutorial-duration>

Terraform を実行してチュートリアルに必要なリソースを作成します。次のようなリソースが作成されます。

* エンベディング保存用の Cloud Storage バケット
* Matching Engine のインデックス エンドポイントを配置する VPC
* クエリ実行用の Compute Engine インスタンス

<walkthrough-editor-open-file filePath="./terraform/main.tf">Terraform のソースコードを確認する</walkthrough-editor-open-file>

`terraform` ディレクトリに移動して Terraform を初期化します。

```bash
cd terraform
terraform init
```

Plan を確認します。

```bash
TF_VAR_project_id="<walkthrough-project-id />" terraform plan
```

実行します。

```bash
TF_VAR_project_id="<walkthrough-project-id />" terraform apply -auto-approve
```

元のディレクトリに移動します。

```bash
cd ..
```

## エンベディングの作成

<walkthrough-tutorial-duration duration="15"></walkthrough-tutorial-duration>

サンプル画像のエンベディングを作成して、Matching Engine のインデックス作成に必要なフォーマットで Cloud Storage にアップロードします。[Cloud Shell のリソース](https://cloud.google.com/shell/docs/how-cloud-shell-works?hl=ja)では処理が難しいため、Cloud Run jobs でエンベディング作成ジョブ (Vectorizer) を実行します。

<walkthrough-editor-open-file filePath="./vectorizer/main.py">Vectorizer のソースコードを確認する</walkthrough-editor-open-file>

Vectorizer の Docker イメージを [Cloud Build](https://cloud.google.com/build?hl=ja) を使ってビルドして [Artifact Registry](https://cloud.google.com/artifact-registry?hl=ja) にプッシュします。

```bash
cd vectorizer
gcloud builds submit \
  --tag "us-central1-docker.pkg.dev/<walkthrough-project-id />/vectorizer/vectorizer:v1"
```

Vectorizer の Cloud Run job を作成して実行します。

```bash
gcloud beta run jobs create \
  vectorizer \
  --image "us-central1-docker.pkg.dev/<walkthrough-project-id />/vectorizer/vectorizer:v1"  \
  --cpu 4 \
  --memory 2Gi \
  --parallelism 5 \
  --region us-central1 \
  --service-account "vectorizer@<walkthrough-project-id />.iam.gserviceaccount.com" \
  --tasks 5 \
  --set-env-vars="DESTINATION_ROOT=gs://<walkthrough-project-id />-flowers/embeddings" \
  --execute-now
```

[コンソール](https://console.cloud.google.com/run/jobs?project={{project-id}})で実行状況が確認できます。ジョブが終了したら作成されたファイルを確認します。

```bash
gsutil cat gs://<walkthrough-project-id />-flowers/embeddings/flowers/daisy.json | head -1
```

1 行に 1 つの画像ベクトルが次のような JSON で表現されています。

```json
{
  "id": "daisy/100080576_f52e8ee070_n.jpg",
  "embedding": [
    -0.07144428789615631,
    ...
  ]
}
```

元のディレクトリに戻ります。

```bash
cd ..
```

## インデックスの作成とデプロイ

<walkthrough-tutorial-duration duration="60"></walkthrough-tutorial-duration>

Matching Engine のインデックスを作成して、それをインデックス エンドポイントにデプロイします。

インデックスは高速な近似再近傍探索のために必要なデータ構造を持ったデータベースです。[アルゴリズムに関する設定](https://cloud.google.com/vertex-ai/docs/matching-engine/create-manage-index#index-metadata-file)や、探索対象となる[データ (ID とエンベディングのセット)](https://cloud.google.com/vertex-ai/docs/matching-engine/match-eng-setup#input-data-format)で構成されます。

現在、バッチ更新のインデックスは [gcloud コマンドで作成](https://cloud.google.com/vertex-ai/docs/matching-engine/create-manage-index#create_index-gcloud)できますが、ストリーミング更新のインデックスの作成には API ライブラリや curl で [API を実行](https://cloud.google.com/vertex-ai/docs/matching-engine/create-manage-index#create-stream)する必要があります。このチュートリアルではストリーミング更新のインデックスを使うため curl を使って API を実行してインデックスを作成します。

curl コマンドでインデックス作成の API を実行します。

```bash
PROJECT_ID="<walkthrough-project-id />" \
  envsubst < create_index_body.json.tpl | \
  curl -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  "https://us-central1-aiplatform.googleapis.com/v1/projects/<walkthrough-project-id />/locations/us-central1/indexes" \
  -d @-
```

インデックスの作成には数十分から1時間ほどかかります。[コンソール](https://console.cloud.google.com/vertex-ai/matching-engine/indexes?project={{project-id}})でステータスが確認できます。

インデックス エンドポイントを作成します。インデックス エンドポイントはインデックスによる近似再近傍探索を実行するための API を提供するためのリソースです。インデックス エンドポイントには設定した VPC 内からのみアクセスできます。また、負荷によって自動でスケールします。

```bash
project_number=$(gcloud projects describe "<walkthrough-project-id />" --format "value(projectNumber)")
gcloud ai index-endpoints create \
  --display-name "Endpoint for flower search" \
  --network "projects/${project_number}/global/networks/flowers-search" \
  --region us-central1
```

作成したインデックスをインデックス エンドポイントにデプロイします。

```bash
index_id="$(gcloud ai indexes list --region us-central1 --format "value(name)" | cut -d/ -f6)"
index_endpoint_id="$(gcloud ai index-endpoints list --region us-central1 --format "value(name)" | cut -d/ -f6)"
gcloud ai index-endpoints deploy-index \
  "$index_endpoint_id" \
  --region us-central1 \
  --deployed-index-id flowers_search_index \
  --display-name "Deployed flower search index" \
  --index "$index_id"
```

デプロイには数分から数十分かかります。表示されたコマンドを実行するか、コンソールからステータスが確認できます。

## クエリの実行と確認

<walkthrough-tutorial-duration duration="5"></walkthrough-tutorial-duration>

インデックス エンドポイントに対して探索クエリを実行してサンプル画像の類似画像検索を行います。インデックス エンドポイントへのクエリは VPC 内からアクセスする必要があるため、 VPC 内に作成した Compute Engine インスタンスからクエリを実行します。インスタンスは既に Terraform で作成されています。

検索クエリとなる画像を選択します。ここでは daisy の画像を使います。

```bash
image_path="daisy/100080576_f52e8ee070_n.jpg"
```

検索クエリとなる画像を確認します。

```bash
cloudshell open ~/data/flowers/$image_path
```

`gcloud compute ssh` コマンドを使って、Compute Engine インスタンス上の Python プログラムを実行して類似画像を検索します。このプログラムでは、Vectorizer と同じ方法で画像のエンベディングを作成して指定されたインデックス エンドポイントへのクエリを実行します。`Enter passphrase for key` のようなプロンプトが出た場合は SSH 鍵のパスフレーズを入力してください。

<walkthrough-editor-open-file filePath="./searcher/main.py">Searcher のソースコードを確認する</walkthrough-editor-open-file>

```bash
gcloud compute ssh query-runner \
  --zone us-central1-b \
  -- \
  python3 /opt/google-cloud-examples/python/vertexai-matching-engine/searcher/main.py \
  --index_endpoint_name="$(gcloud ai index-endpoints list --region us-central1 --format "value(name)")" \
  --deployed_index_id=flowers_search_index \
  --image_path="/opt/flowers/$image_path"
```

成功すれば次のような出力が得られます。

```
daisy/100080576_f52e8ee070_n.jpg: distance=77.32962799072266
daisy/3275951182_d27921af97_n.jpg: distance=66.36679077148438
daisy/15207766_fc2f1d692c_n.jpg: distance=65.5926742553711
daisy/437859108_173fb33c98.jpg: distance=64.13462829589844
daisy/2509545845_99e79cb8a2_n.jpg: distance=63.66404724121094
```

これらが、クエリした画像の類似画像となります。`distance` はインデックスで設定した類似度です。

Cloud Shell Editor で検索結果の各類似画像を確認します。

```bash
cloudshell open ~/data/flowers/daisy/3275951182_d27921af97_n.jpg
```

今回はインデックスに含まれる画像を使って検索しているため、検索結果に同じ画像も含まれます。

## インデックスに含まれない画像でのクエリ

<walkthrough-tutorial-duration duration="3"></walkthrough-tutorial-duration>

サンプル画像のうち、tulips の画像はまだインデックスに含まれていません。tulips の画像で検索するとどうなるかを確認します。

tulips の画像を 1 つ選択します。

```bash
image_path="tulips/100930342_92e8746431_n.jpg"
```

検索クエリとなる画像を確認します。

```bash
cloudshell open ~/data/flowers/$image_path
```

Compute Engine インスタンス上の Python プログラムを実行して類似画像を検索します。

```bash
gcloud compute ssh query-runner \
  --zone us-central1-b \
  -- \
  python3 /opt/google-cloud-examples/python/vertexai-matching-engine/searcher/main.py \
  --index_endpoint_name="$(gcloud ai index-endpoints list --region us-central1 --format "value(name)")" \
  --deployed_index_id=flowers_search_index \
  --image_path="/opt/flowers/$image_path"
```

成功すれば、次のような出力が得られます。

```
roses/12338444334_72fcc2fc58_m.jpg: distance=95.5372085571289
roses/6363951285_a802238d4e.jpg: distance=91.57391357421875
roses/5863698305_04a4277401_n.jpg: distance=91.4017562866211
roses/9216324117_5fa1e2bc25_n.jpg: distance=91.11756896972656
roses/4558025386_2c47314528.jpg: distance=90.17410278320312
```

これらが、クエリした画像の類似画像となります。次のようにして各類似画像を確認してください。

```bash
cloudshell open ~/data/flowers/roses/12338444334_72fcc2fc58_m.jpg
```

## Updater のデプロイ

<walkthrough-tutorial-duration duration="12"></walkthrough-tutorial-duration>

このチュートリアルではストリーミング アップデート用のインデックスを作成しました。[ストリーミング アップデート](https://cloud.google.com/vertex-ai/docs/matching-engine/update-rebuild-index#update_an_index_using_streaming_updates) でインデックスを更新すると、変更が数秒以内に反映されます。

このチュートリアルでは Updater を使ってインデックスをストリーミング アップデートします。Updater は新しい画像をインデックスに追加するためのサービスです。Updater はリクエストとして受け取ったパスの画像のエンベディングを作成して、インデックスに対して[upsert](https://cloud.google.com/vertex-ai/docs/reference/rest/v1/projects.locations.indexes/upsertDatapoints)を実行します。

<walkthrough-editor-open-file filePath="./updater/main.py">Updater のソースコードを確認する</walkthrough-editor-open-file>

Updater の Docker イメージを Cloud Build を使ってビルド・プッシュします。

```bash
cd updater
gcloud builds submit \
  --tag "us-central1-docker.pkg.dev/<walkthrough-project-id />/updater/updater:v1"
```

Updater を Cloud Run にデプロイします。

```bash
gcloud run deploy \
  updater \
  --image "us-central1-docker.pkg.dev/<walkthrough-project-id />/updater/updater:v1"  \
  --allow-unauthenticated \
  --cpu 4 \
  --memory 2Gi \
  --region us-central1 \
  --service-account "updater@<walkthrough-project-id />.iam.gserviceaccount.com" \
  --set-env-vars="INDEX_NAME=$(gcloud ai indexes list --region us-central1 --format 'value(name)')"
```

元のディレクトリに戻ります。

```bash
cd ..
```

## ストリーミング アップデート

<walkthrough-tutorial-duration duration="5"></walkthrough-tutorial-duration>

Updater にリクエストを送り、ストリーミング アップデートでインデックスに tulips 画像のベクトルを追加して検索結果が変わるかどうかを確認します。

追加する tulips の画像を選択します。

```bash
image_path="tulips/100930342_92e8746431_n.jpg"
```

Updater にこの画像のベクトルをインデックスに追加するようにリクエストします。

```bash
url="$(gcloud run services describe updater --region us-central1 --format 'value(status.url)')"
body="{\"name\":\"$image_path\"}"
curl -X POST \
  -H "Content-Type: application/json" \
  "$url/embeddings" \
  -d "$body"
```

Compute Engine インスタンス上の Python プログラムを実行して類似画像を検索します。

```bash
gcloud compute ssh query-runner \
  --zone us-central1-b \
  -- \
  python3 /opt/google-cloud-examples/python/vertexai-matching-engine/searcher/main.py \
  --index_endpoint_name="$(gcloud ai index-endpoints list --region us-central1 --format "value(name)")" \
  --deployed_index_id=flowers_search_index \
  --image_path="/opt/flowers/$image_path"
```

インデックスが更新されて、次のような結果が得られます。

```
tulips/100930342_92e8746431_n.jpg: distance=140.16213989257812
roses/12338444334_72fcc2fc58_m.jpg: distance=95.5372085571289
roses/6363951285_a802238d4e.jpg: distance=91.57391357421875
roses/5863698305_04a4277401_n.jpg: distance=91.4017562866211
roses/9216324117_5fa1e2bc25_n.jpg: distance=91.11756896972656
```

このように、追加された tulips の画像が検索結果として得られるようになります。

## おつかれさまでした

以上でチュートリアルは終了です。

<walkthrough-conclusion-trophy />

不要になったリソースやプロジェクトは削除してください。
