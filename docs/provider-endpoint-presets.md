# Provider Endpoint Presets

This document tracks the built-in endpoint presets used by Workflow Generator. A preset is marked `verified` only when its base route and API role are checked against official provider documentation. If a model-family path, polling shape, or parameter field still needs provider-specific confirmation, it stays `needs_review`.

## Agnes AI

- Chat Completions: `https://apihub.agnes-ai.com/v1/chat/completions`, sync, `verified`.
- Images: `https://apihub.agnes-ai.com/v1/images/generations`, sync, `verified`.
- Videos: `https://apihub.agnes-ai.com/v1/videos`, async with polling at `/v1/videos/{task_id}`, `verified`.

Official sources checked:

- Agnes 2.0 Flash docs: https://agnes-ai.com/doc/agnes-20-flash
- Agnes Image 2.1 Flash docs: https://agnes-ai.com/doc/agnes-image-21-flash
- Agnes Image 2.0 Flash docs: https://agnes-ai.com/doc/agnes-image-20-flash
- Agnes Video V2.0 docs: https://agnes-ai.com/doc/agnes-video-v20

Built-in model defaults:

| Model | Route | Tasks | Important request fields |
| --- | --- | --- | --- |
| `agnes-2.0-flash` | `/chat/completions` | Chat, agent chat, tool calling, structured output | `messages`, `temperature`, `top_p`, `max_tokens`, `stream`, `tools`, `tool_choice`, `chat_template_kwargs.enable_thinking`, `thinking.type`, `thinking.budget_tokens` |
| `agnes-image-2.1-flash` | `/images/generations` | Text-to-image, image-to-image | `prompt`, `size`, `extra_body.image`, `extra_body.response_format` |
| `agnes-image-2.0-flash` | `/images/generations` | Image-to-image, image edit, multi-image composition | `prompt`, `size`, `seed`, `tags`, `extra_body.image`, `extra_body.response_format` |
| `agnes-video-v2.0` | `/videos` | Text-to-video, image-to-video, reference/keyframe video | `prompt`, `image`, `mode`, `height`, `width`, `num_frames`, `frame_rate`, `seed`, `negative_prompt`, `extra_body.image`, `extra_body.mode` |

Rules: Agnes AI is first in the built-in provider list and is the recommended full-modal starter. The catalog includes the newest text model, the newest image model, the still-documented Image 2.0 editing/composition model, and the newest video model so users can select the version-specific template without hand-writing JSON.

## OpenAI

- Responses: `/v1/responses`, sync. Official source: https://platform.openai.com/docs/api-reference/responses
- Chat Completions: `/v1/chat/completions`, sync. Official source: https://platform.openai.com/docs/api-reference/chat
- Images: `/v1/images/generations` plus image edit/variation family, sync or model-dependent. Official source: https://platform.openai.com/docs/api-reference/images
- Videos: `/v1/videos`, async. Official source: https://platform.openai.com/docs/api-reference/videos
- Audio Speech: `/v1/audio/speech`, sync/streaming. Official source: https://platform.openai.com/docs/api-reference/audio
- Audio Transcriptions: `/v1/audio/transcriptions`, multipart. Official source: https://platform.openai.com/docs/api-reference/audio
- Embeddings: `/v1/embeddings`, sync. Official source: https://platform.openai.com/docs/api-reference/embeddings

Rules: image models (`gpt-image-*`, `dall-e*`) do not route to Chat. Sora models route to Videos. Embedding models route to Embeddings.

## Volcengine Ark

- Chat Completions: `https://ark.cn-beijing.volces.com/api/v3/chat/completions`, sync, `verified`.
- Responses: `/responses`, disabled by default, `needs_review`.
- Seedream Image Generation: `/images/generations`, `needs_review`.
- Seedance Video / AudioVideo tasks: `/contents/generations/tasks`, async, `needs_review`.
- Embedding: `/embeddings`, `needs_review`.
- 3D Generation: `/contents/generations/tasks`, async and disabled by default, `needs_review`.

Official sources checked:

- Ark Chat API: https://www.volcengine.com/docs/82379/1302009
- Seedance 2.0 reference: https://www.volcengine.com/docs/82379/1393047
- Video task query docs: https://www.volcengine.com/docs/82379/1521675
- Seed3D task docs: https://www.volcengine.com/docs/82379/1856293

Rules: `seedream` routes to image endpoints. `seedance-2*` is treated as AudioVideo-capable and outputs `audio_video`; it is not TTS. Older Seedance models remain `needs_review` unless official model-specific audio capability is confirmed.

## Aliyun DashScope / Bailian

- OpenAI Compatible Chat: `/compatible-mode/v1/chat/completions`, sync, `needs_review`.
- Responses: `/compatible-mode/v1/responses`, disabled by default, `needs_review`.
- Text Generation: `/api/v1/services/aigc/text-generation/generation`, sync, `needs_review`.
- Multimodal Generation: `/api/v1/services/aigc/multimodal-generation/generation`, sync, `needs_review`.
- Qwen Omni: realtime/chat-compatible family, streaming/WebSocket model-dependent, `needs_review`.
- Image Generation: `/api/v1/services/aigc/image-generation/generation`, `needs_review`.
- Video Task: `/api/v1/services/aigc/video-generation/video-synthesis`, async, requires `X-DashScope-Async: enable`, `needs_review`.
- TTS / ASR / Embedding / Rerank: provider-specific routes, `needs_review`.

Official sources checked:

- Model Studio docs index: https://help.aliyun.com/zh/model-studio
- Qwen-Omni realtime docs: https://help.aliyun.com/zh/model-studio/realtime
- Qwen-Image docs: https://help.aliyun.com/zh/model-studio/qwen-image-api
- Wan text-to-video docs: https://help.aliyun.com/zh/model-studio/text-to-video-api-reference
- Wan image-to-video docs: https://help.aliyun.com/zh/model-studio/image-to-video-general-api-reference

Rules: video tasks are async and require the async header. Region and API key must match for region-scoped model families. Qwen-Omni is understanding/speech output, not image/video generation.

## DeepSeek

- OpenAI-compatible Chat: `https://api.deepseek.com/chat/completions`, sync, `verified`.
- Anthropic-compatible route: disabled by default, `needs_review`.

Official source: https://api-docs.deepseek.com/api/create-chat-completion

Rules: DeepSeek presets are text-only. No image, video, audio generation, embedding, or rerank capabilities are inferred unless official docs add them.

## MiniMax China

- Language: `https://api.minimaxi.com/v1/chat/completions`, sync, `verified`.
- TTS: `/t2a_v2`, sync/streaming model-dependent, `needs_review`.
- Video Generation: `/video_generation`, async, `verified`.
- Image Generation: `/image_generation`, `needs_review`.
- Music Generation: `/music_generation`, async, `needs_review`.

Official sources checked:

- China API overview: https://platform.minimaxi.com/docs/api-reference/api-overview
- OpenAI-compatible language API: https://platform.minimaxi.com/docs/api-reference/text-openai-api
- Image generation: https://platform.minimaxi.com/docs/api-reference/image-generation
- Video generation: https://platform.minimaxi.com/docs/api-reference/video-generation-t2v
- Text to speech: https://platform.minimaxi.com/docs/api-reference/speech-t2a-http
- Music generation: https://platform.minimaxi.com/docs/api-reference/music-generation
- China video generation: https://platform.minimaxi.com/docs/guides/video-generation

Rules: use `platform.minimaxi.com` / `api.minimaxi.com` for China presets. Do not mix in global-only `minimax.io` endpoints unless the endpoint is explicitly copied as a custom route.

## Custom OpenAI-Compatible

Custom presets are `unknown` by default. Chat Completions can be enabled by the user; images, videos, audio, embeddings, rerank, and custom JSON stay disabled until explicitly enabled and tested.

## Preset Lifecycle

- `system_preset`: never permanently deleted. Delete disables it and keeps `presetKey`.
- `user_custom`: soft-deleted by default.
- `migrated`: preserved from older configs.
- `imported`: preserved from external imports.

Restoration actions:

- Restore a disabled preset.
- Reset a modified preset to the built-in definition.
- Copy a system preset as a custom endpoint before editing.

## Parameter Safety

Regular users should edit typed ParameterSchema fields. Raw JSON remains an advanced override. The router validates task, input modalities, endpoint profile, schema, adapter, and required parameters before calling a provider.
