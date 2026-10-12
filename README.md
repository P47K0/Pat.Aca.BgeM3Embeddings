# bge-m3 embedding server (ACA)

Self-hosted `BAAI/bge-m3` on Azure Container Apps (CPU, scale to zero), used as the
fallback for the sites-template AI assistants when Cloudflare Workers AI runs out of its
daily free neurons. Same model, so vectors match the ones stored in Vectorize.

Background and contract: `2026-10-12-bge-m3-aca-fallback.md` (handoff from the
sites-template session; sites-template issue #401).

## What it is

Not a .NET project: a Dockerfile around Hugging Face
[Text Embeddings Inference](https://github.com/huggingface/text-embeddings-inference)
(`cpu-1.9.4`) with the model baked in (converted to safetensors at build time).

- `POST /embed` `{"inputs": [...], "normalize": true}` -> array of 1024-float vectors
- `GET /health` -> 200 once the model is loaded
- up to 32 inputs per call (`--max-client-batch-size 32`, used by the sites-template index workflow)
- both need `Authorization: Bearer <API key>`

## Deploy

1. GitHub environment `dev`: reuse the `DOCKERHUB_*`, `AZURE_*`, `AZURE_RESOURCE_GROUP`,
   `ACA_ENVIRONMENT_NAME` values, and add secret `EMBEDDING_API_KEY` (long random string).
2. Run the **Build & deploy bge-m3 server** workflow. It prints the FQDN.
3. Scale to zero (wait 10+ min idle), then `URL=https://<fqdn> KEY=... scripts/check.sh`.

`EMBEDDING_FALLBACK_URL` and `EMBEDDING_FALLBACK_KEY` go on both Workers
(`daregiao-landing`, `project-sites-router`) and in the GitHub secrets of
P47K0/sites-template (see the handoff).

## Open items

- Cold start against the 30 s Worker budget is unmeasured until first deploy.
- Cosine check against Workers AI bge-m3 (expect >= 0.99) is still to do.
- Cost estimate to be filled in after measuring.
