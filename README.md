# bge-m3 embedding server (ACA)

Self-hosted `BAAI/bge-m3` on Azure Container Apps (CPU, scale to zero). It generates the
embeddings for the blog articles (KnowledgeBase chunks) and for the GitHub workflows that
index and test site texts, so no embedding quota is needed from a third party.

Same model as Cloudflare Workers AI `@cf/baai/bge-m3` and the local Ollama `bge-m3`:
measured cosine against Ollama is 0.99995+ on PT/EN sentences, so the vectors are
interchangeable with the ones already stored.

History: it was built as a fallback for the sites-template assistants when Workers AI ran
out of daily neurons (handoff `2026-10-12-bge-m3-aca-fallback.md`, sites-template issue #401).
The assistants no longer use it; only batch callers do.

## What it is

Not a .NET project: a Dockerfile around Hugging Face
[Text Embeddings Inference](https://github.com/huggingface/text-embeddings-inference)
(`cpu-1.9.4`) with the model baked in (converted to safetensors at build time).

- `POST /embed` `{"inputs": [...], "normalize": true}` -> array of 1024-float vectors
- up to 32 inputs per call (`--max-client-batch-size 32`)
- `GET /health` -> 200 once the model is loaded
- both need `Authorization: Bearer <API key>`
- `--max-batch-tokens 2048` (inputs longer than that are truncated); lowering it shortens the
  start-up warm-up but would truncate long article paragraphs, so keep it

## Behaviour

- Scale: min 0 / max 1, 2 vCPU / 4 GiB, cooldown 600 s. No traffic = no cost.
- Cold start from zero: about 35-90 s measured (about 3 s model load, about 27 s TEI
  warm-up, the rest image pull and scheduling). Callers must wait: send `GET /health` with a
  timeout of 150 s or more first, then embed. Warm latency is about 1 s per call.
- TEI prints its arguments, including the API key, in the console log at every start.
  Treat log access as key access and redact that line before sharing logs.

## Deploy

1. GitHub environment `dev`: the `DOCKERHUB_*`, `AZURE_*`, `AZURE_RESOURCE_GROUP` and
   `ACA_ENVIRONMENT_NAME` values, plus secret `EMBEDDING_API_KEY` (any long random string).
2. Run the **Build & deploy bge-m3 server** workflow. It prints the FQDN.
3. Check: `URL=https://<fqdn> KEY=... scripts/check.sh` (timings, batch of 32, 401s).
   For a real cold start, run it after the app has scaled to zero.

Callers read the URL and key from their own secrets (`EMBEDDING_FQDN`, `EMBEDDING_API_KEY`).
To rotate the key: change `EMBEDDING_API_KEY`, then re-run the deploy workflow.

## Possible later

- Leaner image (int8 ONNX, or the image in ACR in the same region) to cut cold start and
  cost further. Needs a build and a cosine re-check against fp32.
